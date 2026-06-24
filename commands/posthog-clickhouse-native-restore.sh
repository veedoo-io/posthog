#!/bin/bash

# Налаштування
DATABASE="posthog"
BACKUP_BASE_DIR="/clickhouse-backups"
TAR_FILE=$1

if [ -z "$TAR_FILE" ]; then
    echo "Використання: $0 <path_to_backup_tar_gz>"
    echo "Приклад: $0 ./data/posthog_stats_native_20260623_143657.tar.gz"
    exit 1
fi

if [ ! -f "$TAR_FILE" ]; then
    echo "❌ Файл не знайдено: $TAR_FILE"
    exit 1
fi

BACKUP_FILENAME=$(basename "$TAR_FILE")
BACKUP_NAME="${BACKUP_FILENAME%.tar.gz}"
TEMP_EXTRACT_DIR="./data/clickhouse-backups/${BACKUP_NAME}"

echo "--- Початок відновлення нативного бекапу ClickHouse ---"

# 1. Розпакування архіву
echo "Розпакування архіву $BACKUP_FILENAME..."
# Використовуємо docker для очищення, бо файли можуть належати root або clickhouse
docker compose exec -T clickhouse rm -rf "${BACKUP_BASE_DIR}/${BACKUP_NAME}"

mkdir -p "$TEMP_EXTRACT_DIR"
# Використовуємо --no-same-owner щоб файли належали поточному користувачу
# Використовуємо --no-same-permissions щоб уникнути помилок при спробі встановити права з архіву
tar -xzf "$TAR_FILE" -C "./data/clickhouse-backups" --no-same-owner --no-same-permissions

if [ $? -ne 0 ]; then
    echo "⚠️ Попередження: tar завершився з помилками (можливо через права доступу)."
    echo "Перевірка чи файли розпаковані..."
    if [ ! -d "$TEMP_EXTRACT_DIR" ]; then
        echo "❌ Помилка: Директорія $TEMP_EXTRACT_DIR не створена!"
        exit 1
    fi
fi

# Встановлюємо права, щоб Clickhouse міг читати файли
# UID 101 - це зазвичай користувач clickhouse в контейнері
echo "Налаштування прав доступу..."
chmod -R 777 "$TEMP_EXTRACT_DIR"

# 2. Визначення шляху всередині контейнера
CONTAINER_BACKUP_PATH="${BACKUP_BASE_DIR}/${BACKUP_NAME}"

# 3. Виконання RESTORE
echo "Виконання RESTORE в ClickHouse (DATABASE ${DATABASE})..."

# ClickHouse RESTORE DATABASE намагається перестворити таблиці. 
# Для Replicated таблиць це викликає REPLICA_ALREADY_EXISTS, якщо шлях у ZK вже зайнятий.
# Коли ми відновлюємо в ту саму базу, ClickHouse бачить, що шлях реплікації в метаданих бекапу 
# збігається з існуючим, і видає помилку.

# Щоб обійти це, можна спробувати відновити тільки ті таблиці, яких немає, 
# або використовувати AS для відновлення в іншу назву (але ви хочете в posthog).

RESTORE_QUERY="RESTORE DATABASE ${DATABASE} FROM File('${CONTAINER_BACKUP_PATH}/') SETTINGS allow_non_empty_tables=true, allow_different_table_def=true"

# ПРИМІТКА: Якщо помилка REPLICA_ALREADY_EXISTS для системних таблиць (як partition_statistics) заважає,
# ви можете відновити тільки потрібні таблиці статистики:
# RESTORE TABLE posthog.sharded_events, posthog.person, posthog.sharded_sessions FROM File(...)

docker compose exec -T clickhouse clickhouse-client --query "${RESTORE_QUERY}"

if [ $? -eq 0 ]; then
    echo "✅ Дані успішно відновлені!"
    
    echo "Очищення тимчасових файлів..."
    rm -rf "$TEMP_EXTRACT_DIR"
else
    echo "❌ Помилка при виконанні RESTORE в ClickHouse!"
    echo "Тимчасові файли залишено в $TEMP_EXTRACT_DIR для діагностики."
    echo "Ви можете спробувати відновити окрему таблицю вручну:"
    echo "RESTORE TABLE posthog.table_name FROM File('${CONTAINER_BACKUP_PATH}/') SETTINGS allow_non_empty_tables=true"
    exit 1
fi

echo "--- Готово ---"
