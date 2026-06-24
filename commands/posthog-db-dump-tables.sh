#!/bin/bash

# Дамп Postgres бази 'posthog' окремо по таблицях
# Кожна таблиця зберігається в окремому файлі

BACKUP_DIR="/db-backups"
KEEP_DAYS=1
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/posthog_db_tables_${DATE}"

# Створення директорії для бекапів
mkdir -p "$BACKUP_PATH"

echo "Started table-by-table backup at $(date)"

# Отримуємо список всіх таблиць у базі
TABLES=$(psql -U posthog -d posthog -t -c "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;")

if [ -z "$TABLES" ]; then
    echo "❌ No tables found or database connection failed!"
    rm -rf "$BACKUP_PATH"
    exit 1
fi

# Лічильник успішних таблиць
success=0
failed=0

# Дампимо кожну таблицю окремо
for table in $TABLES; do
    echo "Dumping table: $table..."

    if pg_dump -U posthog -d posthog -t "$table" | gzip > "${BACKUP_PATH}/${table}.sql.gz"; then
        ((success++))
        SIZE=$(stat -c%s "${BACKUP_PATH}/${table}.sql.gz" 2>/dev/null || echo "0")
        echo "  ✅ ${table} ($(numfmt --to=iec-i --suffix=B $SIZE 2>/dev/null || echo "$SIZE bytes"))"
    else
        ((failed++))
        echo "  ❌ Failed to dump table: $table"
        rm -f "${BACKUP_PATH}/${table}.sql.gz"
    fi
done

echo ""
echo "Dumped $success tables successfully, $failed failed"

if [ "$success" -eq 0 ]; then
    echo "❌ No tables were dumped!"
    rm -rf "$BACKUP_PATH"
    exit 1
fi

# Архівуємо всю директорію з таблицями
echo "Compressing backup directory..."
cd "$BACKUP_DIR"
if tar -czf "posthog_db_tables_${DATE}.tar.gz" "posthog_db_tables_${DATE}/"; then
    echo "✅ Backup compressed to: posthog_db_tables_${DATE}.tar.gz"
    rm -rf "$BACKUP_PATH"
else
    echo "❌ Failed to compress backup!"
    exit 1
fi

# Видаління старих бекапів (залишаємо тільки останній)
echo "Cleaning up old table backups, keeping only the latest one..."
ls -t "$BACKUP_DIR"/posthog_db_tables_*.tar.gz | tail -n +2 | xargs -r rm -f

echo "Finished backup at $(date)"
