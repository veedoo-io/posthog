#!/bin/bash

# Налаштування
DATABASE="posthog"
BACKUP_BASE_DIR="/clickhouse-backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="posthog_stats_native_${DATE}"
BACKUP_PATH="${BACKUP_BASE_DIR}/${BACKUP_NAME}"
TAR_FILE="/home/nikolay/Docker/posthog/posthog/data/clickhouse-backups/${BACKUP_NAME}.tar.gz"

# Список таблиць для бекапу (тільки статистика та важливі дані)
TABLES=(
    "sharded_events"
    "person"
    "person_distinct_id2"
    "sharded_sessions"
    "sharded_app_metrics"
    "sharded_app_metrics2"
    "sharded_log_entries"
    "sharded_heatmaps"
    "sharded_performance_events"
    "sharded_session_replay_events"
    "groups"
)

echo "--- Початок створення нативного бекапу ClickHouse ---"

# Формуємо SQL запит для бекапу вибраних таблиць
TABLES_SQL=""
for i in "${!TABLES[@]}"; do
    if [ $i -eq 0 ]; then
        TABLES_SQL="TABLE ${DATABASE}.${TABLES[$i]}"
    else
        TABLES_SQL="${TABLES_SQL}, TABLE ${DATABASE}.${TABLES[$i]}"
    fi
done

BACKUP_QUERY="BACKUP ${TABLES_SQL} TO File('${BACKUP_PATH}/')"

echo "Виконання запиту в ClickHouse..."
docker compose exec -T clickhouse clickhouse-client --query "${BACKUP_QUERY}"

if [ $? -eq 0 ]; then
    echo "✅ Бекап успішно створено у контейнері: ${BACKUP_PATH}"
    
    echo "Створення архіву на хості..."
    # Оскільки /clickhouse-backups зазвичай змонтований до локальної папки data/clickhouse-backups (перевіримо це)
    # Якщо ні, ми можемо скопіювати з контейнера або використати шлях на хості.
    # Припускаємо, що BACKUP_BASE_DIR у контейнері відповідає папці на хості.
    
    # Спробуємо знайти де лежить BACKUP_PATH на хості
    HOST_BACKUP_DIR="./clickhouse-backups/${BACKUP_NAME}"
    
    if [ -d "$HOST_BACKUP_DIR" ]; then
        tar -czf "$TAR_FILE" -C "./clickhouse-backups" "$BACKUP_NAME"
        echo "✅ Архів створено: $TAR_FILE"
    else
        echo "⚠️ Не вдалося знайти папку бекапу на хості за шляхом $HOST_BACKUP_DIR"
        echo "Спробую заархівувати через docker exec..."
        docker compose exec -T clickhouse tar -czf "/tmp/${BACKUP_NAME}.tar.gz" -C "${BACKUP_BASE_DIR}" "${BACKUP_NAME}"
        docker cp $(docker compose ps -q clickhouse):/tmp/${BACKUP_NAME}.tar.gz "$TAR_FILE"
        docker compose exec -T clickhouse rm "/tmp/${BACKUP_NAME}.tar.gz"
        echo "✅ Архів створено через docker cp: $TAR_FILE"
    fi
else
    echo "❌ Помилка при створенні бекапу в ClickHouse!"
    exit 1
fi

echo "--- Готово ---"
echo "Для відновлення використовуйте команду:"
echo "RESTORE TABLE posthog.table_name FROM File('${BACKUP_BASE_DIR}/${BACKUP_NAME}/')"
