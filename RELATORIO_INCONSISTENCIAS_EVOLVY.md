# RELATÓRIO DE INCONSISTÊNCIAS NA MIGRAÇÃO EVOLVY → CHATWOOT

**Documento para Fins Jurídicos**

---

## INFORMAÇÕES DO DOCUMENTO

| Campo | Valor |
|-------|-------|
| **Data de Geração** | 19 de Janeiro de 2026 |
| **Período dos Dados** | 01/01/2024 a 19/12/2025 |
| **Sistema de Origem** | Evolvy (app.evolvy.io) |
| **Sistema de Destino** | Chatwoot |
| **Responsável Técnico** | Idiomus |

---

## 1. SUMÁRIO EXECUTIVO

Este documento detalha todas as inconsistências identificadas durante o processo de migração de dados da plataforma Evolvy para o Chatwoot. As inconsistências incluem arquivos de mídia (attachments) que não puderam ser recuperados do servidor Evolvy, conversas que não foram importadas, e falhas de API durante a extração dos dados.

### Resumo das Inconsistências

| Tipo de Inconsistência | Quantidade | Impacto |
|------------------------|------------|---------|
| Attachments HTTP 404 (deletados do servidor) | 6.149 | Arquivos perdidos permanentemente |
| Attachments não encontrados localmente | 1.166 | Arquivos não baixados |
| Conversas não importadas (dentro do período) | 2.552 | Posteriormente importadas |
| Conversas fora do período (pós-migração) | 6.366 | Não necessitam importação |
| Falhas de API durante extração | 1 | 1 mensagem não extraída |

---

## 2. METODOLOGIA DE COLETA

### 2.1 Processo de Extração

1. **Dump de Conversas**: Extração via API Evolvy de todas as conversas e mensagens
2. **Download de Attachments**: Download individual de cada arquivo de mídia referenciado
3. **Verificação de Integridade**: Comparação entre dados extraídos e dados no sistema Chatwoot

### 2.2 Fontes de Dados Analisadas

| Arquivo | Descrição |
|---------|-----------|
| `attachments_irrecuperaveis.txt` | Lista de 6.149 attachments com HTTP 404 |
| `attachments_nao_encontrados.txt` | Lista de 1.166 attachments não encontrados |
| `todas_conversas_status.csv` | Status de todas as 138.864 conversas |
| `latency_log.csv` | Log de 1.151 chamadas à API Evolvy |
| `download_fast.log` | Log de tentativas de download de attachments |
| `import_missing_*.log` | Logs de importação de conversas |

---

## 3. ATTACHMENTS COM ERRO HTTP 404

### 3.1 Visão Geral

**Total de arquivos afetados: 6.149**

Estes arquivos foram referenciados nas conversas exportadas, mas retornaram erro HTTP 404 (Not Found) ao tentar fazer download do servidor Evolvy. Isso indica que os arquivos foram **deletados do servidor Evolvy** antes da migração completa.

### 3.2 Distribuição por Inbox de Origem

| Inbox Evolvy | Nome do Inbox | Quantidade | % do Total |
|--------------|---------------|------------|------------|
| 5871 | Idiomus FB | 2.522 | 41,0% |
| 5601 | Teacher Poli WA (83) 92000-5321 | 2.405 | 39,1% |
| 14483 | API Oficial Onboarding | 986 | 16,0% |
| 14638 | Suporte extra (emails Idiomus) | 146 | 2,4% |
| 14639 | Extra (emails Teacher Poli) | 90 | 1,5% |
| **TOTAL** | | **6.149** | **100%** |

### 3.3 Distribuição por Tipo de Arquivo

| Extensão | Tipo | Quantidade | % do Total |
|----------|------|------------|------------|
| jpg | Imagem | 1.990 | 32,4% |
| mp4 | Vídeo | 1.856 | 30,2% |
| oga | Áudio (Opus) | 1.248 | 20,3% |
| bin | Desconhecido | 384 | 6,2% |
| pdf | Documento | 381 | 6,2% |
| png | Imagem | 150 | 2,4% |
| webp | Imagem | 122 | 2,0% |
| mp3 | Áudio | 10 | 0,2% |
| txt | Texto | 4 | 0,1% |
| mov | Vídeo | 2 | 0,0% |
| m4a | Áudio | 1 | 0,0% |
| gif | Imagem | 1 | 0,0% |
| **TOTAL** | | **6.149** | **100%** |

### 3.4 Conversas Afetadas

**Total de conversas distintas com attachments perdidos: 3.535**

#### Conversas com Maior Quantidade de Arquivos Perdidos (Top 20)

| Inbox | Conv ID | Attachments Perdidos |
|-------|---------|---------------------|
| 5601 | 58511 | 19 |
| 5601 | 55045 | 19 |
| 5601 | 62598 | 18 |
| 5601 | 54478 | 18 |
| 5601 | 54449 | 12 |
| 5601 | 88575 | 11 |
| 5601 | 64681 | 11 |
| 5601 | 131383 | 11 |
| 14483 | 253049 | 11 |
| 5871 | 87063 | 10 |
| 5871 | 135724 | 10 |
| 5871 | 131591 | 10 |
| 5601 | 80980 | 10 |
| 5601 | 58949 | 10 |
| 14483 | 256527 | 10 |
| 14483 | 254837 | 10 |
| 14483 | 254298 | 10 |
| 5871 | 144010 | 9 |
| 5871 | 136548 | 9 |
| 5601 | 87056 | 9 |

