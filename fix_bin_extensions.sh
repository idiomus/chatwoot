#!/bin/bash
# Renomeia arquivos .bin para extensão correta baseado no mimetype do JSON

cd /home/tarzan/Documents/programing/idiomus/chatwoot/06_01_2026_evolvy_dump/backup

echo "=== CORREÇÃO DE EXTENSÕES .bin ==="
echo "Data: $(date)"

# Mapa de mimetype para extensão
get_extension() {
  local mime="$1"
  case "$mime" in
    audio/mpeg) echo "mp3" ;;
    audio/ogg|audio/opus) echo "oga" ;;
    audio/wav) echo "wav" ;;
    audio/mp4|audio/m4a) echo "m4a" ;;
    audio/*) echo "mp3" ;;
    image/jpeg) echo "jpg" ;;
    image/png) echo "png" ;;
    image/gif) echo "gif" ;;
    image/webp) echo "webp" ;;
    image/*) echo "jpg" ;;
    video/mp4) echo "mp4" ;;
    video/quicktime) echo "mov" ;;
    video/*) echo "mp4" ;;
    application/pdf) echo "pdf" ;;
    text/plain) echo "txt" ;;
    text/csv) echo "csv" ;;
    *) echo "" ;;
  esac
}

renamed=0
skipped=0
failed=0

# Processar cada arquivo .bin
find attachments -name "*.bin" -type f | while read bin_file; do
  # Extrair info do caminho: attachments/inbox_X/conv_Y/att_Z.bin
  dir=$(dirname "$bin_file")
  filename=$(basename "$bin_file" .bin)
  att_id=$(echo "$filename" | sed 's/att_//')
  
  # Extrair inbox e conv do caminho
  inbox_id=$(echo "$dir" | grep -oP 'inbox_\K[0-9]+')
  conv_id=$(echo "$dir" | grep -oP 'conv_\K[0-9]+')
  
  # Encontrar JSON da conversa
  json_file="inbox_${inbox_id}_conversations/conversation_${conv_id}.json"
  
  if [ ! -f "$json_file" ]; then
    ((skipped++))
    continue
  fi
  
  # Extrair mimetype do attachment específico
  mimetype=$(jq -r --arg id "$att_id" '.messages[].attachments[]? | select(.id == ($id | tonumber)) | .mimetype // empty' "$json_file" 2>/dev/null | head -1)
  
  if [ -z "$mimetype" ] || [ "$mimetype" = "null" ]; then
    ((skipped++))
    continue
  fi
  
  # Determinar nova extensão
  new_ext=$(get_extension "$mimetype")
  
  if [ -z "$new_ext" ]; then
    ((skipped++))
    continue
  fi
  
  # Renomear
  new_file="$dir/att_${att_id}.${new_ext}"
  
  if [ -f "$new_file" ]; then
    # Já existe com extensão correta, remover o .bin
    rm -f "$bin_file"
    ((renamed++))
  else
    mv "$bin_file" "$new_file"
    ((renamed++))
  fi
  
  # Progresso
  if [ $((renamed % 500)) -eq 0 ]; then
    echo "Progresso: $renamed renomeados..."
  fi
done

echo ""
echo "=== RESULTADO ==="
echo "Renomeados: $renamed"
echo "Skipped: $skipped"
echo "Failed: $failed"
