#!/bin/bash
# Verificação completa de attachments Evolvy

cd /home/tarzan/Documents/programing/idiomus/chatwoot/06_01_2026_evolvy_dump/backup

echo "=== VERIFICAÇÃO DE ATTACHMENTS EVOLVY ==="
echo "Data: $(date)"
echo ""

# 1. Contar attachments referenciados nas conversas
echo "1. Contando attachments referenciados nas conversas..."
total_refs=0
missing_refs=0

for dir in inbox_*_conversations; do
  inbox_id=$(echo "$dir" | sed 's/inbox_//;s/_conversations//')

  # Contar referências a attachments
  refs=$(grep -r '"data_url"' "$dir" 2>/dev/null | wc -l)
  total_refs=$((total_refs + refs))

  # Verificar quantos arquivos existem localmente
  attach_dir="../attachments/inbox_$inbox_id"
  if [ -d "$attach_dir" ]; then
    local_count=$(find "$attach_dir" -type f 2>/dev/null | wc -l)
  else
    local_count=0
  fi

  echo "  Inbox $inbox_id: $refs referências, $local_count arquivos locais"
done

echo ""
echo "Total de referências a attachments: $total_refs"

# 2. Contar arquivos locais
echo ""
echo "2. Arquivos de attachment salvos localmente:"
total_local=$(find attachments -type f 2>/dev/null | wc -l)
total_size=$(du -sh attachments 2>/dev/null | cut -f1)
echo "  Total: $total_local arquivos ($total_size)"

# 3. Verificar tipos de arquivo
echo ""
echo "3. Tipos de arquivo no dump:"
find attachments -type f 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10

echo ""
echo "=== FIM DA VERIFICAÇÃO ==="
