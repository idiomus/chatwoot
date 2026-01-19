#!/bin/bash
# Import missing conversations from CSV with detailed logging
# Optimized for maximum performance with batch processing
# Usage: ./run_import_missing.sh

set -e
cd /home/tarzan/Documents/programing/idiomus/chatwoot

# Paths inside container (mounted as /app)
CSV_FILE="/app/todas_conversas_status.csv"
LOG_FILE="/app/import_missing_$(date +%Y%m%d_%H%M%S).log"
BATCH_SIZE=500

echo "=== IMPORT DE CONVERSAS FALTANTES (OTIMIZADO) ==="
echo "Data: $(date)"
echo "CSV: $CSV_FILE (container path)"
echo "Log: $LOG_FILE (container path)"
echo "Batch Size: $BATCH_SIZE"
echo ""

# Count conversations to import (using local path)
TOTAL=$(grep -E "dentro_periodo,nao_importado" "todas_conversas_status.csv" 2>/dev/null | wc -l)
echo "Conversas a importar: $TOTAL"
echo ""

if [ "$TOTAL" -eq 0 ]; then
    echo "Nenhuma conversa para importar!"
    exit 0
fi

echo "Iniciando import..."
echo ""

# Run import with optimizations:
# - BATCH_SIZE=500: Process 500 conversations at a time
# - SKIP_ATTACHMENTS=true: Import attachments separately for speed
# - Suppress ActionCable broadcasts to avoid overhead
docker compose run --rm --no-deps \
  -e RAILS_ENV=production \
  -e CSV_FILE="$CSV_FILE" \
  -e LOG_FILE="$LOG_FILE" \
  -e BATCH_SIZE="$BATCH_SIZE" \
  -e SKIP_ATTACHMENTS=true \
  -e RAILS_LOG_LEVEL=warn \
  rails bundle exec rake evolvy:import_from_csv

echo ""
echo "=== IMPORT FINALIZADO ==="
echo "Log completo: import_missing_*.log"
echo ""
echo "Para ver falhas:"
echo "  grep -A5 'FAIL' import_missing_*.log | tail -50"