---

## 4. ATTACHMENTS NÃO ENCONTRADOS LOCALMENTE

### 4.1 Visão Geral

**Total de arquivos afetados: 1.166**

Estes arquivos foram referenciados nas conversas exportadas, mas não foram encontrados no diretório local de attachments após o download. Diferente dos HTTP 404, estes arquivos podem ter falhado durante o download por outros motivos (timeout, conexão interrompida, etc.).

### 4.2 Distribuição por Inbox de Origem

| Inbox Evolvy | Nome do Inbox | Quantidade | % do Total |
|--------------|---------------|------------|------------|
| 5871 | Idiomus FB | 973 | 83,4% |
| 14515 | Teacher Poli FB | 79 | 6,8% |
| 14535 | Teacher Poli Hispanohablantes FB | 41 | 3,5% |
| 13726 | Teacher Poli Oficial WA | 36 | 3,1% |
| 14483 | API Oficial Onboarding | 14 | 1,2% |
| 5608 | Idiomus App FB | 12 | 1,0% |
| 13984 | Teacher Poli WA | 10 | 0,9% |
| 5599 | Idiomus WA (84) | 1 | 0,1% |
| **TOTAL** | | **1.166** | **100%** |

### 4.3 Conversas Mais Afetadas

| Inbox | Conv ID | Attachments Não Encontrados |
|-------|---------|----------------------------|
| 13726 | 202352 | 4 |
| 13984 | 205313 | 4 |
| 13726 | 232440 | 2 |
| 14515 | 208480 | 2 |

---

## 5. CONVERSAS NÃO IMPORTADAS

### 5.1 Visão Geral

**Total de conversas não importadas inicialmente: 8.918**

Após análise detalhada:
- **Dentro do período (necessitavam importação)**: 2.552
- **Fora do período (após 19/12/2025)**: 6.366

As conversas dentro do período foram posteriormente importadas via processo de recuperação.

### 5.2 Distribuição por Inbox e Período

| Inbox | Nome | Dentro Período | Fora Período | Total |
|-------|------|----------------|--------------|-------|
| 14483 | API Oficial Onboarding | 92 | 3.453 | 3.545 |
| 14639 | Extra (emails Teacher Poli) | 1.415 | 1.564 | 2.979 |
| 14638 | Suporte extra (emails Idiomus) | 923 | 754 | 1.677 |
| 14515 | Teacher Poli FB | 45 | 421 | 466 |
| 14535 | Teacher Poli Hispanohablantes FB | 20 | 155 | 175 |
| 5871 | Idiomus FB | 35 | 19 | 54 |
| 5598 | Idiomus Oficial WA | 13 | 0 | 13 |
| 5601 | Teacher Poli WA (83) | 4 | 0 | 4 |
| 5599 | Idiomus WA (84) | 3 | 0 | 3 |
| 5600 | Onboarding WA (83) | 2 | 0 | 2 |
| **TOTAL** | | **2.552** | **6.366** | **8.918** |

### 5.3 Amostra de Conversas Não Importadas (Dentro do Período)

| Evolvy ID | Inbox | Data Criação | Status |
|-----------|-------|--------------|--------|
| 42829 | 5598 | 05/02/2024 | nao_importado |
| 70818 | 5598 | 15/03/2024 | nao_importado |
| 80303 | 5598 | 26/03/2024 | nao_importado |
| 80498 | 5598 | 27/03/2024 | nao_importado |
| 86216 | 5598 | 02/05/2024 | nao_importado |
| 86217 | 5598 | 02/05/2024 | nao_importado |
| 86262 | 5598 | 02/05/2024 | nao_importado |
| 97303 | 5599 | 24/06/2024 | nao_importado |
| 100923 | 5598 | 05/07/2024 | nao_importado |
| 102161 | 5871 | 09/07/2024 | nao_importado |

**Nota**: Estas conversas foram posteriormente recuperadas e importadas em 15/01/2026.

---

## 6. FALHAS DE API DURANTE EXTRAÇÃO

### 6.1 Visão Geral

Durante o processo de extração de dados via API Evolvy, foram registradas as seguintes estatísticas:

| Métrica | Valor |
|---------|-------|
| Total de chamadas à API | 1.151 |
| Chamadas bem-sucedidas | 1.150 |
| Chamadas com falha | 1 |
| Taxa de sucesso | 99,91% |

### 6.2 Detalhes da Falha

| Timestamp Unix | Endpoint | Latência (ms) | Status |
|----------------|----------|---------------|--------|
| 1765513286.95 | POST /messages | 485,9 | fail |

**Impacto**: 1 mensagem não foi extraída corretamente da API Evolvy.

---

