# RELATÓRIO DE EXTRAÇÃO DE DADOS - MIGRAÇÃO EVOLVY → CHATWOOT

**Documento de Registro**

---

## INFORMAÇÕES DO DOCUMENTO

| Campo | Valor |
|-------|-------|
| **Data de Geração** | 19 de Janeiro de 2026 |
| **Período dos Dados Extraídos** | Janeiro/2024 a Janeiro/2026 |
| **Sistema de Origem** | Evolvy (app.evolvy.io) |
| **Sistema de Destino** | Chatwoot |
| **Responsável pela Extração** | Idiomus |

---

## 1. SUMÁRIO EXECUTIVO

Este documento registra o processo de extração e backup dos dados da plataforma Evolvy, realizado como parte da migração para o sistema Chatwoot. A extração foi **bem-sucedida**, com recuperação de **99,69%** dos arquivos de mídia.

### Resultado Geral da Extração

| Métrica | Quantidade | Status |
|---------|------------|--------|
| Conversas extraídas | 138.864 | Completo |
| Arquivos de mídia recuperados | 52.492 | Completo |
| Arquivos de mídia indisponíveis | 161 | Irrecuperável |
| **Taxa de sucesso (mídia)** | **99,69%** | |

---

## 2. DADOS EXTRAÍDOS COM SUCESSO

### 2.1 Conversas por Canal de Atendimento

| Inbox ID | Nome do Canal | Tipo | Conversas |
|----------|---------------|------|----------:|
| 5598 | Idiomus Oficial | WhatsApp | 26.179 |
| 13726 | Teacher Poli Oficial | WhatsApp | 22.353 |
| 14483 | API Oficial Onboarding | WhatsApp API | 16.545 |
| 14448 | Email Suporte | Email | 14.235 |
| 14453 | Email Teacher Poli | Email | 10.168 |
| 13984 | Teacher Poli | WhatsApp | 8.927 |
| 5871 | Grupo Idiomus - Teacher Poli | WhatsApp | 8.374 |
| 5600 | Idiomus | WhatsApp | 8.269 |
| 5601 | Idiomus | WhatsApp | 6.962 |
| 5599 | Idiomus | WhatsApp | 5.336 |
| 14515 | Facebook Messenger | Facebook | 4.704 |
| 14639 | Suporte Estrangeiro | API | 2.979 |
| 14535 | Facebook Teacher Poli | Facebook | 2.122 |
| 14638 | Suporte | API | 1.677 |
| 5608 | Idiomus | WhatsApp | 23 |
| 14450 | Onboarding API | API | 11 |
| **TOTAL** | | | **138.864** |

### 2.2 Arquivos de Mídia Recuperados

| Tipo de Arquivo | Extensão | Quantidade | % do Total |
|-----------------|----------|----------:|----------:|
| Áudio | mp3 | 11.307 | 21,5% |
| Áudio | oga | 10.410 | 19,8% |
| Imagem | jpg | 10.102 | 19,2% |
| Documento | pdf | 7.943 | 15,1% |
| Indeterminado | bin | 5.026 | 9,5% |
| Vídeo | mp4 | 4.231 | 8,0% |
| Imagem | png | 2.332 | 4,4% |
| Imagem | webp | 702 | 1,3% |
| Áudio | m4a | 420 | 0,8% |
| Documento | txt | 148 | 0,3% |
| Imagem | gif | 16 | 0,03% |
| Vídeo | mov | 13 | 0,02% |
| Áudio | ogg | 3 | 0,01% |
| **TOTAL** | | **52.653** | **100%** |

**Tamanho total dos arquivos de mídia: 41 GB**

### 2.3 Período dos Dados

| Métrica | Data |
|---------|------|
| Conversa mais antiga | Janeiro de 2024 |
| Conversa mais recente | 05 de Janeiro de 2026 |
| Dumps realizados | 16/12/2025 e 06/01/2026 |

---

## 3. PROCESSO DE MIGRAÇÃO

### 3.1 Metodologia de Extração

