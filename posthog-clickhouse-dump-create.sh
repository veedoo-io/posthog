#!/bin/bash

# Налаштування для ClickHouse
BACKUP_DIR="/var/lib/clickhouse/backups"
KEEP_DAYS=1
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="clickhouse_backup_${DATE}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Створення директорії, якщо її немає
mkdir -p "$BACKUP_DIR"

echo "Started ClickHouse backup at $(date)"

# Встановлюємо робочу директорію в /tmp, щоб уникнути помилки "cannot get current directory"
cd /tmp

# Виконання бекапу бази 'default'
if clickhouse-client --query "BACKUP DATABASE default TO File('/var/lib/clickhouse/backups/${BACKUP_NAME}/')"; then
    echo "✅ ClickHouse backup created at: ${BACKUP_PATH}"
    
    # Переходимо в папку бекапів для стискання
    cd "$BACKUP_DIR"
    # Стискаємо в архів
    tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}" && rm -rf "${BACKUP_NAME}"
    echo "✅ Backup compressed to: ${BACKUP_NAME}.tar.gz"
else
    echo "❌ ClickHouse backup failed!"
    exit 1
fi

# Видалення старих бекапів
echo "Cleaning up old ClickHouse backups..."
find "$BACKUP_DIR" -name "clickhouse_backup_*.tar.gz" -type f -mtime +"$KEEP_DAYS" -exec rm -f {} \; -print

echo "Finished ClickHouse backup at $(date)"
