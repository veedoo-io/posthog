#!/bin/bash

# Налаштування для ClickHouse
BACKUP_DIR="/backups"
KEEP_DAYS=1
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="clickhouse_backup_${DATE}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Створення директорії, якщо її немає
mkdir -p "$BACKUP_DIR"

echo "Started ClickHouse backup at $(date)"

# Виконання бекапу бази 'posthog'
if clickhouse-client --query "BACKUP DATABASE posthog TO File('${BACKUP_DIR}/${BACKUP_NAME}/')"; then
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

# Видалення старих бекапів (залишаємо тільки останній)
echo "Cleaning up old ClickHouse backups, keeping only the latest one..."
ls -t "$BACKUP_DIR"/clickhouse_backup_*.tar.gz | tail -n +2 | xargs -r rm -f

echo "Finished ClickHouse backup at $(date)"