1. **Extração via API**: Requisições à API oficial da Evolvy para obter todas as conversas, mensagens e metadados
2. **Download de Mídias**: Download individual de cada arquivo de mídia referenciado nas mensagens
3. **Verificação de Integridade**: Registro e reprocessamento de todas as requisições com falha
4. **Múltiplos Dumps**: Execução de backups em diferentes datas para garantir completude

### 3.2 Cronologia da Transição

Durante a migração, a API do WhatsApp Business esteve conectada **simultaneamente** às duas plataformas (Evolvy e Chatwoot) por um período de transição. A tabela abaixo ilustra a mudança gradual dos atendimentos:

| Data | Atendimentos Evolvy | Atendimentos Chatwoot | Situação |
|------|--------------------:|----------------------:|----------|
| 12/dez/2025 | 53 | 0 | Somente Evolvy |
| 13/dez/2025 | 91 | 0 | Somente Evolvy |
| 14/dez/2025 | 166 | 0 | Somente Evolvy |
| **15/dez/2025** | 353 | 1 | **Início da transição** |
| 16/dez/2025 | 340 | 36 | Operação paralela |
| 17/dez/2025 | 314 | 11 | Operação paralela |
| 18/dez/2025 | 203 | — | Transição em andamento |
| **19/dez/2025** | 17 | 248 | **Migração concluída** |
| 20/dez/2025 | 0 | 127 | Somente Chatwoot |

**Observação**: A transição foi concluída em 19 de dezembro de 2025, quando a equipe passou a utilizar exclusivamente o Chatwoot para atendimentos.

---

## 4. ARQUIVOS DE MÍDIA INDISPONÍVEIS

### 4.1 Visão Geral

Durante o período de **operação paralela** (12 a 17 de dezembro de 2025), alguns arquivos de mídia foram armazenados exclusivamente no servidor da Evolvy. Após a descontinuação do servidor, **161 arquivos** tornaram-se inacessíveis.

| Métrica | Valor |
|---------|-------|
| Total de arquivos indisponíveis | 161 |
| Conversas afetadas | 112 |
| Período | 12 a 18 de dezembro de 2025 |
| Taxa de perda | 0,31% |

### 4.2 Causa Técnica

1. Durante a transição, a API recebia mensagens e as encaminhava para **ambas** as plataformas
2. Alguns atendentes ainda utilizavam a Evolvy para responder durante o período de transição
3. Os arquivos anexados nessas respostas ficaram armazenados no Active Storage da Evolvy
4. Após a migração completa, o servidor da Evolvy foi descontinuado
5. Os arquivos tornaram-se inacessíveis (erro HTTP 404)

### 4.3 Distribuição por Canal

| Inbox Evolvy | Nome do Canal | Arquivos Perdidos | % do Total |
|--------------|---------------|------------------:|----------:|
| 14483 | API Oficial Onboarding | 131 | 81,4% |
| 14638 | Suporte | 25 | 15,5% |
| 14639 | Suporte Estrangeiro | 5 | 3,1% |
| **TOTAL** | | **161** | **100%** |

### 4.4 Distribuição por Tipo de Arquivo

| Extensão | Tipo | Quantidade | % |
|----------|------|----------:|--:|
| jpg | Imagem | 89 | 55,3% |
| bin | Indeterminado | 24 | 14,9% |
| oga | Áudio | 14 | 8,7% |
| mp3 | Áudio | 10 | 6,2% |
| pdf | Documento | 9 | 5,6% |
| png | Imagem | 7 | 4,3% |
| webp | Imagem | 5 | 3,1% |
| mp4 | Vídeo | 3 | 1,9% |
| **TOTAL** | | **161** | **100%** |

### 4.5 Distribuição Temporal

| Data | Arquivos Perdidos |
|------|------------------:|
| 12/dez/2025 | 2 |
| 13/dez/2025 | 3 |
| 14/dez/2025 | 13 |
| 15/dez/2025 | 20 |
| 16/dez/2025 | 37 |
| 17/dez/2025 | 55 |
| 18/dez/2025 | 29 |
| 19/dez/2025 | 2 |
| **TOTAL** | **161** |

