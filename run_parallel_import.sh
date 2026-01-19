#!/bin/bash
# Parallel Evolvy Import Script

echo "Starting parallel conversation imports..."

docker compose run --rm --no-deps -e RAILS_ENV=production -e CUTOFF_DATE=2025-12-15 -e SKIP_ATTACHMENTS=true -e SKIP_CONTACTS=true -e TARGET_INBOX=11 rails bundle exec rake evolvy:import &
docker compose run --rm --no-deps -e RAILS_ENV=production -e CUTOFF_DATE=2025-12-15 -e SKIP_ATTACHMENTS=true -e SKIP_CONTACTS=true -e TARGET_INBOX=1 rails bundle exec rake evolvy:import &
docker compose run --rm --no-deps -e RAILS_ENV=production -e CUTOFF_DATE=2025-12-15 -e SKIP_ATTACHMENTS=true -e SKIP_CONTACTS=true -e TARGET_INBOX=10 rails bundle exec rake evolvy:import &
docker compose run --rm --no-deps -e RAILS_ENV=production -e CUTOFF_DATE=2025-12-15 -e SKIP_ATTACHMENTS=true -e SKIP_CONTACTS=true -e TARGET_INBOX=7 rails bundle exec rake evolvy:import &
docker compose run --rm --no-deps -e RAILS_ENV=production -e CUTOFF_DATE=2025-12-15 -e SKIP_ATTACHMENTS=true -e SKIP_CONTACTS=true -e TARGET_INBOX=8 rails bundle exec rake evolvy:import &
docker compose run --rm --no-deps -e RAILS_ENV=production -e CUTOFF_DATE=2025-12-15 -e SKIP_ATTACHMENTS=true -e SKIP_CONTACTS=true -e TARGET_INBOX=9 rails bundle exec rake evolvy:import &

wait
echo "Conversations done! Starting attachments..."

docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=11 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=1 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=10 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=7 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=8 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=9 rails bundle exec rake evolvy:import_attachments &

wait
echo "All imports completed!"
