# Evolvy to Chatwoot Migration

Complete migration guide for Evolvy data (SaaS based on Chatwoot v2.18.0) to self-hosted Chatwoot v4.x instance.

## Table of Contents

1. [Overview](#overview)
2. [Data Summary](#data-summary)
3. [Agent Mapping](#agent-mapping)
4. [Rake Tasks](#rake-tasks)
5. [Local Test Environment](#local-test-environment)
6. [Production Deployment](#production-deployment)
7. [Validation](#validation)
8. [Technical Details](#technical-details)
9. [Troubleshooting](#troubleshooting)

---

## Overview

### Migration Objective

**Primary Goal: Maximum Data Integrity**

The migration must preserve data with the highest possible fidelity. Every conversation, message, contact, and metadata should be migrated accurately from Evolvy to Chatwoot. This includes:

- **Content Integrity**: Message content must match exactly
- **Sender Attribution**: Every message must be attributed to the correct sender (agent or contact)
- **Timestamp Preservation**: Original created_at/updated_at times must be preserved
- **Relationship Integrity**: Conversations linked to correct contacts, inboxes, and assignees
- **Metadata Preservation**: Labels, custom attributes, and additional_attributes

**Validation Approach**: For every migrated conversation, a diff file is generated comparing the migrated data against the original JSON. This allows field-by-field verification of data integrity.

### Source System
- **Platform**: Evolvy (closed SaaS)
- **Base Version**: Chatwoot v2.18.0
- **Account ID**: 3253
- **Data Export**: JSON dump via API scraping

### Target System
- **Platform**: Self-hosted Chatwoot v4.x
- **Production URL**: https://cs.idiomus.com
- **Account ID**: 1 (Idiomus)

### Migration Approach
- **Rails/ActiveRecord** (not raw SQL) for data integrity
- **Preserve original timestamps** on all records
- **Create inactive users** for ex-employees to maintain historical attribution
- **Import order**: Labels → Inboxes → Contacts → Conversations → Messages
- **Diff validation**: Generate comparison files for each migrated conversation

### Operation Tracking (CRITICAL)

**Every CRUD operation on production MUST be logged and generate a diff file.**

All rake tasks that modify production data **automatically**:
1. **Generate a diff file** (`diffs/<operation>_<timestamp>.diff`) BEFORE/AFTER the operation
2. **Append to OPERATIONS_LOG.md** with full operation details

This is built into the rake tasks - no manual logging required.

#### Automatic Logging Coverage

| Task | Creates Diff | JSON Manifest | Logs to OPERATIONS_LOG |
|------|--------------|---------------|------------------------|
| `evolvy:import` | ✅ `import_*.diff` | ✅ `import_manifest_*.json` | ✅ |
| `evolvy:test_import` | ✅ `test_import_*.diff` | ✅ `test_import_manifest_*.json` | ✅ |
| `evolvy:import_contacts` | ✅ `import_*.diff` | ❌ | ✅ |
| `evolvy:import_conversations` | ✅ `import_*.diff` | ❌ | ✅ |
| `evolvy:create_ex_employees` | ✅ `create_ex_employees_*.diff` | ❌ | ✅ |
| `evolvy:cleanup_duplicates` | ✅ `cleanup_duplicates_*.diff` | ❌ | ✅ |
| `evolvy:cleanup_duplicate_conversations` | ✅ `cleanup_duplicate_conversations_*.diff` | ❌ | ✅ |
| `evolvy:cleanup_inbox` | ✅ `cleanup_inbox_*.diff` | ❌ | ✅ |
| `evolvy:validate` | ❌ (read-only) | ❌ | ❌ |
| `evolvy:dry_run` | ❌ (read-only) | ❌ | ❌ |
| `evolvy:show_duplicates` | ❌ (read-only) | ❌ | ❌ |

#### Diff File Contents

Each diff file includes:
- Timestamp and operation type
- Summary statistics (records created, skipped, deleted)
- List of affected record IDs (conversations, messages, contacts)
- For cleanup operations: which records were kept vs deleted

#### File Structure

```
16_12_2025_evolvy_dump/
├── OPERATIONS_LOG.md           # Append-only log of all operations
├── MIGRATION_PROGRESS.md       # High-level migration status
├── INBOX_MAPPING_SLACK.txt     # Human-readable inbox mapping for sharing
├── backup/                     # Source JSON data from Evolvy
│   ├── inbox_14515_conversations/
│   │   ├── conversation_196048.json
│   │   └── ...
│   └── ...
├── data/
│   ├── evolvy_contacts.json
│   └── evolvy_labels.json
└── diffs/                      # Auto-generated diff files
    ├── import_20251218_150000.diff           # Summary diff
    ├── import_manifest_20251218_150000.json  # Full mapping manifest (JSON)
    ├── test_import_20251218_141000.diff
    ├── test_import_manifest_20251218_141000.json
    ├── cleanup_inbox_1_20251218_160000.diff
    ├── cleanup_duplicates_20251218_160000.diff
    ├── cleanup_duplicate_conversations_20251218_161000.diff
    ├── create_ex_employees_20251218_170000.diff
    └── conv_196048.diff        # Per-conversation comparison diffs
```

- **OPERATIONS_LOG.md**: Append-only, one entry per operation
- **diffs/**: One file per operation, timestamped for traceability

#### Log Entry Format (Auto-generated)

```markdown
---

## 2025-12-18 14:10 - Test Import (SUCCESS)

- **Operator**: Claude (automated)
- **Database**: 144.202.41.139 / chatwoot
- **Command**: `bundle exec rake evolvy:test_import`
- **Status**: SUCCESS

### Results
- **Mode**: TEST
- **Conversations Imported**: 208
- **Messages Imported**: 853
- **Diff File**: /path/to/diffs/test_import_20251218_141000.diff
- **Duration Seconds**: 45.2

---
```

---

## Data Summary

| Entity | Count | Notes |
|--------|-------|-------|
| **Contacts** | 86,247 | Includes phone numbers, emails, custom attributes |
| **Conversations** | 128,030 | Across 16 inboxes |
| **Messages (estimated)** | ~500,000+ | Based on conversation samples |
| **Agent Messages** | 379,284 | Messages sent by team members |
| **Labels** | 29 | Contact and conversation labels |
| **Inboxes** | 16 | WhatsApp, Email, Facebook channels |
| **Unique Agents** | 30 | 18 active + 12 ex-employees |

### Inbox Mapping (Evolvy → Chatwoot)

| Evolvy ID | Evolvy Name | Chatwoot ID | Chatwoot Inbox | Convs |
|-----------|-------------|-------------|----------------|-------|
| 5601 | Teacher Poli (83) 92000-5321 | 11 | Grupo Idiomus - Teacher Poli | 6,961 |
| 13726 | Teacher Poli (41) 99866-0291 | 11 | Grupo Idiomus - Teacher Poli | 22,186 |
| 13984 | Teacher Poli (41) 98765-0291 | 11 | Grupo Idiomus - Teacher Poli | 8,927 |
| 14515 | Teacher Poli Facebook | 8 | Teacher Poli | 4,248 |
| 14535 | Teacher Poli Latam | 9 | Teacher Poli Latam | 1,960 |
| 5608 | Idiomus App | 7 | Idiomus | 23 |
| 5871 | Idiomus | 7 | Idiomus | 8,348 |
| 14483 | API Oficial | 10 | Suporte Oficial | 12,765 |
| 14450 | Onboarding API | 10 | Suporte Oficial | 11 |
| 5598 | Idiomus (41) 99907-1709 | 1 | Histórico Evolvy | 26,179 |
| 5599 | Idiomus (84) 99411-8931 | 1 | Histórico Evolvy | 5,336 |
| 5600 | Onboarding (83) 99115-3226 | 1 | Histórico Evolvy | 8,269 |
| 13536 | Teste Nivelamento | nil | (skip - IMAP) | 0 |
| 14448 | Email Suporte | nil | (skip - IMAP) | 14,185 |
| 14453 | Email Teacher Poli | nil | (skip - IMAP) | 8,396 |
| 14638 | Suporte Email | nil | (skip - IMAP) | 761 |

**Summary by target inbox:**

| Chatwoot Inbox | Total Conversations |
|----------------|---------------------|
| 11 - Grupo Idiomus - Teacher Poli | 38,074 |
| 1 - Histórico Evolvy (inactive) | 39,784 |
| 10 - Suporte Oficial | 12,776 |
| 7 - Idiomus | 8,371 |
| 8 - Teacher Poli (Facebook) | 4,248 |
| 9 - Teacher Poli Latam | 1,960 |
| **TOTAL TO IMPORT** | **105,213** |
| (skip - emails via IMAP) | 23,342 |

---

## Agent Mapping

### Active Agents (Chatwoot IDs 2-20)

These users already exist in production Chatwoot:

| Evolvy ID | Name | Email | Chatwoot ID | Messages |
|-----------|------|-------|-------------|----------|
| 18075 | Caio Passos | caio.passos@idiomus.com | 2 | 3 |
| 5986 | Juliana Nizer | juliana@idiomus.com | 3 | 51,818 |
| 17861 | Herison Pereira | herison.pereira@idiomus.com | 4 | 6 |
| 17297 | Pablo Luz | pablo@idiomus.com | 5 | - |
| 16887 | Ivison | ivison.freire@idiomus.com | 7 | 38,462 |
| 16396 | Fabio | fabio.gregorio@idiomus.com | 8 | 20,303 |
| 17313 | Catherine | catherine.mello@idiomus.com | 9 | 23,052 |
| 17370 | Betina Ogliari | betina.ogliari@idiomus.com | 10 | 358 |
| 18090 | Bruno Araujo | bruno.araujo@idiomus.com | 11 | 260 |
| 17951 | Felipe Foiato | foiato@idiomus.com | 12 | - |
| 5883 | Israel | israel@idiomus.com | 13 | 78 |
| 15861 | Jorge Frizzo | jorge.frizzo@idiomus.com | 14 | 21 |
| 17854 | Laura | laura.moreira@idiomus.com | 15 | 12,158 |
| 18077 | Pedro Lobao | admin@slever.com.br | 16 | - |
| 17840 | Rachel | rachel@idiomus.com | 17 | 24 |
| 18106 | Rafaela Lamim | rafaela.lamim@idiomus.com | 18 | 3 |
| 17824 | Vanessa | vanessa.abreu@idiomus.com | 19 | 12,406 |
| 5995 | Vinicius | vinicius@idiomus.com | 20 | 10,943 |

### Ex-Employees (Chatwoot IDs 21-35)

These users will be **created as inactive accounts** for historical data preservation:

| Evolvy ID | Name | Email | Chatwoot ID | Messages | Note |
|-----------|------|-------|-------------|----------|------|
| 6 | ADM (Sistema) | adm.sistema@idiomus.com | 21 | 165,056 | JustSell bot/system |
| 5984 | Jessica | jessica@idiomus.com | 22 | 8,896 | Ex-employee |
| 17464 | Tiago Gaspari | tiago.gaspari@idiomus.com | 23 | 10,033 | Ex-employee |
| 16185 | Suellen | suellen.goncalves@idiomus.com | 24 | 8,494 | Ex-employee |
| 15566 | Lizandra | maria.lizandra@idiomus.com | 25 | 6,553 | Ex-employee |
| 16826 | Sandra | sandra.postay@idiomus.com | 26 | 4,100 | Ex-employee |
| 16361 | Fernando | fernando.garcia@idiomus.com | 27 | 2,361 | Ex-employee |
| 17847 | Carina Camargo | carina.camargo@idiomus.com | 28 | 1,688 | Ex-employee |
| 16186 | Camila | camila.teixeira@idiomus.com | 29 | 1,522 | Ex-employee |
| 17463 | Wallan Peixoto | wallan.david@idiomus.com | 30 | 355 | Ex-employee |
| 17404 | Isadora Almeida | isadora.magalhaes@idiomus.com | 31 | 299 | Ex-employee |
| 17468 | Adriane Rampazzo | adriane.rampazzo@idiomus.com | 32 | 29 | Ex-employee |
| 1174 | Guilherme Suporte | guilherme.evolvy@idiomus.com | 33 | 1 | Evolvy support |
| 17471 | Hudson Moreira | hudson.moreira@idiomus.com | 34 | 1 | Ex-employee |
| 17507 | Luan Pereira | luan.souza@idiomus.com | 35 | 1 | Ex-employee |

**Total Coverage**: 379,284 agent messages (100%) will have correct sender attribution.

### Team Mapping

| Evolvy Team ID | Name | Chatwoot Team ID |
|----------------|------|------------------|
| 15102 | CS | 1 |
| 12212 | Compra | 2 |

---

## Rake Tasks

Location: `lib/tasks/evolvy_import.rake`

| Task | Description | When to Use |
|------|-------------|-------------|
| `evolvy:dry_run` | Analyze dump statistics without importing | Before import to verify data |
| `evolvy:validate_senders` | Verify all agent senders are mapped | Before import to ensure 100% coverage |
| `evolvy:create_ex_employees` | Create inactive users for ex-employees | **Run first in production** |
| `evolvy:import` | Full production import | Main migration task |
| `evolvy:test_import` | Limited import for testing | Local testing with limits |
| `evolvy:validate` | Validate imported data integrity | After import to verify success |
| `evolvy:import_contacts` | Import only contacts | Partial import if needed |
| `evolvy:import_conversations` | Import only conversations | Partial import if needed |
| `evolvy:cleanup_inbox` | Delete ALL data from specific inbox | Clean up failed imports (requires `INBOX_ID`) |
| `evolvy:cleanup_duplicates` | Remove duplicate messages | Fix duplicate imports |
| `evolvy:cleanup_duplicate_conversations` | Remove duplicate conversations | Fix duplicate imports |
| `evolvy:cleanup_evolvy_imports` | Delete ALL Evolvy-imported data | Retry failed imports |
| `evolvy:import_attachments` | Import attachments for existing messages | After conversation import (supports `TARGET_INBOX`) |
| `evolvy:show_duplicates` | Show duplicate statistics | Diagnose duplicate issues |

### Environment Variables

```bash
# Core settings (defaults shown)
EVOLVY_DUMP_PATH=./16_12_2025_evolvy_dump  # Relative to Rails root
CHATWOOT_ACCOUNT_ID=1
IMPORT_BATCH_SIZE=1000

# For test mode (evolvy:test_import)
LIMIT_CONTACTS=500
LIMIT_CONVERSATIONS=100
LIMIT_INBOX=13726  # Optional: specific inbox ID

# Migration gap handling
CUTOFF_DATE=2025-12-15    # Skip conversations created on/after this date
SKIP_ATTACHMENTS=true     # Track attachments in manifest but don't import them

# Parallel import (see Parallel Import section below)
TARGET_INBOX=11           # Only import conversations for this Chatwoot inbox
SKIP_CONTACTS=true        # Skip contact import (for parallel runs)

# For cleanup_inbox task
INBOX_ID=1                # Required: inbox to clean
```

### Parallel Import (Performance Optimization)

For faster imports on multi-core systems, run multiple processes in parallel by target inbox.

**Prerequisites:**
- Contacts must be imported first (single process)
- Each process handles one Chatwoot inbox
- No overlap = no race conditions = idempotency preserved

**Inbox Distribution:**

| Chatwoot Inbox | ID | Evolvy Inboxes | ~Conversations |
|----------------|-----|----------------|----------------|
| Grupo Idiomus - Teacher Poli | 11 | 5601, 13726, 13984 | 38K |
| Histórico Evolvy | 1 | 5598, 5599, 5600 | 40K |
| Suporte Oficial | 10 | 14483, 14450 | 13K |
| Idiomus | 7 | 5608, 5871 | 8K |
| Teacher Poli | 8 | 14515 | 4K |
| Teacher Poli Latam | 9 | 14535 | 2K |

**Commands (run in separate terminals):**

```bash
# Terminal 1 - Inbox 11 (38K convs)
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e CUTOFF_DATE=2025-12-15 \
  -e SKIP_ATTACHMENTS=true \
  -e SKIP_CONTACTS=true \
  -e TARGET_INBOX=11 \
  rails bundle exec rake evolvy:import

# Terminal 2 - Inbox 1 (40K convs)
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e CUTOFF_DATE=2025-12-15 \
  -e SKIP_ATTACHMENTS=true \
  -e SKIP_CONTACTS=true \
  -e TARGET_INBOX=1 \
  rails bundle exec rake evolvy:import

# Terminal 3 - Inbox 10 (13K convs)
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e CUTOFF_DATE=2025-12-15 \
  -e SKIP_ATTACHMENTS=true \
  -e SKIP_CONTACTS=true \
  -e TARGET_INBOX=10 \
  rails bundle exec rake evolvy:import

# Terminal 4 - Inbox 7 (8K convs)
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e CUTOFF_DATE=2025-12-15 \
  -e SKIP_ATTACHMENTS=true \
  -e SKIP_CONTACTS=true \
  -e TARGET_INBOX=7 \
  rails bundle exec rake evolvy:import

# Terminal 5 - Inbox 8 (4K convs)
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e CUTOFF_DATE=2025-12-15 \
  -e SKIP_ATTACHMENTS=true \
  -e SKIP_CONTACTS=true \
  -e TARGET_INBOX=8 \
  rails bundle exec rake evolvy:import

# Terminal 6 - Inbox 9 (2K convs)
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e CUTOFF_DATE=2025-12-15 \
  -e SKIP_ATTACHMENTS=true \
  -e SKIP_CONTACTS=true \
  -e TARGET_INBOX=9 \
  rails bundle exec rake evolvy:import
```

**Single command (all parallel + attachments at end):**

```bash
# Run all 6 conversation imports in parallel, then attachments in parallel
for inbox in 11 1 10 7 8 9; do docker compose run --rm --no-deps -e RAILS_ENV=production -e 
  CUTOFF_DATE=2025-12-15 -e SKIP_ATTACHMENTS=true -e SKIP_CONTACTS=true -e TARGET_INBOX=$inbox
   rails bundle exec rake evolvy:import & done; wait; echo "Conversations done!"; for inbox in
   11 1 10 7 8 9; do docker compose run --rm --no-deps -e RAILS_ENV=production -e             
  TARGET_INBOX=$inbox rails bundle exec rake evolvy:import_attachments & done; wait; echo "All
   done!"     
```

**Expected speedup:** ~5-6x (limited by DB connections, not CPU)

### JSON Manifest Output

Every import generates a comprehensive JSON manifest file for granular tracking:

**File**: `diffs/import_manifest_<timestamp>.json`

```json
{
  "generated_at": "2025-12-18T19:30:00Z",
  "mode": "FULL",
  "cutoff_date": "2025-12-15",
  "stats": {
    "conversations_imported": 105213,
    "conversations_skipped": 0,
    "conversations_cutoff": 1234,
    "messages_imported": 1172809,
    "attachments_tracked": 51827
  },
  "mappings": {
    "conversations": {
      "120513": {"chatwoot_id": 789, "inbox_id": 11}
    },
    "contacts": {
      "1807894": 12345
    },
    "messages": {
      "76380798": {"chatwoot_id": 999001, "conversation_id": 789}
    },
    "agents": {
      "17370": 42
    }
  },
  "attachments": [
    {"evolvy_conv_id": "120513", "evolvy_msg_id": "76380798", "file_type": "image", "data_url": "..."}
  ]
}
```

**Use cases:**
- Verify specific conversation was imported: `jq '.mappings.conversations["120513"]' manifest.json`
- Find missing messages: Compare source JSON evolvy_ids against manifest
- Re-import only missing data: Query manifest to identify gaps

---

## Local Test Environment

### Prerequisites

1. Docker and Docker Compose installed
2. Evolvy dump folder available
3. Access to production PostgreSQL credentials

### Setup Steps (Production Database Mode)

This setup connects to the **production PostgreSQL database** from your local machine.

```bash
# 1. Create .env file with minimal configuration
cat > .env << 'EOF'
SECRET_KEY_BASE=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2g3h4i5j6k7l8m9n0o1p2q3r4s5t6u7v8w9x0y1z2

RAILS_ENV=production

# PostgreSQL Production (get credentials from team)
POSTGRES_DATABASE=chatwoot
POSTGRES_HOST=<production_host>
POSTGRES_USERNAME=<username>
POSTGRES_PASSWORD=<password>

# Redis - temporary local container
REDIS_URL=redis://172.17.0.1:6380
REDIS_PASSWORD=

# Other required settings
FRONTEND_URL=http://localhost:3000
RAILS_LOG_TO_STDOUT=true
EOF

# 2. Start a temporary Redis container (required for ActiveRecord callbacks)
docker run -d --name chatwoot-redis-temp -p 6380:6379 redis:alpine

# 3. Verify dump folder exists
ls -la 16_12_2025_evolvy_dump/
```

### Copy Dump to Chatwoot Folder

```bash
# The dump must be inside chatwoot folder (for Docker volume access)
cp -r /path/to/16_12_2025_evolvy_dump ./16_12_2025_evolvy_dump

# Add to .gitignore (already done)
echo "16_12_2025_evolvy_dump/" >> .gitignore
```

### Run Test Import (Against Production DB)

```bash
# 1. Run limited test import (100 conversations from inbox 14515)
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e LIMIT_INBOX=14515 \
  -e LIMIT_CONVERSATIONS=100 \
  rails bundle exec rake evolvy:test_import

# 2. Run dry run to see statistics
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  rails bundle exec rake evolvy:dry_run

# 3. Validate sender mapping
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  rails bundle exec rake evolvy:validate_senders
```

### Full Import (Production)

```bash
# Run full import
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  rails bundle exec rake evolvy:import

# Validate after import
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  rails bundle exec rake evolvy:validate
```

### Cleanup

```bash
# Stop and remove temporary Redis
docker stop chatwoot-redis-temp && docker rm chatwoot-redis-temp

# Remove any leftover containers
docker compose down
```

### Important Notes

- **`--no-deps`**: Skips starting local postgres/redis containers since we're using production database
- **`-e RAILS_ENV=production`**: Required to override docker-compose.yaml's default `development` setting
- **Redis**: A temporary Redis is required for Sidekiq job enqueuing (ActiveRecord callbacks)
- **Redis IP `172.17.0.1`**: This is the Docker bridge network gateway IP (host machine from container's perspective)

### Useful Commands

```bash
# Rails console with production database
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  rails bundle exec rails console

# Check specific conversation after import
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  rails bundle exec rails runner "
    conv = Conversation.where(\"additional_attributes->>'evolvy_id' = '120513'\").first
    puts \"Messages: #{conv&.messages&.count}\"
  "
```

---

## Production Deployment

### Pre-Migration Checklist

- [ ] Backup production database (`pg_dump`)
- [ ] Verify Chatwoot account ID matches `CHATWOOT_ACCOUNT_ID=1`
- [ ] Verify active agents exist with correct IDs (2-20) in production
- [ ] Schedule maintenance window (estimated: 2-4 hours for 128k conversations)
- [ ] Prepare Evolvy dump on server

### Step 1: Upload Dump to Production Server

```bash
# Option A: SCP
scp -r 12_12_2025_evolvy_dump/ user@cs.idiomus.com:/path/to/chatwoot/

# Option B: Rsync (resumable, better for large files)
rsync -avz --progress 12_12_2025_evolvy_dump/ user@cs.idiomus.com:/path/to/chatwoot/12_12_2025_evolvy_dump/
```

### Step 2: Validate Agent Mapping

```bash
cd /path/to/chatwoot
bundle exec rails evolvy:validate_senders
```

**Expected output:**
```
================================================================================
✅ ALL AGENT SENDERS ARE MAPPED - Production import will have correct attribution
================================================================================
```

### Step 3: Create Ex-Employee Users

```bash
bundle exec rails evolvy:create_ex_employees
```

**Expected output:**
```
✅ Created: ADM (Sistema) (adm.sistema@idiomus.com) - ID 21
✅ Created: Jéssica (jessica@idiomus.com) - ID 22
... (15 users total)
✅ All ex-employee users ready for migration
```

**What this does:**
- Creates 15 inactive users (IDs 21-35)
- Random passwords (no login access)
- Sets `custom_attributes: { inactive: true, evolvy_migration: true }`
- Adds to account as offline agents

### Step 4: Run Dry Run

```bash
bundle exec rails evolvy:dry_run
```

Review output for any issues before proceeding.

### Step 5: Execute Full Import

```bash
# Full import
bundle exec rails evolvy:import

# Or with custom batch size for memory management
IMPORT_BATCH_SIZE=500 bundle exec rails evolvy:import
```

**Estimated Duration**: 2-4 hours for 128,030 conversations.

### Step 6: Validate Import

```bash
bundle exec rails evolvy:validate
```

**Expected output:**
```
[1/6] Checking contacts count...
  ✅ Contacts: 86247 imported (source: 86247)
[2/6] Checking contacts data integrity (sample)...
  ✅ Contact data integrity: OK (sample of 10)
[3/6] Checking conversations count...
  ✅ Conversations: 128030 imported (source: 128030, 100%)
[4/6] Checking messages integrity (sample)...
  ✅ Messages integrity: OK
[5/6] Checking timestamps preservation...
  ✅ Timestamps preserved (sample: 2024-01-15 14:32:00)
[6/6] Checking labels...
  ✅ Labels: 29 imported (source: 29)

============================================================
✅ VALIDATION PASSED - Data integrity is acceptable for production
============================================================
```

### Step 7: Manual Verification

1. Access Chatwoot UI at cs.idiomus.com
2. Navigate to imported conversations (prefixed with `[Evolvy]`)
3. Verify:
   - Messages display correctly
   - Agent names show on sent messages (not "bot" or "admin")
   - Timestamps are historical (not current date)
   - Labels are attached to contacts/conversations

---

## Validation

### Diff-Based Validation (Primary Method)

The primary validation method generates git-style diff files comparing each migrated conversation against its original JSON data.

**Tool**: `16_12_2025_evolvy_dump/conversation_diff_generator.py`

```bash
# Generate diffs for all conversations (or limited sample)
cd 16_12_2025_evolvy_dump

POSTGRES_HOST=<host> \
POSTGRES_DATABASE=chatwoot \
POSTGRES_USERNAME=<user> \
POSTGRES_PASSWORD=<password> \
uv run --with psycopg2-binary python conversation_diff_generator.py --limit 100
```

**Output Structure**:
```
diffs/
├── SUMMARY.txt           # Overall statistics
├── stats.json            # Machine-readable stats
├── conv_120513.diff      # Individual conversation diff
├── conv_120520.diff
└── ...
```

**Sample Diff File** (`conv_120513.diff`):
```
================================================================================
CONVERSATION DIFF: Evolvy ID 120513
================================================================================

## CONVERSATION METADATA
----------------------------------------
  status: snoozed [OK]
  created_at: 2024-09-05T10:13:08 [OK]
  inbox: 13726 -> [Evolvy] Teacher Poli Oficial
  assignee: juliana@idiomus.com [OK]

## MESSAGES
----------------------------------------
  Source count: 13
  DB count:     13
  [OK] Message counts match

### MESSAGE-BY-MESSAGE COMPARISON

[OK] 76380798 (incoming) -> Contact:Jéssica Winny
[OK] 76380850 (outgoing) -> User:Juliana
[DIFF] 76380900 (outgoing):
        sender: expected User, got Contact
[OK] 76380950 (activity) -> system
...

================================================================================
RESULT: DIFFERENCES FOUND
================================================================================
```

**What Each Diff Shows**:
- **[OK]**: Field matches between source and DB
- **[DIFF]**: Field has differences (shows both values)
- **[MISSING]**: Message exists in source but not in DB
- **CONVERSATION NOT MIGRATED**: Entire conversation missing from DB

**Interpreting Results**:
| Stats Field | Ideal Value | Action if Different |
|-------------|-------------|---------------------|
| `not_found` | 0 | Check inbox mapping, import logs |
| `with_differences` | 0 | Review individual diffs for patterns |
| `perfect_match` | = found | All data migrated correctly |

### Automated Checks (evolvy:validate)

| Check | Description | Pass Criteria |
|-------|-------------|---------------|
| Contacts Count | Compare imported vs source | ≥95% imported |
| Contacts Integrity | Sample 10 contacts for required fields | No missing evolvy_id |
| Conversations Count | Verify conversations imported | >0 imported |
| Messages Integrity | Compare message counts in samples | Match source counts |
| Timestamps | Verify historical dates preserved | created_at < 1 day ago |
| Labels | Compare label counts | All labels imported |

### Manual Validation Queries

```ruby
# In Rails console
account = Account.find(1)

# Check totals
puts "Contacts: #{account.contacts.count}"
puts "Conversations: #{account.conversations.count}"
puts "Messages: #{Message.where(account: account).count}"

# Check specific conversation
conv = account.conversations.where("additional_attributes->>'evolvy_id' = '120513'").first
puts "Messages: #{conv.messages.count}"
conv.messages.limit(5).each do |m|
  sender_name = m.sender&.name || 'Contact'
  puts "#{m.message_type}: #{sender_name} - #{m.content&.truncate(50)}"
end

# Verify ex-employee messages display correctly
user = User.find(21)  # ADM Sistema
puts "ADM messages: #{user.messages.count}"

# Check a message from an ex-employee
msg = Message.joins(:sender).where(sender_type: 'User', sender_id: 22).first
puts "Sender: #{msg.sender.name}"  # Should show "Jéssica"
```

---

## Technical Details

### Dump File Structure

```
12_12_2025_evolvy_dump/
├── backup/
│   ├── inbox_XXXXX.json              # Inbox metadata (16 files)
│   └── inbox_XXXXX_conversations/    # Per-inbox folders
│       ├── conversation_YYYYY.json   # Individual conversations (128,030 files)
│       └── all_conversations_summary.json
├── data/
│   ├── evolvy_contacts.json          # All contacts (~890MB)
│   ├── evolvy_labels.json            # 29 labels
│   └── conversation_mapping.json     # ID mapping reference
└── unified_data/                      # Additional exports
```

### Conversation JSON Structure

```json
{
  "id": 120513,
  "uuid": "7b79d78d-fe23-4c90-a93c-a90e5d14c0ad",
  "account_id": 3253,
  "inbox_id": 13726,
  "status": "resolved",
  "created_at": 1725541988,
  "timestamp": 1725542100,
  "meta": {
    "sender": {
      "id": 1807894,
      "name": "Customer Name",
      "phone_number": "+5583999999999",
      "email": null
    },
    "channel": "Channel::Wpp",
    "assignee": {
      "id": 5986,
      "email": "juliana@idiomus.com",
      "name": "Juliana"
    }
  },
  "messages": [
    {
      "id": 76380798,
      "content": "Hello",
      "message_type": 0,
      "content_type": "text",
      "created_at": 1725541989,
      "sender": {
        "type": "contact",
        "id": 1807894
      }
    },
    {
      "id": 76380850,
      "content": "Hi! How can I help?",
      "message_type": 1,
      "created_at": 1725542050,
      "sender": {
        "type": "user",
        "id": 5986
      }
    }
  ],
  "labels": ["onboarding", "teacher-poli"]
}
```

### Message Types

| Value | Type | Description |
|-------|------|-------------|
| 0 | incoming | Customer message |
| 1 | outgoing | Agent message |
| 2 | activity | System message (assignments, etc.) |

### Timestamp Preservation

```ruby
# Disable Rails automatic timestamps
Conversation.record_timestamps = false
conversation = Conversation.new(
  created_at: parse_timestamp(conv_data['created_at']),
  updated_at: parse_timestamp(conv_data['timestamp']),
  last_activity_at: parse_timestamp(conv_data['last_activity_at'])
)
conversation.save!(validate: false)
Conversation.record_timestamps = true
```

### Message Sender Attribution Logic

The sender attribution handles multiple edge cases discovered in the Evolvy data:

| Scenario | Message Type | Sender Data | Result |
|----------|--------------|-------------|--------|
| Activity message | 2 | Any | `nil` (system message) |
| Incoming with contact | 0 | `type: contact` | Contact |
| Incoming without sender | 0 | Missing/empty | Contact |
| Outgoing with user | 1 | `type: user` | Mapped User |
| Outgoing without sender | 1 | Missing/empty | Fallback Agent (ADM Sistema) |
| Outgoing with unmapped user | 1 | `type: user`, ID not in AGENTS | Fallback Agent |
| Channel::Whatsapp style | Any | `sender_type: User, sender_id: X` | Uses separate fields |

**Key insights from data analysis:**
- ~3% of Channel::Wpp outgoing messages lack sender data (sent via direct API)
- Activity messages (type=2) never have sender - they are system-generated
- Channel::Whatsapp uses separate `sender_type`/`sender_id` fields instead of nested `sender` object

```ruby
def determine_sender_for_bulk(msg_data, default_contact)
  message_type = msg_data['message_type'] || 0

  # Activity messages (type=2) never have sender - they are system messages
  return [nil, nil] if message_type == 2

  # Check for separate sender_type/sender_id fields (used by Channel::Whatsapp)
  if msg_data['sender_type'].present? && msg_data['sender_id'].present?
    case msg_data['sender_type']
    when 'Contact'
      return ['Contact', default_contact.id]
    when 'User'
      user_id = map_agent_id(msg_data['sender_id'])
      return user_id ? ['User', user_id] : ['User', fallback_agent_id]
    end
  end

  sender_data = msg_data['sender']

  # No sender data - determine by message type
  unless sender_data.present? && sender_data.is_a?(Hash) && sender_data.any?
    # Incoming messages (type=0) without sender: use contact
    return ['Contact', default_contact.id] if message_type == 0

    # Outgoing messages (type=1,3) without sender: use fallback agent
    return ['User', fallback_agent_id]
  end

  case sender_data['type']
  when 'contact'
    ['Contact', default_contact.id]
  when 'user', 'agent_bot'
    user_id = map_agent_id(sender_data['id'])
    # Use fallback agent for unmapped users instead of contact
    user_id ? ['User', user_id] : ['User', fallback_agent_id]
  else
    # Unknown type - determine by message type
    message_type == 0 ? ['Contact', default_contact.id] : ['User', fallback_agent_id]
  end
end

def fallback_agent_id
  # Use ADM (Sistema) as fallback - Evolvy ID 6
  @fallback_agent_id ||= @agent_mapping[6] || find_or_create_fallback_agent
end
```

**Fallback Agent**: ADM (Sistema) - `adm.sistema@idiomus.com` is used for:
- Outgoing messages without sender data
- Messages from unmapped agents
- Bot/automation messages from JustSell system

### Contact Identifier Convention

All imported contacts have identifier format: `evolvy_XXXXX`

```ruby
contact.identifier = "evolvy_#{evolvy_contact_id}"
contact.custom_attributes = {
  'evolvy_id' => evolvy_contact_id,
  'evolvy_imported_at' => Time.current.iso8601
}
```

### Inbox Naming Convention

Imported inboxes are prefixed with `[Evolvy]`:
- Original: "WhatsApp Business"
- Imported: "[Evolvy] WhatsApp Business"

This distinguishes historical inboxes from new production inboxes.

### Foreign Key Dependencies (Import Order)

```
1. Labels (no dependencies)
2. Inboxes + Channels (account)
3. Contacts (account)
4. ContactInboxes (contact, inbox)
5. Conversations (account, inbox, contact, contact_inbox, assignee)
6. Messages (account, inbox, conversation, sender)
7. Taggings (labels on contacts/conversations)
```

### Ex-Employee User Creation (SQL)

```ruby
# Uses raw SQL to control specific user IDs
ActiveRecord::Base.connection.execute(<<-SQL.squish)
  INSERT INTO users (id, email, encrypted_password, name, display_name, uid, provider,
                     created_at, updated_at, confirmed_at, custom_attributes)
  VALUES (
    #{emp[:id]},
    '#{emp[:email]}',
    '#{BCrypt::Password.create(SecureRandom.hex(32))}',
    '#{emp[:name]}',
    '#{emp[:name]}',
    '#{emp[:email]}',
    'email',
    NOW(), NOW(), NOW(),
    '{"inactive": true, "note": "#{emp[:note]}", "evolvy_migration": true}'::jsonb
  )
SQL

# Update sequence to avoid ID conflicts
max_id = User.maximum(:id) || 0
ActiveRecord::Base.connection.execute("SELECT setval('users_id_seq', #{max_id + 1}, false)")
```

---

## Troubleshooting

### "0 conversation files found"

**Cause**: Dump folder not accessible from Rails container.

**Solution**: Ensure dump is inside chatwoot folder (Docker volume mount):
```bash
cp -r /external/path/12_12_2025_evolvy_dump ./12_12_2025_evolvy_dump
```

### "duplicate key value violates unique constraint"

**Cause**: User already exists or uid/provider constraint.

**Solution**: The `create_ex_employees` task checks for existing users by email. If running again, it will skip existing users.

### "null value in column updated_at"

**Cause**: Missing timestamp in source data.

**Solution**: Already handled - falls back to `created_at` or current time:
```ruby
updated_time = parse_timestamp(conv_data['timestamp'] || conv_data['last_activity_at'] || conv_data['created_at'])
```

### Messages showing "bot" or "admin" as sender

**Cause**: Agent mapping not found for Evolvy user ID.

**Solution**:
1. Run `evolvy:validate_senders` to find unmapped senders
2. Add missing mappings to `AGENT_MAPPING`
3. Create ex-employee users with `evolvy:create_ex_employees`

### Foreign key constraint errors during cleanup

**Cause**: Trying to delete records with dependent children.

**Solution**: Delete in reverse dependency order:
```ruby
Message.where(...).delete_all
Conversation.where(...).delete_all
ContactInbox.where(...).delete_all
Contact.where(...).delete_all
Inbox.where(...).destroy_all  # destroy_all to delete channels
```

### Import taking too long

**Solution**: Reduce batch size:
```bash
IMPORT_BATCH_SIZE=250 bundle exec rails evolvy:import
```

---

## Rollback Plan

### Option 1: Delete Imported Data Only

```ruby
# In Rails console
account = Account.find(1)

# Delete in reverse order
Message.where(account: account).where("additional_attributes->>'evolvy_id' IS NOT NULL").delete_all
Conversation.where(account: account).where("additional_attributes->>'evolvy_id' IS NOT NULL").delete_all
ContactInbox.joins(:contact).where(contacts: { account_id: account.id }).where("contacts.identifier LIKE 'evolvy_%'").delete_all
account.contacts.where("identifier LIKE 'evolvy_%'").delete_all
account.inboxes.where("name LIKE '[Evolvy]%'").destroy_all
```

### Option 2: Full Database Restore

```bash
# Stop services
docker-compose down

# Restore from backup
pg_restore -d chatwoot_production backup_before_migration.dump

# Restart services
docker-compose up -d
```

---

## Files Created/Modified

| File | Purpose |
|------|---------|
| `lib/tasks/evolvy_import.rake` | Main migration rake tasks and EvolvyImporter class |
| `docs/evolvy-migration.md` | This documentation |
| `.gitignore` | Added `12_12_2025_evolvy_dump/` exclusion |

---

## References

- [Chatwoot Docker Setup](https://developers.chatwoot.com/contributing-guide/environment-setup/docker)
- [Chatwoot API Reference](https://developers.chatwoot.com/api-reference)

---

---

## Migration Status (Final - January 2026)

### Summary

| Metric | Value | Status |
|--------|-------|--------|
| Conversations imported | 133,407 | COMPLETE |
| Messages reimported | 2,458 | COMPLETE |
| Attachments available | 52,653 | PARTIAL |
| Attachments irrecoverable | 6,149 | LOST (404) |

### Conversations

- **Total imported**: 133,407 conversations with `evolvy_id`
- **Period covered**: 01/01/2024 - 19/12/2025
- **CSV import**: 2,552 additional conversations imported via `evolvy:import_from_csv`
- **Verification**: `todas_conversas_status.csv`

### Messages

- **Bulk import issue**: Fixed `determine_message_sender` to return `[type, id]` instead of objects
- **Reimport task**: `evolvy:reimport_messages` - processed 2,570 conversations
- **Result**: 2,458 success, 0 failed, 112 skipped (no messages in JSON)

### Attachments

**Local files by extension:**
| Extension | Count | Type |
|-----------|-------|------|
| MP3 | 11,307 | Audio |
| OGA | 10,410 | Audio (Opus) |
| JPG | 10,102 | Image |
| PDF | 7,943 | Document |
| BIN | 5,026 | Unknown |
| MP4 | 4,231 | Video |
| PNG | 2,332 | Image |
| Others | 1,302 | Mixed |

**Issues resolved:**
1. **Extension fix**: 15,559 files renamed from `.bin` to correct extension based on mimetype
2. **Duplicate removal**: 17,490 duplicate `.bin` files removed
3. **Download script fix**: Now checks `att_ID.*` (any extension) before downloading

**Irrecoverable attachments:**
- 6,149 attachments return HTTP 404 from Evolvy API
- List saved to: `attachments_irrecuperaveis.txt`
- Cause: Files deleted from Evolvy (Active Storage expiration or cleanup)

### Files Created

| File | Purpose |
|------|---------|
| `todas_conversas_status.csv` | Verification of all conversations |
| `attachments_irrecuperaveis.txt` | List of 6,149 irrecoverable attachments |
| `reimport_msgs_*.log` | Message reimport log |
| `import_missing_*.log` | CSV import log |
| `download_missing_attachments_fast.sh` | Fixed download script |
| `fix_bin_extensions.sh` | Extension renaming script |

### Recommendations

1. **Keep backup**: Preserve `06_01_2026_evolvy_dump` in secure location
2. **Remove old dump**: `16_12_2025_evolvy_dump` can be deleted after confirmation
3. **Visual verification**: Check sample conversations in Chatwoot UI
4. **Cancel Evolvy**: Safe to cancel subscription after final verification

---

*Last Updated: January 2026*
*Migration Completed: 2026-01-16*
*Conversations: 133,407 imported*
*Messages: Reimported for 2,458 conversations*
*Attachments: 52,653 available, 6,149 irrecoverable (404)*
*Local Testing Completed: 2025-12-18*
*Agent Mapping Validated: 100% coverage (379,284 messages)*
*Sender Handling Updated: 2025-12-18 (handles null senders, Channel::Whatsapp fields, fallback agent)*
*Local Docker Setup Documented: 2025-12-18 (production DB mode with temp Redis)*
*Inbox Mapping Finalized: 2025-12-18 (105,213 conversations to 6 target inboxes)*
*JSON Manifest Added: 2025-12-18 (granular tracking of all conversations, messages, contacts)*
*Cutoff Date Filter Added: 2025-12-18 (avoid overlap with webhook data)*
*Attachment Tracking Added: 2025-12-18 (reference in manifest without import)*
