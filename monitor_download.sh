#!/bin/bash
cd /home/tarzan/Documents/programing/idiomus/chatwoot
while true; do
  clear
  echo "=== MONITOR DE DOWNLOAD DE ATTACHMENTS ==="
  echo "Atualizado: $(date)"
  echo ""
  echo "Downloads OK: $(grep -c ' OK$' download_attachments.log 2>/dev/null || echo 0)"
  echo "Downloads FAILED: $(grep -c 'FAILED$' download_attachments.log 2>/dev/null || echo 0)"
  echo "Skipped: $(grep -c 'Skipped' download_attachments.log 2>/dev/null || echo 0)"
  echo ""
  echo "Processo ativo: $(pgrep -f download_missing_attachments.sh > /dev/null && echo 'SIM' || echo 'NÃO')"
  echo ""
  echo "Últimas linhas:"
  tail -5 download_attachments.log 2>/dev/null
  echo ""
  echo "Arquivos com falha:"
  grep "FAILED$" download_attachments.log 2>/dev/null | tail -5 || echo "(nenhum)"
  sleep 10
done