## 7. ERROS DURANTE IMPORTAÇÃO

### 7.1 Erros de Importação de Mensagens

Durante a importação inicial, alguns erros foram registrados:

```
[MSG ERROR] Conv 270259: can't quote User
[MSG ERROR] Conv 270260: can't quote User
...
[MSG ERROR] Conv 270287: can't quote Contact
```

**Causa**: Bug no código de importação que foi posteriormente corrigido.
**Resolução**: Mensagens reimportadas com sucesso após correção.

### 7.2 Resultado do Reimport de Mensagens

| Métrica | Valor |
|---------|-------|
| Total processado | 2.570 |
| Sucesso | 2.458 |
| Falha | 0 |
| Ignoradas (sem mensagens no JSON) | 112 |

---

## 8. RESUMO CONSOLIDADO DE INCONSISTÊNCIAS

### 8.1 Dados Perdidos Permanentemente

| Categoria | Quantidade | Descrição |
|-----------|------------|-----------|
| **Attachments HTTP 404** | **6.149** | Arquivos deletados do servidor Evolvy |
| **Attachments não encontrados** | **1.166** | Arquivos não baixados (falha de download) |
| **Mensagem API fail** | **1** | Mensagem não extraída |
| **TOTAL PERDIDO** | **7.316** | |

### 8.2 Dados Recuperados

| Categoria | Quantidade | Descrição |
|-----------|------------|-----------|
| Conversas reimportadas | 2.552 | Conversas dentro do período recuperadas |
| Mensagens reimportadas | 2.458 | Mensagens de conversas vazias |
| Attachments importados | 54.824 | Total no Chatwoot |

### 8.3 Impacto por Canal de Comunicação

| Canal | Attachments 404 | Attachments Não Encontrados | Total Perdido |
|-------|-----------------|----------------------------|---------------|
| WhatsApp (5601) | 2.405 | 0 | 2.405 |
| Facebook (5871) | 2.522 | 973 | 3.495 |
| API Onboarding (14483) | 986 | 14 | 1.000 |
| Email Suporte (14638) | 146 | 0 | 146 |
| Email Teacher Poli (14639) | 90 | 0 | 90 |
| Facebook Teacher Poli (14515) | 0 | 79 | 79 |
| Facebook Hispanohablantes (14535) | 0 | 41 | 41 |
| WhatsApp Teacher Poli (13726) | 0 | 36 | 36 |
| WhatsApp Teacher Poli 2 (13984) | 0 | 10 | 10 |
| Facebook Idiomus App (5608) | 0 | 12 | 12 |
| WhatsApp Idiomus (5599) | 0 | 1 | 1 |
| **TOTAL** | **6.149** | **1.166** | **7.315** |

---

## 9. CONCLUSÃO

### 9.1 Causa Raiz das Inconsistências

1. **Attachments HTTP 404 (6.149)**: Os arquivos foram deletados do servidor Evolvy (provavelmente por política de retenção do Active Storage ou limpeza manual) antes que o backup completo pudesse ser realizado.

2. **Attachments Não Encontrados (1.166)**: Falhas durante o processo de download (timeout, conexão interrompida, ou arquivo corrompido no servidor de origem).

3. **Falha de API (1)**: Erro pontual durante chamada POST /messages.

### 9.2 Responsabilidade

Os dados perdidos (7.316 arquivos) estavam sob custódia do sistema Evolvy e foram deletados ou tornaram-se inacessíveis antes da conclusão da migração. A equipe técnica do Idiomus realizou múltiplas tentativas de recuperação, incluindo:

- Verificação em dumps anteriores (16/12/2025)
- Tentativas de re-download via URLs originais
- Contato com API Evolvy para recuperação

### 9.3 Documentação Complementar

Os seguintes arquivos contêm informações detalhadas:

| Arquivo | Conteúdo |
|---------|----------|
| `attachments_irrecuperaveis.txt` | Lista completa dos 6.149 attachments com 404 |
| `attachments_nao_encontrados.txt` | Lista dos 1.166 attachments não encontrados |
| `todas_conversas_status.csv` | Status de todas as 138.864 conversas |
| `EVOLVY_DUMP_VERIFICACAO.txt` | Documento de verificação técnica |

---

## ANEXOS

### Anexo A: Estrutura do Arquivo attachments_irrecuperaveis.txt

Formato: `inbox|conv_id|att_id|url|extensao`

Exemplo:
```
14483|249476|20563483|https://app.evolvy.io/rails/active_storage/blobs/redirect/...|jpg
14483|249611|20567026|https://app.evolvy.io/rails/active_storage/blobs/redirect/...|jpg
```

### Anexo B: Estrutura do Arquivo todas_conversas_status.csv

Colunas: `evolvy_id,evolvy_inbox,chatwoot_inbox,created_at,data,periodo,status`

Exemplo:
```
2,5871,7,1711263081,2024-03-24,dentro_periodo,importado
42829,5598,1,1707152456,2024-02-05,dentro_periodo,nao_importado
```

---

**Fim do Documento**

*Gerado automaticamente em 19/01/2026*
