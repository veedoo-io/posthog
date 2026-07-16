#!/bin/bash

# Налаштування для роботи ВСЕРЕДИНІ контейнера
# Папка /db-backups має бути прокинута через volumes у docker-compose
BACKUP_DIR="/db-backups"
KEEP_DAYS=1
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/posthog_db_${DATE}.sql.gz"

# Створення директорії для бекапів, якщо вона не існує (всередині контейнера)
mkdir -p "$BACKUP_DIR"

echo "Started backup inside container at $(date)"

# Створення дампу напряму через pg_dump
# Використовуємо --data-only для того, щоб не створювати таблиці (тільки дані)
# --disable-triggers допомагає уникнути проблем із циклічними зовнішніми ключами при відновленні
# --no-owner та --no-privileges допомагають при відновленні в інші середовища
# Ми ігноруємо stderr (2>/dev/null), щоб приховати численні попередження про циклічні ключі, які є нормальними для PostHog
if pg_dump -U posthog -d posthog --data-only --disable-triggers --no-owner --no-privileges 2>/dev/null | gzip > "$BACKUP_FILE"; then
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

# Видалення старих бекапів (залишаємо тільки останній)
echo "Cleaning up old backups, keeping only the latest one..."
ls -t "$BACKUP_DIR"/posthog_db_*.sql.gz | tail -n +2 | xargs -r rm -f

echo "Finished backup at $(date)"