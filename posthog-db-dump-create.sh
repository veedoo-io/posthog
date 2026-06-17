#!/bin/bash

# Налаштування для роботи ВСЕРЕДИНІ контейнера
# Папка /backups має бути прокинута через volumes у docker-compose
BACKUP_DIR="/backups"
KEEP_DAYS=1
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/posthog_db_${DATE}.sql.gz"

# Створення директорії для бекапів, якщо вона не існує (всередині контейнера)
mkdir -p "$BACKUP_DIR"

echo "Started backup inside container at $(date)"

# Створення дампу напряму через pg_dumpall
# Оскільки скрипт працює в контейнері db, ми просто викликаємо утиліту
if pg_dumpall -U posthog | gzip > "$BACKUP_FILE"; then
    echo "✅ Backup created: $BACKUP_FILE"
    
    # Перевірка розміру (мінімум 1 КБ)
    SIZE=$(stat -c%s "$BACKUP_FILE")
    if [ "$SIZE" -lt 1024 ]; then
        echo "⚠️ Warning: Backup file is very small ($SIZE bytes). It might be empty or corrupted."
    fi
else
    echo "❌ Backup failed!"
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Видалення старих бекапів
echo "Cleaning up backups older than $KEEP_DAYS days..."
find "$BACKUP_DIR" -name "posthog_db_*.sql.gz" -type f -mtime +"$KEEP_DAYS" -exec rm -f {} \; -print

echo "Finished backup at $(date)"
