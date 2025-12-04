#!/bin/sh
# Automatically loads any variable *_FILE to its non-suffixed version

load_secrets() {
  for var in $(env | grep '_FILE=' | cut -d= -f1); do
    var_name="${var%_FILE}"

    file_path="$(eval echo \"\$$var\")"

    if [ -f "$file_path" ] && [ -r "$file_path" ]; then
      echo "[secrets] Loading $var_name from $file_path"

      secret_value="$(cat "$file_path" | tr -d '\n')"
      export "$var_name"="$secret_value"

      unset "$var"
    else
      echo "[secrets] Warning: File not found or not readable: $file_path (for $var_name)"
    fi
  done
}

load_secrets
