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

### Inboxes Breakdown

| ID | Name | Type | Conversations |
|----|------|------|---------------|
| 5598 | Idiomus Oficial (41) 99907-1709 | WhatsApp | 26,179 |
| 13726 | Teacher Poli Oficial (41) 99866-0291 | WhatsApp | 21,945 |
| 14448 | Email Suporte | Email | 14,168 |
| 14483 | API Oficial onboarding | WhatsApp | 12,158 |
| 13984 | Teacher Poli (41) 98765-0291 | WhatsApp | 8,927 |
| 5871 | Idiomus | Facebook | 8,343 |
| 5600 | Onboarding (83)99115-3226 | WhatsApp | 8,269 |
| 14453 | Email Teacher Poli | Email | 8,092 |
| 5601 | Teacher Poli - (83)92000-5321 | WhatsApp | 6,961 |
| 5599 | Idiomus - (84) 99411-8931 | WhatsApp | 5,336 |
| 14515 | Teacher Poli | Facebook | 4,214 |
| 14535 | Teacher Poli hispanohablantes | Facebook | 1,936 |
| 14639 | (no metadata) | ? | 905 |
| 14638 | Suporte | Email | 563 |
| 5608 | Idiomus App | Facebook | 23 |
| 14450 | Onboarding API | WhatsApp | 11 |

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

### Environment Variables

```bash
# Optional - defaults shown
EVOLVY_DUMP_PATH=./12_12_2025_evolvy_dump  # Relative to Rails root
CHATWOOT_ACCOUNT_ID=1
IMPORT_BATCH_SIZE=1000

# For test mode (evolvy:test_import)
LIMIT_CONTACTS=500
LIMIT_CONVERSATIONS=100
LIMIT_INBOX=13726  # Optional: specific inbox ID
```

---

## Local Test Environment

### Prerequisites

1. Docker and Docker Compose installed
2. Evolvy dump folder available

### Setup Steps

```bash
# 1. Clone and configure
cd chatwoot
cp .env.example .env
# Edit .env - set POSTGRES_PASSWORD and REDIS_PASSWORD

# 2. Build containers
docker compose build

# 3. Initialize database
docker compose run --rm rails bundle exec rails db:chatwoot_prepare

# 4. Start services
docker compose up -d

# 5. Access
# App: http://localhost:3000
# Login: john@acme.inc / Password1!
```

### Copy Dump to Chatwoot Folder

```bash
# The dump must be inside chatwoot folder (for Docker volume access)
cp -r /path/to/12_12_2025_evolvy_dump ./12_12_2025_evolvy_dump

# Add to .gitignore (already done)
echo "12_12_2025_evolvy_dump/" >> .gitignore
```

### Run Test Import

```bash
# 1. Validate sender mapping
docker compose exec rails bundle exec rails evolvy:validate_senders

# 2. Create ex-employees
docker compose exec rails bundle exec rails evolvy:create_ex_employees

# 3. Run limited test
docker compose exec rails bundle exec rails evolvy:test_import

# 4. Validate results
docker compose exec rails bundle exec rails evolvy:validate
```

### Useful Commands

```bash
# Rails console
docker compose exec rails bundle exec rails console

# View logs
docker compose logs -f rails

# Reset database completely
docker compose down -v
docker compose run --rm rails bundle exec rails db:chatwoot_prepare
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

```ruby
def determine_message_sender(msg_data, default_contact)
  sender_data = msg_data['sender']
  return default_contact unless sender_data

  case sender_data['type']
  when 'contact'
    default_contact  # Customer message
  when 'user'
    # Map Evolvy user ID to Chatwoot user ID
    chatwoot_user_id = AGENT_MAPPING[sender_data['id']]
    User.find_by(id: chatwoot_user_id)
  else
    default_contact
  end
end
```

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

*Last Updated: December 2024*
*Local Testing Completed: 2024-12-15*
*Agent Mapping Validated: 100% coverage (379,284 messages)*