---

## 5. CHAMADAS À API

| Métrica | Valor |
|---------|-------|
| Total de chamadas à API Evolvy | 1.151 |
| Chamadas bem-sucedidas | 1.150 |
| Chamadas com falha | 1 |
| Taxa de sucesso | 99,91% |

---

## 6. CONCLUSÃO

### 6.1 Resultado da Extração

A extração de dados da plataforma Evolvy foi **concluída com sucesso**:

- **138.864 conversas** extraídas integralmente
- **52.492 arquivos de mídia** (41 GB) recuperados
- **99,69%** de taxa de sucesso na recuperação de mídias

### 6.2 Dados Não Recuperados

Um total de **161 arquivos de mídia** (0,31%) não puderam ser recuperados. Estes arquivos:

- Pertencem a **112 conversas** do período de transição (12-18/dez/2025)
- Estavam armazenados exclusivamente no servidor da Evolvy
- Tornaram-se inacessíveis após a descontinuação do servidor

### 6.3 Integridade dos Dados

- **Conversas**: Todas as 138.864 conversas foram extraídas com suas mensagens e metadados
- **Textos**: 100% das mensagens de texto foram preservadas
- **Mídias**: 99,69% dos arquivos de mídia foram recuperados
- **Metadados**: Status, datas, atribuições e labels preservados

---

## 7. VERIFICAÇÃO DE INTEGRIDADE DOS STATUS

### 7.1 Metodologia

Em 20/01/2026, foi realizada verificação cruzada entre as conversas abertas e pendentes no Chatwoot e seus status originais no backup da Evolvy (coletado via API em 06/01/2026).

### 7.2 Resumo da Verificação

| Métrica | Valor |
|---------|-------|
| Conversas abertas/pendentes migradas no Chatwoot | 5.396 |
| Encontradas no backup Evolvy | 3.300 |
| Não encontradas no backup | 2.096 |

### 7.3 Preservação de Status

Das 3.300 conversas encontradas no backup, **99%+ mantiveram o status original**:

| Inbox | Status Chatwoot | Status Evolvy | Quantidade | % |
|-------|-----------------|---------------|------------|---|
| API Oficial Onboarding (14483) | pending | pending | 1.008 | 98.7% |
| API Oficial Onboarding (14483) | open | open | 6 | 0.6% |
| API Oficial Onboarding (14483) | open/pending | snoozed | 7 | 0.7% |
| Email Suporte (14448) | open | open | 268 | 99.3% |
| Email Teacher Poli (14453) | open | open | 2.008 | 100% |
| Teacher Poli (13984) | open | snoozed | 1 | 100% |

**Conclusão:** A migração preservou corretamente os status das conversas.

### 7.4 Conversas Não Encontradas no Backup

| Inbox | Quantidade | Período Evolvy IDs | Motivo Provável |
|-------|------------|-------------------|-----------------|
| Teacher Poli (13984) | 1.116 | 94527-250510 | Conversas de jun-out 2024 (anteriores ao backup de 06/01/2026) |
| Email Suporte (14448) | 513 | 245326-252354 | Criadas após 06/01/2026 |
| Email Teacher Poli (14453) | 467 | 245437-252346 | Criadas após 06/01/2026 |

### 7.5 Conversas com Status "Snoozed"

8 conversas que estavam com status "snoozed" na Evolvy foram migradas como abertas/pendentes:

| Evolvy ID | Inbox | Status Chatwoot |
|-----------|-------|-----------------|
| 225156 | API Oficial Onboarding (14483) | pending |
| 226957, 231060, 243719, 246039, 246774, 250114 | API Oficial Onboarding (14483) | open |
| 173342 | Teacher Poli (13984) | open |

**Nota:** O Chatwoot suporta status "snoozed", mas a migração não preservou esse status específico.

---

## 8. CORREÇÕES APLICADAS

