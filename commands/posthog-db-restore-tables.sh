#!/bin/bash

# Відновлення Postgres таблиць зі скомпресованого архіву з дампами по таблицях

BACKUP_DIR="/db-backups"
ARCHIVE="$1"

# Якщо архів не вказано — показуємо список для вибору
if [ -z "$ARCHIVE" ]; then
    echo "Available table backup archives:"

    count=0
    ls -t "$BACKUP_DIR"/posthog_db_tables_*.tar.gz 2>/dev/null | while read file; do
        count=$((count + 1))
        echo "  $count) $(basename "$file")"
    done

    # Переброй список для зберігання у змінну
    archives=$(ls -t "$BACKUP_DIR"/posthog_db_tables_*.tar.gz 2>/dev/null)
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
    echo "Usage: $0 [/db-backups/posthog_db_tables_YYYYMMDD_HHMMSS.tar.gz]"
    exit 1
fi

# Ім'я директорії без .tar.gz
ARCHIVE_NAME=$(basename "$ARCHIVE" .tar.gz)
BACKUP_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

echo "Started table restore at $(date)"
echo "Using archive: $(basename "$ARCHIVE")"

# Розпаковуємо архів, якщо ще не розпакований
if [ ! -d "$BACKUP_PATH" ]; then
    echo "Extracting ${ARCHIVE}..."
    tar -xzf "$ARCHIVE" -C "$BACKUP_DIR" || { echo "❌ Failed to extract archive"; exit 1; }
fi

# Отримуємо список таблиць у архіві
TABLES=$(ls "$BACKUP_PATH"/*.sql.gz 2>/dev/null | xargs -I {} basename {} .sql.gz)

if [ -z "$TABLES" ]; then
    echo "❌ No table dumps found in archive!"
    exit 1
fi

# Запиту у користувача режим відновлення
echo ""
echo "Restore mode:"
echo "  1) Append (долити дані в наявні таблиці, можливі дублі)"
echo "  2) Replace (видалити таблиці і заново створити)"
echo ""
printf "Choose mode (1 or 2): "
read mode

if [ "$mode" != "1" ] && [ "$mode" != "2" ]; then
    echo "❌ Invalid choice"
    exit 1
fi

# Лічильник успішних таблиць
success=0
failed=0

# Відновлюємо кожну таблицю
for table in $TABLES; do
    table_file="${BACKUP_PATH}/${table}.sql.gz"

    if [ "$mode" = "2" ]; then
        echo "Dropping table $table..."
        psql -U posthog -d posthog -c "DROP TABLE IF EXISTS $table CASCADE;" > /dev/null 2>&1
    fi

    echo "Restoring table: $table..."

    if gunzip -c "$table_file" | psql -U posthog -d posthog > /dev/null 2>&1; then
        ((success++))
        echo "  ✅ $table"
    else
        ((failed++))
        echo "  ❌ Failed to restore table: $table"
    fi
done

echo ""
echo "Restored $success tables successfully, $failed failed"

# Видаляємо розпаковану директорію
rm -rf "$BACKUP_PATH"

if [ "$failed" -gt 0 ]; then
    echo "⚠️ Some tables failed to restore"
    exit 1
fi

echo "Finished table restore at $(date)"
