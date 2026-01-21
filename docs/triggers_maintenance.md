# Triggers Customizados - Chatwoot Idiomus

> Documentação de triggers personalizados no banco de dados PostgreSQL

## Triggers Ativos

### 1. `trg_conversations_round_robin`

**Tabela:** `conversations`
**Eventos:** `BEFORE INSERT`, `BEFORE UPDATE OF team_id`
**Função:** `fn_round_robin_assignment()`
**Criado em:** 2026-01-21

**Descrição:**
Atribui automaticamente agentes em round-robin quando uma equipe é atribuída a uma conversa e não há agente definido.

**Comportamento:**
- Só executa se `team_id` estiver definido E `assignee_id` estiver vazio
- Verifica se a equipe está habilitada na tabela `custom_round_robin_config`
- Atribui o próximo agente da equipe em ordem circular
- Registra a atribuição na tabela de log (se habilitado)
- Auto-limpa logs antigos (1% de chance por execução)

**Equipes configuradas:**
| team_id | Nome | Membros |
|---------|------|---------|
| 3 | email support | Juliana Nizer, Fabio |

---

## Tabelas de Suporte

### `custom_round_robin_config`
Configuração de round-robin por equipe.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| team_id | INTEGER | FK para teams.id |
| enabled | BOOLEAN | Habilita/desabilita round-robin |
| enable_logging | BOOLEAN | Habilita/desabilita registro de log |
| log_retention_days | INTEGER | Dias para manter logs (default: 30) |
| description | TEXT | Descrição da configuração |

### `custom_round_robin_state`
Estado atual do round-robin por equipe.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| team_id | INTEGER | FK para teams.id |
| last_assigned_user_id | INTEGER | Último agente atribuído |
| assignment_count | INTEGER | Total de atribuições |
| updated_at | TIMESTAMP | Última atualização |

### `custom_round_robin_log`
Log de auditoria das atribuições automáticas.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| conversation_id | INTEGER | ID da conversa |
| display_id | INTEGER | Display ID da conversa |
| team_id | INTEGER | ID da equipe |
| assigned_user_id | INTEGER | ID do agente atribuído |
| assigned_user_name | TEXT | Nome do agente |
| event_type | TEXT | INSERT ou UPDATE |
| created_at | TIMESTAMP | Data/hora da atribuição |

---

## Comandos de Manutenção

### Listar todos os triggers
```sql
SELECT
  tgname AS trigger_name,
  relname AS table_name,
  CASE tgenabled
    WHEN 'O' THEN 'enabled'
    WHEN 'D' THEN 'disabled'
  END AS status,
  proname AS function_name
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE NOT tgisinternal
ORDER BY relname, tgname;
```

### Ver código da função
```sql
SELECT prosrc FROM pg_proc WHERE proname = 'fn_round_robin_assignment';
```

### Desabilitar trigger (sem deletar)
```sql
ALTER TABLE conversations DISABLE TRIGGER trg_conversations_round_robin;
```

### Reabilitar trigger
```sql
ALTER TABLE conversations ENABLE TRIGGER trg_conversations_round_robin;
```

### Deletar trigger completamente
```sql
DROP TRIGGER trg_conversations_round_robin ON conversations;
DROP FUNCTION fn_round_robin_assignment();
DROP TABLE custom_round_robin_log;
DROP TABLE custom_round_robin_state;
DROP TABLE custom_round_robin_config;
```

---

## Configuração de Equipes

### Adicionar nova equipe ao round-robin
```sql
INSERT INTO custom_round_robin_config (team_id, enabled, enable_logging, log_retention_days, description)
VALUES (
  <TEAM_ID>,
  true,           -- habilitado
  true,           -- com logging
  30,             -- 30 dias de retenção
  'Descrição da equipe'
);
```

### Desabilitar round-robin para uma equipe
```sql
UPDATE custom_round_robin_config
SET enabled = false, updated_at = NOW()
WHERE team_id = <TEAM_ID>;
```

### Desabilitar logging (reduzir uso de disco)
```sql
UPDATE custom_round_robin_config
SET enable_logging = false, updated_at = NOW()
WHERE team_id = <TEAM_ID>;
```

---

## Monitoramento

### Ver últimas atribuições
```sql
SELECT * FROM custom_round_robin_log
ORDER BY created_at DESC LIMIT 20;
```

### Ver estatísticas por equipe
```sql
SELECT
  c.team_id,
  t.name,
  s.assignment_count,
  u.name AS ultimo_agente,
  s.updated_at
FROM custom_round_robin_config c
JOIN teams t ON c.team_id = t.id
LEFT JOIN custom_round_robin_state s ON c.team_id = s.team_id
LEFT JOIN users u ON s.last_assigned_user_id = u.id;
```

### Ver distribuição de atribuições
```sql
SELECT
  assigned_user_name,
  count(*) AS total_atribuicoes,
  max(created_at) AS ultima_atribuicao
FROM custom_round_robin_log
WHERE team_id = 3
GROUP BY assigned_user_name
ORDER BY total_atribuicoes DESC;
```

### Limpar logs manualmente
```sql
DELETE FROM custom_round_robin_log
WHERE created_at < NOW() - INTERVAL '7 days';
```

---

## Atribuição em Massa

### Forçar atribuição via trigger para conversas existentes

Para atribuir agentes automaticamente em conversas que já existem mas não têm agente atribuído, basta definir (ou redefinir) o `team_id`. O trigger será disparado para cada linha.

```sql
-- Atribuir equipe email support a todas conversas de email sem agente
UPDATE conversations SET team_id = 3
WHERE inbox_id IN (12, 13) AND assignee_id IS NULL;
```

**Como funciona:**
1. O `UPDATE` dispara o trigger `trg_conversations_round_robin`
2. O trigger verifica se `assignee_id` é NULL
3. Se NULL, atribui o próximo agente em round-robin
4. Registra no log (se habilitado)

**Considerações:**
- Para grandes volumes, considere fazer em batches:
  ```sql
  -- Batch de 1000 por vez
  UPDATE conversations SET team_id = 3
  WHERE id IN (
    SELECT id FROM conversations
    WHERE inbox_id IN (12, 13) AND assignee_id IS NULL
    LIMIT 1000
  );
  ```
- O log pode crescer rapidamente em atribuições em massa
- Considere desabilitar logging temporariamente para grandes volumes:
  ```sql
  UPDATE custom_round_robin_config SET enable_logging = false WHERE team_id = 3;
  -- executar atribuição em massa
  UPDATE custom_round_robin_config SET enable_logging = true WHERE team_id = 3;
  ```

---

## Troubleshooting

### Trigger não está atribuindo agente
1. Verificar se a equipe está habilitada:
   ```sql
   SELECT * FROM custom_round_robin_config WHERE team_id = <ID>;
   ```
2. Verificar se a equipe tem membros:
   ```sql
   SELECT * FROM team_members WHERE team_id = <ID>;
   ```
3. Verificar se `assignee_id` já estava preenchido (trigger não sobrescreve)

### Agente sempre o mesmo
1. Verificar estado do round-robin:
   ```sql
   SELECT * FROM custom_round_robin_state WHERE team_id = <ID>;
   ```
2. Verificar se há mais de um membro na equipe

### Logs crescendo muito
1. Reduzir período de retenção:
   ```sql
   UPDATE custom_round_robin_config
   SET log_retention_days = 7 WHERE team_id = <ID>;
   ```
2. Ou desabilitar logging:
   ```sql
   UPDATE custom_round_robin_config
   SET enable_logging = false WHERE team_id = <ID>;
   ```
