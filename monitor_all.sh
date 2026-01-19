#!/bin/bash
# Monitor all running processes for Evolvy migration
# Usage: ./monitor_all.sh

cd /home/tarzan/Documents/programing/idiomus/chatwoot

while true; do
  clear
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║          EVOLVY MIGRATION MONITOR - $(date '+%Y-%m-%d %H:%M:%S')          ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  echo ""

  # Download status
  echo "┌─────────────────────────────────────────────────────────────────────┐"
  echo "│ DOWNLOAD DE ATTACHMENTS                                             │"
  echo "├─────────────────────────────────────────────────────────────────────┤"
  if pgrep -f "download_missing_attachments" > /dev/null 2>&1; then
    OK=$(grep -c "^OK" download_fast.log 2>/dev/null || echo 0)
    FAIL=$(grep -c "^FAILED" download_fast.log 2>/dev/null || echo 0)
    TOTAL=45713
    PERCENT=$((OK * 100 / TOTAL))
    BAR=$(printf '%*s' $((PERCENT/2)) '' | tr ' ' '█')
    BAR_EMPTY=$(printf '%*s' $((50 - PERCENT/2)) '' | tr ' ' '░')
    echo "│ Status: 🟢 ATIVO                                                   │"
    echo "│ [$BAR$BAR_EMPTY] $PERCENT%"
    echo "│ OK: $OK | FAILED: $FAIL | Restante: $((TOTAL - OK))              "
    echo "│ ETA: ~$(( (TOTAL - OK) / 500 )) min                               "
  else
    echo "│ Status: ⚫ INATIVO                                                 │"
  fi
  echo "└─────────────────────────────────────────────────────────────────────┘"
  echo ""

  # Database stats
  echo "┌─────────────────────────────────────────────────────────────────────┐"
  echo "│ BANCO DE DADOS                                                      │"
  echo "├─────────────────────────────────────────────────────────────────────┤"
  CONVS=$(docker run --rm postgres:15-alpine psql "postgresql://caio:1JgtM05pCbON2htH@144.202.41.139/chatwoot" -t -A -c "SELECT COUNT(*) FROM conversations WHERE additional_attributes->>'evolvy_id' IS NOT NULL" 2>/dev/null || echo "?")
  echo "│ Conversas com evolvy_id: $CONVS                                    "
  echo "└─────────────────────────────────────────────────────────────────────┘"
  echo ""

  # Import logs
  echo "┌─────────────────────────────────────────────────────────────────────┐"
  echo "│ ÚLTIMAS OPERAÇÕES                                                   │"
  echo "├─────────────────────────────────────────────────────────────────────┤"
  if [ -f "import_missing_20260115_202357.log" ]; then
    echo "│ Import CSV: COMPLETO ($(grep -c "convs," import_missing_20260115_202357.log 2>/dev/null) batches)"
  fi
  echo "└─────────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "Pressione Ctrl+C para sair. Atualizando a cada 30s..."

  sleep 30
done