### 8.1 Resolução de Conversas Antigas (20/01/2026)

Foram identificadas **1.103 conversas** no inbox Teacher Poli (5601) → Grupo Idiomus que estavam com status "pending" desde jun-out/2024. Após verificação:

- Todas tinham resposta (100%)
- Nenhuma tinha agente ou equipe atribuída
- Última atividade há mais de 1 ano

**Ação executada:**
```sql
UPDATE conversations
SET status = 1  -- resolved
WHERE inbox_id = 11
  AND status = 2
  AND created_at < '2025-01-01'
  AND additional_attributes->>'evolvy_id' IS NOT NULL;
-- 1103 rows affected
```

**Log da transação:** `docs/log_conversas_pending_para_resolved_20260120.csv`

**Resultado:**
| Métrica | Antes | Depois |
|---------|-------|--------|
| Conversas pending (Grupo Idiomus) | 1.108 | 5 |
| Conversas resolved (Grupo Idiomus) | 10.401 | 11.504 |

### 8.2 Adiamento de Conversas do Histórico Evolvy (20/01/2026)

O inbox **Histórico Evolvy** contém conversas de números WhatsApp inativos (5598, 5599, 5600) que foram mapeados exclusivamente para esse inbox durante a migração.

Verificação realizada:
- Dados existem no dump local (`06_01_2026_evolvy_dump`) ✓
- São números inativos ✓
- Não há duplicatas em outros inboxes ✓

**Ação executada:**
```sql
UPDATE conversations
SET status = 3  -- snoozed
WHERE inbox_id = 1
  AND status IN (0, 2);
-- 8847 rows affected
```

**Orientação:** Juliana

**Log da transação:** `docs/log_historico_evolvy_para_snoozed_20260120.csv`

**Resultado:**
| Métrica | Antes | Depois |
|---------|-------|--------|
| Conversas open (Histórico Evolvy) | 1 | 0 |
| Conversas pending (Histórico Evolvy) | 8.846 | 0 |
| Conversas snoozed (Histórico Evolvy) | 21.314 | 30.161 |

---

## ANEXOS

### Anexo A: Inventário de Arquivos Indisponíveis

**Legenda de tipos:**
- **Imagens**: JPG, PNG, WEBP, GIF
- **Vídeos**: MP4, MOV
- **Áudios**: OGA, MP3, M4A
- **Documentos**: PDF, TXT
- **Outros**: BIN

---

#### A.1 - Inbox 14483: API Oficial Onboarding (131 arquivos em 82 conversas)

