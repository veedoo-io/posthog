#!/bin/bash

# Відновлення (append) бекапу ClickHouse бази 'posthog'
# Дані доливаються в наявні таблиці, без повного перезапису.

BACKUP_DIR="/clickhouse-backups"
ARCHIVE="$1"

# Якщо архів не вказано — показуємо список для вибору
if [ -z "$ARCHIVE" ]; then
    echo "Available backup archives:"

    ls -t "$BACKUP_DIR"/clickhouse_backup_*.tar.gz 2>/dev/null | while read file; do
        echo "  $(basename "$file")"
    done > /tmp/backups_list.txt

    count=$(wc -l < /tmp/backups_list.txt)

    if [ "$count" -eq 0 ]; then
        echo "❌ No backup archives found in $BACKUP_DIR"
        rm -f /tmp/backups_list.txt
        exit 1
    fi

    echo ""
    printf "Select backup number to restore (1-%d): " "$count"
    read choice

    if ! [ "$choice" -ge 1 ] 2>/dev/null || ! [ "$choice" -le "$count" ] 2>/dev/null; then
        echo "❌ Invalid choice"
        rm -f /tmp/backups_list.txt
        exit 1
    fi

    ARCHIVE=$(sed -n "${choice}p" /tmp/backups_list.txt | xargs -I {} ls -t "$BACKUP_DIR"/{} 2>/dev/null | head -n 1)
    ARCHIVE=$(ls -t "$BACKUP_DIR"/clickhouse_backup_*.tar.gz 2>/dev/null | sed -n "${choice}p")
    rm -f /tmp/backups_list.txt
fi

if [ ! -f "$ARCHIVE" ]; then
    echo "❌ Backup archive not found: ${ARCHIVE}"
    echo "Usage: $0 [/clickhouse-backups/clickhouse_backup_YYYYMMDD_HHMMSS.tar.gz]"
    exit 1
fi

# Ім'я директорії = ім'я архіву без .tar.gz
BACKUP_NAME=$(basename "$ARCHIVE" .tar.gz)
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

echo "Started ClickHouse restore at $(date)"
echo "Using archive: ${ARCHIVE}"

# Розпаковуємо архів у дозволений шлях, якщо директорії ще немає
if [ ! -d "$BACKUP_PATH" ]; then
    echo "Extracting ${ARCHIVE}..."
    tar -xzf "$ARCHIVE" -C "$BACKUP_DIR" || { echo "❌ Failed to extract archive"; exit 1; }
fi

# Відновлення з доливанням даних у наявні таблиці
if clickhouse-client --query "RESTORE DATABASE posthog FROM File('${BACKUP_PATH}/') SETTINGS allow_non_empty_tables=true, allow_different_table_def=true"; then
    echo "✅ ClickHouse restore (append) completed from: ${BACKUP_PATH}"
    # Прибираємо розпаковану директорію, архів лишаємо
    rm -rf "$BACKUP_PATH"
else
    echo "❌ ClickHouse restore failed!"
    exit 1
fi

echo "Finished ClickHouse restore at $(date)"



if clickhouse-client --query "RESTORE DATABASE posthog FROM File('/clickhouse-backups/clickhouse_backups_20260624_082139/') SETTINGS allow_non_empty_tables=true, allow_different_table_def=true"; then
    echo "✅ ClickHouse restore (append) completed from: ${BACKUP_PATH}"
    # Прибираємо розпаковану директорію, архів лишаємо
    rm -rf "$BACKUP_PATH"
else
    echo "❌ ClickHouse restore failed!"
    exit 1
fi

