#!/bin/bash
# Download missing attachments from Evolvy API
# Run before canceling Evolvy subscription

cd /home/tarzan/Documents/programing/idiomus/chatwoot/06_01_2026_evolvy_dump/backup

API_TOKEN="TBJbVQvRS8oxpWX9R7niG6QQ"
CONCURRENT=10
DOWNLOADED=0
FAILED=0
SKIPPED=0

echo "=== DOWNLOAD DE ATTACHMENTS FALTANTES ==="
echo "Data: $(date)"
echo "Concorrência: $CONCURRENT"
echo ""

download_attachment() {
  local url="$1"
  local output_path="$2"

  # Create directory if needed
  mkdir -p "$(dirname "$output_path")"

  # Download with retry
  for attempt in 1 2 3; do
    if curl -sS -L -o "$output_path" -H "api_access_token: $API_TOKEN" "$url" 2>/dev/null; then
      # Check if file is valid (not empty, not error HTML)
      if [ -s "$output_path" ] && ! head -c 100 "$output_path" | grep -q "<!DOCTYPE"; then
        return 0
      fi
    fi
    sleep 1
  done
  rm -f "$output_path" 2>/dev/null
  return 1
}

export -f download_attachment
export API_TOKEN

# Process each inbox
for dir in inbox_*_conversations; do
  inbox_id=$(echo "$dir" | sed 's/inbox_//;s/_conversations//')
  attach_dir="attachments/inbox_$inbox_id"

  echo "=== Processando inbox $inbox_id ==="

  # Extract all attachment info from conversations
  for conv_file in "$dir"/conversation_*.json; do
    [ -f "$conv_file" ] || continue
    conv_id=$(basename "$conv_file" .json | sed 's/conversation_//')
    conv_attach_dir="$attach_dir/conv_$conv_id"

    # Extract attachments from this conversation
    attachments=$(jq -r '.messages[]?.attachments[]? | select(.data_url != null and .data_url != "") | "\(.id)|\(.data_url)|\(.extension // "bin")"' "$conv_file" 2>/dev/null)

    while IFS='|' read -r att_id att_url att_ext; do
      [ -z "$att_id" ] && continue

      # Determine output filename
      if [ -z "$att_ext" ] || [ "$att_ext" = "null" ]; then
        att_ext="bin"
      fi
      output_file="$conv_attach_dir/att_$att_id.$att_ext"

      # Check if already exists
      if [ -f "$output_file" ]; then
        ((SKIPPED++))
        continue
      fi

      # Download
      echo -n "  Downloading att_$att_id..."
      if download_attachment "$att_url" "$output_file"; then
        echo " OK"
        ((DOWNLOADED++))
      else
        echo " FAILED"
        ((FAILED++))
      fi

    done <<< "$attachments"
  done

  echo "  Inbox $inbox_id: Downloaded=$DOWNLOADED, Failed=$FAILED, Skipped=$SKIPPED"
done

echo ""
echo "=== RESUMO FINAL ==="
echo "Downloaded: $DOWNLOADED"
echo "Failed: $FAILED"
echo "Skipped (já existiam): $SKIPPED"
echo "=== FIM ==="