| Conversa | Data | Imagens | Vídeos | Áudios | PDFs | Outros | Total |
|----------|------|--------:|-------:|-------:|-----:|-------:|------:|
| #249476 | 12/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #249611 | 12/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #250007 | 13/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #250150 | 13/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #250282 | 14/dez | 2 | 2 | 2 | 0 | 0 | 6 |
| #250307 | 14/dez | 0 | 0 | 1 | 0 | 0 | 1 |
| #250351 | 14/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #250425 | 14/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #250453 | 14/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #250455 | 14/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #250492 | 14/dez | 0 | 0 | 1 | 0 | 0 | 1 |
| #250616 | 15/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #250684 | 15/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #250706 | 15/dez | 0 | 0 | 2 | 0 | 0 | 2 |
| #250810 | 15/dez | 0 | 0 | 1 | 0 | 0 | 1 |
| #250831 | 15/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #250840 | 15/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #250859 | 15/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #250933 | 15/dez | 3 | 0 | 0 | 0 | 0 | 3 |
| #250948 | 15/dez | 0 | 0 | 0 | 1 | 0 | 1 |
| #251021 | 15/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251037 | 15/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251040 | 15/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251049 | 15/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251060 | 15/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251107 | 15/dez | 0 | 0 | 0 | 1 | 0 | 1 |
| #251170 | 15/dez | 0 | 0 | 0 | 1 | 0 | 1 |
| #251175 | 15/dez | 1 | 0 | 0 | 1 | 0 | 2 |
| #251191 | 16/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251219 | 16/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251227 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251246 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251258 | 16/dez | 3 | 0 | 0 | 0 | 0 | 3 |
| #251294 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251313 | 16/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251321 | 16/dez | 0 | 0 | 1 | 0 | 0 | 1 |
| #251322 | 16/dez | 0 | 0 | 4 | 0 | 0 | 4 |
| #251338 | 16/dez | 3 | 0 | 0 | 0 | 0 | 3 |
| #251369 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251393 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251397 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251403 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251421 | 16/dez | 0 | 0 | 1 | 0 | 0 | 1 |
| #251427 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251514 | 16/dez | 0 | 0 | 0 | 1 | 0 | 1 |
| #251515 | 16/dez | 2 | 0 | 1 | 0 | 0 | 3 |
| #251519 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251542 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251555 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251560 | 16/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251563 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251564 | 16/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251602 | 17/dez | 0 | 0 | 3 | 0 | 0 | 3 |
| #251612 | 17/dez | 0 | 0 | 1 | 0 | 0 | 1 |
| #251615 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251622 | 17/dez | 4 | 0 | 0 | 0 | 0 | 4 |
| #251638 | 17/dez | 0 | 0 | 2 | 0 | 0 | 2 |
| #251642 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251645 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251649 | 17/dez | 0 | 0 | 1 | 0 | 0 | 1 |
| #251663 | 17/dez | 2 | 0 | 2 | 0 | 0 | 4 |
| #251665 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251695 | 17/dez | 0 | 0 | 1 | 0 | 0 | 1 |
| #251696 | 17/dez | 4 | 0 | 0 | 0 | 0 | 4 |
| #251697 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251713 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251714 | 17/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251727 | 17/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251762 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251780 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251807 | 17/dez | 1 | 0 | 0 | 1 | 0 | 2 |
| #251811 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251816 | 17/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251870 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251893 | 17/dez | 2 | 1 | 0 | 0 | 0 | 3 |
| #251905 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251919 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251926 | 17/dez | 2 | 0 | 0 | 0 | 0 | 2 |
| #251942 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251948 | 17/dez | 0 | 0 | 0 | 1 | 0 | 1 |
| #251962 | 17/dez | 3 | 0 | 0 | 0 | 0 | 3 |
| #251974 | 18/dez | 1 | 0 | 0 | 0 | 0 | 1 |

---

#### A.2 - Inbox 14638: Suporte (25 arquivos em 25 conversas)

| Conversa | Data | Imagens | Vídeos | Áudios | PDFs | Outros | Total |
|----------|------|--------:|-------:|-------:|-----:|-------:|------:|
| #251215 | 16/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251286 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251433 | 16/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251581 | 16/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251613 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251629 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251635 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251657 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251658 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251659 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251660 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251661 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251960 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251971 | 18/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251991 | 18/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #252008 | 18/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #252009 | 18/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #252010 | 18/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #252011 | 18/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #252012 | 18/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #252158 | 18/dez | 0 | 0 | 0 | 1 | 0 | 1 |
| #252189 | 18/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #252276 | 18/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #252289 | 19/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #252301 | 19/dez | 0 | 0 | 0 | 0 | 1 | 1 |

---

#### A.3 - Inbox 14639: Suporte Estrangeiro (5 arquivos em 5 conversas)

| Conversa | Data | Imagens | Vídeos | Áudios | PDFs | Outros | Total |
|----------|------|--------:|-------:|-------:|-----:|-------:|------:|
| #251357 | 16/dez | 0 | 0 | 0 | 0 | 1 | 1 |
| #251606 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251609 | 17/dez | 1 | 0 | 0 | 0 | 0 | 1 |
| #251809 | 17/dez | 0 | 0 | 0 | 1 | 0 | 1 |
| #251825 | 17/dez | 0 | 0 | 0 | 0 | 1 | 1 |

---

**Fim do Documento**

*Gerado em 19/01/2026*
