#!/bin/bash
# Fast parallel download of missing attachments from Evolvy API
# Uses 30 concurrent downloads
# FIXED: Checks for att_ID.* (any extension) before downloading

set -e
cd /home/tarzan/Documents/programing/idiomus/chatwoot/06_01_2026_evolvy_dump/backup

API_TOKEN="TBJbVQvRS8oxpWX9R7niG6QQ"
CONCURRENT=30
LOG_FILE="/home/tarzan/Documents/programing/idiomus/chatwoot/download_fast.log"

echo "=== DOWNLOAD RÁPIDO DE ATTACHMENTS ===" | tee "$LOG_FILE"
echo "Data: $(date)" | tee -a "$LOG_FILE"
echo "Concorrência: $CONCURRENT" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Create list of all attachments to download
echo "Gerando lista de attachments para baixar..." | tee -a "$LOG_FILE"

> /tmp/attachments_to_download.txt

for dir in inbox_*_conversations; do
  [ -d "$dir" ] || continue
  inbox_id=$(echo "$dir" | sed 's/inbox_//;s/_conversations//')

  for conv_file in "$dir"/conversation_*.json; do
    [ -f "$conv_file" ] || continue
    conv_id=$(basename "$conv_file" .json | sed 's/conversation_//')

    # Extract attachments with mimetype for better extension detection
    jq -r --arg inbox "$inbox_id" --arg conv "$conv_id" \
      '.messages[]?.attachments[]? | select(.data_url != null and .data_url != "") |
       "\($inbox)|\($conv)|\(.id)|\(.data_url)|\(.extension // "")|\(.mimetype // "")"' \
      "$conv_file" 2>/dev/null >> /tmp/attachments_to_download.txt
  done
done

TOTAL=$(wc -l < /tmp/attachments_to_download.txt)
echo "Total de attachments no dump: $TOTAL" | tee -a "$LOG_FILE"

# Filter out already downloaded - check for ANY extension with same ID
echo "Filtrando já baixados (verificando att_ID.* com qualquer extensão)..." | tee -a "$LOG_FILE"
> /tmp/attachments_missing.txt

# Also check 16_12_2025 dump
DUMP_OLD="/home/tarzan/Documents/programing/idiomus/chatwoot/16_12_2025_evolvy_dump/backup/attachments"

while IFS='|' read -r inbox conv att_id url ext mimetype; do
  [ -z "$att_id" ] && continue

  output_dir="attachments/inbox_$inbox/conv_$conv"

  # Check if file exists with ANY extension in current dump
  if ls "$output_dir"/att_"$att_id".* >/dev/null 2>&1; then
    continue
  fi

  # Check if file exists in old dump
  if ls "$DUMP_OLD/inbox_$inbox/conv_$conv"/att_"$att_id".* >/dev/null 2>&1; then
    continue
  fi

  # Determine best extension from mimetype or fallback
  if [ -n "$ext" ] && [ "$ext" != "null" ]; then
    final_ext="$ext"
  elif [ -n "$mimetype" ] && [ "$mimetype" != "null" ]; then
    case "$mimetype" in
      audio/mpeg) final_ext="mp3" ;;
      audio/ogg|audio/opus) final_ext="oga" ;;
      audio/wav) final_ext="wav" ;;
      audio/mp4) final_ext="m4a" ;;
      image/jpeg) final_ext="jpg" ;;
      image/png) final_ext="png" ;;
      image/gif) final_ext="gif" ;;
      image/webp) final_ext="webp" ;;
      video/mp4) final_ext="mp4" ;;
      video/quicktime) final_ext="mov" ;;
      application/pdf) final_ext="pdf" ;;
      text/plain) final_ext="txt" ;;
      *) final_ext="bin" ;;
    esac
  else
    final_ext="bin"
  fi

  echo "$inbox|$conv|$att_id|$url|$final_ext" >> /tmp/attachments_missing.txt
done < /tmp/attachments_to_download.txt

MISSING=$(wc -l < /tmp/attachments_missing.txt)
echo "Attachments faltando: $MISSING" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ "$MISSING" -eq 0 ]; then
  echo "Nenhum attachment para baixar!" | tee -a "$LOG_FILE"
  exit 0
fi

# Download function
download_one() {
  local line="$1"
  local api_token="$2"

  IFS='|' read -r inbox conv att_id url ext <<< "$line"

  [ -z "$att_id" ] && return 0
  [ -z "$ext" ] && ext="bin"

  output_dir="attachments/inbox_$inbox/conv_$conv"
  output_file="$output_dir/att_$att_id.$ext"

  mkdir -p "$output_dir"

  # Download with retry
  for attempt in 1 2 3; do
    if curl -sS -L -o "$output_file" -H "api_access_token: $api_token" "$url" 2>/dev/null; then
      if [ -s "$output_file" ] && ! head -c 100 "$output_file" 2>/dev/null | grep -q "<!DOCTYPE"; then
        echo "OK $att_id"
        return 0
      fi
    fi
    sleep 0.5
  done

  rm -f "$output_file" 2>/dev/null
  echo "FAILED $att_id"
  return 1
}

export -f download_one

echo "Iniciando download paralelo ($CONCURRENT simultâneos)..." | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run parallel downloads with progress
cat /tmp/attachments_missing.txt | \
  xargs -P $CONCURRENT -I {} bash -c 'download_one "$@"' _ {} "$API_TOKEN" 2>&1 | \
  tee -a "$LOG_FILE" | \
  awk '
    BEGIN { ok=0; fail=0 }
    /^OK/ { ok++; if (ok % 100 == 0) print "[" strftime("%H:%M:%S") "] " ok " downloads OK" > "/dev/stderr" }
    /^FAILED/ { fail++; print > "/dev/stderr" }
    END { print "\n=== RESUMO ===" > "/dev/stderr"; print "OK: " ok > "/dev/stderr"; print "FAILED: " fail > "/dev/stderr" }
  '

echo "" | tee -a "$LOG_FILE"
echo "=== DOWNLOAD COMPLETO ===" | tee -a "$LOG_FILE"
echo "Data: $(date)" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
