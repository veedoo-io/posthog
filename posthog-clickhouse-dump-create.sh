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

# Отримуємо список всіх баз даних, крім системних
DATABASES=$(clickhouse-client --query "SHOW DATABASES" | grep -vE 'system|information_schema|INFORMATION_SCHEMA')

echo "Found databases: $DATABASES"

# Створюємо тимчасову папку для цього бекапу
mkdir -p "/backups/${BACKUP_NAME}"

# Виконання бекапу для кожної бази
for db in $DATABASES; do
    echo "Backing up database: $db"
    if clickhouse-client --query "BACKUP DATABASE $db TO File('/backups/${BACKUP_NAME}/$db/')"; then
        echo "✅ Database $db backed up"
    else
        echo "❌ Backup of $db failed!"
        exit 1
    fi
done

echo "✅ ClickHouse backup created at: ${BACKUP_PATH}"

# Переходимо в папку бекапів для стискання
cd "/backups"
# Стискаємо в архів
tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}" && rm -rf "${BACKUP_NAME}"
echo "✅ Backup compressed to: ${BACKUP_NAME}.tar.gz"

# Видалення старих бекапів (залишаємо тільки останній)
echo "Cleaning up old ClickHouse backups, keeping only the latest one..."
ls -t "$BACKUP_DIR"/clickhouse_backup_*.tar.gz | tail -n +2 | xargs -r rm -f

echo "Finished ClickHouse backup at $(date)"
