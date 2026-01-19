#!/bin/bash
# Parallel Attachment Import Script

echo "Starting parallel attachment imports..."

docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=11 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=1 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=10 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=7 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=8 rails bundle exec rake evolvy:import_attachments &
docker compose run --rm --no-deps -e RAILS_ENV=production -e TARGET_INBOX=9 rails bundle exec rake evolvy:import_attachments &

wait
echo "All attachment imports completed!"
