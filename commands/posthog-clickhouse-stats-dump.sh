#!/bin/bash

# Скрипт для створення дампу статистичних даних PostHog ClickHouse
# Включає події, користувачів та агреговані метрики

DUMP_DIR="./clickhouse-backups/clickhouse-stats-dump-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DUMP_DIR"

# Список таблиць для дампу (основна статистика)
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

echo "--- Починаємо дамп статистичних даних PostHog ---"
echo "Директорія дампу: $DUMP_DIR"

for TABLE in "${TABLES[@]}"; do
    echo "Експорт таблиці $TABLE..."
    
    # Отримуємо структуру (CREATE TABLE)
    docker compose exec -T clickhouse clickhouse-client --query "SHOW CREATE TABLE posthog.$TABLE" > "$DUMP_DIR/$TABLE.sql"
    
    # Експортуємо дані у форматі Native (найшвидший для ClickHouse)
    # Ми використовуємо стиснення для економії місця
    docker compose exec -T clickhouse clickhouse-client --query "SELECT * FROM posthog.$TABLE" --format Native | gzip > "$DUMP_DIR/$TABLE.native.gz"
    
    if [ $? -eq 0 ]; then
        SIZE=$(du -h "$DUMP_DIR/$TABLE.native.gz" | cut -f1)
        echo "  Успішно: $TABLE (розмір: $SIZE)"
    else
        echo "  Помилка при експорті $TABLE"
    fi
done

echo "--- Дамп завершено ---"
echo "Створення архіву..."
TAR_FILE="$DUMP_DIR.tar.gz"
tar -czf "$TAR_FILE" -C "$(dirname "$DUMP_DIR")" "$(basename "$DUMP_DIR")"

if [ $? -eq 0 ]; then
    echo "Архів успішно створено: $TAR_FILE"
    echo "Видалення тимчасових файлів..."
    rm -rf "$DUMP_DIR"
else
    echo "Помилка при створенні архіву!"
    echo "Файли залишилися у: $DUMP_DIR"
    exit 1
fi

echo "--- Готово ---"
echo "Для відновлення:"
echo "1. Розпакуйте: tar -xzf $(basename "$TAR_FILE")"
echo "2. Завантажте дані: gunzip -c <table_name>.native.gz | docker compose exec -T clickhouse clickhouse-client --query \"INSERT INTO posthog.table FORMAT Native\""
