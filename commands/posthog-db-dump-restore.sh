#!/bin/bash

# Відновлення дампу Postgres бази 'posthog'

BACKUP_DIR="/db-backups"
ARCHIVE="$1"

# Якщо архів не вказано — показуємо список для вибору
if [ -z "$ARCHIVE" ]; then
    echo "Available backup archives:"

    count=0
    ls -t "$BACKUP_DIR"/posthog_db_*.sql.gz 2>/dev/null | while read file; do
        count=$((count + 1))
        echo "  $count) $(basename "$file")"
    done

    # Переброй список для зберігання у змінну
    archives=$(ls -t "$BACKUP_DIR"/posthog_db_*.sql.gz 2>/dev/null)
    count=$(echo "$archives" | wc -l)

    if [ "$count" -eq 0 ] || [ -z "$archives" ]; then
        echo "❌ No backup archives found in $BACKUP_DIR"
        exit 1
    fi

    echo ""
    printf "Select backup number to restore (1-%d): " "$count"
    read choice

    if ! [ "$choice" -ge 1 ] 2>/dev/null || ! [ "$choice" -le "$count" ] 2>/dev/null; then
        echo "❌ Invalid choice"
        exit 1
    fi

    ARCHIVE=$(echo "$archives" | sed -n "${choice}p")
fi

if [ ! -f "$ARCHIVE" ]; then
    echo "❌ Backup archive not found: ${ARCHIVE}"
    echo "Usage: $0 [/db-backups/posthog_db_YYYYMMDD_HHMMSS.sql.gz]"
    exit 1
fi

# Ім'я файлу без .gz
DUMP_FILE="${ARCHIVE%.gz}"
DUMP_NAME=$(basename "$DUMP_FILE")

echo "Started Postgres restore at $(date)"
echo "Using archive: $(basename "$ARCHIVE")"

# Розпаковуємо архів, якщо ще не розпакований
if [ ! -f "$DUMP_FILE" ]; then
    echo "Extracting ${ARCHIVE}..."
    gunzip -c "$ARCHIVE" > "$DUMP_FILE" || { echo "❌ Failed to extract archive"; exit 1; }
fi

# Відновлення дампу у Postgres
echo "Restoring database..."
if psql -U posthog posthog < "$DUMP_FILE"; then
    echo "✅ Postgres restore completed from: $(basename "$ARCHIVE")"
    # Видаляємо розпакований файл
    rm -f "$DUMP_FILE"
else
    echo "❌ Postgres restore failed!"
    exit 1
fi

echo "Finished Postgres restore at $(date)"
