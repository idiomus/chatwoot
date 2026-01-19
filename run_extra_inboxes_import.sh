#!/bin/bash
# Importar inboxes extras: 14638 (Suporte) e 14639 (Extra TP)
# Executar após a importação atual terminar

cd /home/tarzan/Documents/programing/idiomus/chatwoot

echo "=== Importando inboxes extras (14638, 14639) ==="
echo "14638 (Suporte extra) → inbox 12: 1,677 conversas"
echo "14639 (Extra TP) → inbox 13: 2,979 conversas"
echo ""

docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e SKIP_ATTACHMENTS=true \
  -e SKIP_CONTACTS=true \
  rails bundle exec rake evolvy:import_conversations
