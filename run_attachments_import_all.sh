#!/bin/bash
# Parallel Attachment Import Script - All Inboxes

echo "Starting parallel attachment imports..."
echo "Date: $(date)"

LOG_DIR="/home/tarzan/Documents/programing/idiomus/chatwoot"

# Run imports in parallel for each Chatwoot inbox
# Inbox 1: WhatsApp inativo (5598, 5599, 5600) - has most attachments
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=1 rails bundle exec rake evolvy:import_attachments > "$LOG_DIR/att_import_inbox_1.log" 2>&1 &

# Inbox 7: Facebook (5608, 5871)
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=7 rails bundle exec rake evolvy:import_attachments > "$LOG_DIR/att_import_inbox_7.log" 2>&1 &

# Inbox 8: Teacher Poli FB (14515)
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=8 rails bundle exec rake evolvy:import_attachments > "$LOG_DIR/att_import_inbox_8.log" 2>&1 &

# Inbox 9: Teacher Poli Hispanohablantes FB (14535)
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=9 rails bundle exec rake evolvy:import_attachments > "$LOG_DIR/att_import_inbox_9.log" 2>&1 &

# Inbox 10: Onboarding API (14450, 14483)
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=10 rails bundle exec rake evolvy:import_attachments > "$LOG_DIR/att_import_inbox_10.log" 2>&1 &

# Inbox 11: Teacher Poli WA (13726, 13984, 5601) - second largest
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=11 rails bundle exec rake evolvy:import_attachments > "$LOG_DIR/att_import_inbox_11.log" 2>&1 &

# Inbox 12: Email Suporte (14448, 14638)
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=12 rails bundle exec rake evolvy:import_attachments > "$LOG_DIR/att_import_inbox_12.log" 2>&1 &

# Inbox 13: Email Teacher Poli (14453, 14639)
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=13 rails bundle exec rake evolvy:import_attachments > "$LOG_DIR/att_import_inbox_13.log" 2>&1 &

echo "All imports started. Waiting for completion..."
wait

echo ""
echo "=== IMPORT COMPLETED ==="
echo "Date: $(date)"
echo ""
echo "Logs saved to $LOG_DIR/att_import_inbox_*.log"
echo ""

# Show summary from each log
for i in 1 7 8 9 10 11 12 13; do
  echo "--- Inbox $i ---"
  grep -E "Imported:|Skipped|Not found|Failed:|Duration:" "$LOG_DIR/att_import_inbox_$i.log" 2>/dev/null | tail -5
  echo ""
done
