#!/bin/bash
# Reimport messages for conversations that have no messages
# This fixes the "can't quote Contact" error from the previous import

cd /home/tarzan/Documents/programing/idiomus/chatwoot

LOG_FILE="reimport_msgs_$(date +%Y%m%d_%H%M%S).log"

echo "=== REIMPORT MESSAGES ==="
echo "Log file: $LOG_FILE"
echo ""

docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e LOG_FILE="/app/$LOG_FILE" \
  rails bundle exec rake evolvy:reimport_messages

echo ""
echo "Done! Check log: $LOG_FILE"
