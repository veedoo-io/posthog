#!/bin/bash

# Скрипт для повного перерахунку Web Analytics в ClickHouse
# Має запускатися всередині контейнера clickhouse або через docker exec

DATABASE="posthog"
TEAM_ID=${1:-1}

# 1. Очищення застарілих даних
echo "Очищення таблиць пре-агрегації та сесій..."
clickhouse-client --query "TRUNCATE TABLE $DATABASE.sharded_web_overview_preaggregated"
clickhouse-client --query "TRUNCATE TABLE $DATABASE.sharded_web_stats_preaggregated"
clickhouse-client --query "TRUNCATE TABLE $DATABASE.web_pre_aggregated_teams"
clickhouse-client --query "TRUNCATE TABLE $DATABASE.web_pre_aggregated_stats"
clickhouse-client --query "TRUNCATE TABLE $DATABASE.web_pre_aggregated_stats_staging"

DATABASE="posthog"
TEAM_ID=${1:-1}
# 2. Синхронізація сесій (raw_sessions)
echo "Синхронізація таблиці сесій з подій (подневно для економії пам'яті)..."

# Налаштування для економії пам'яті
CH_SETTINGS="--max_memory_usage 2000000000 --max_bytes_before_external_group_by 1000000000 --max_query_size 10000000"

# Оптимізоване отримання днів: використовуємо тільки поле timestamp (яке є в індексі)
echo "Отримання списку днів..."
# Scan only by timestamp and team_id (both are indexed) to get potential days.
# This avoids expensive JSON parsing for the whole table.
DAYS=$(clickhouse-client $CH_SETTINGS --query "
    SELECT DISTINCT toDate(timestamp) 
    FROM $DATABASE.sharded_events 
    WHERE team_id = $TEAM_ID 
      AND timestamp > now() - INTERVAL 3 YEAR 
    ORDER BY 1")

if [ -z "$DAYS" ]; then
    echo "❌ Помилка: Не знайдено жодного дня з подіями. Перевірте TEAM_ID та наявність даних."
    exit 1
fi

echo "Знайдено днів для обробки: $(echo $DAYS | wc -w)"

# 2. Синхронізація сесій (raw_sessions)
echo "Крок 1: Синхронізація таблиці сесій (raw_sessions)..."
for day in $DAYS; do
    echo "  - Обробка сесій за день: $day..."
    # Перевіряємо, чи є сесії в цей день перед великим запитом
    HAS_SESSIONS=$(clickhouse-client $CH_SETTINGS --query "SELECT 1 FROM $DATABASE.sharded_events WHERE team_id = $TEAM_ID AND toDate(timestamp) = '$day' AND JSONExtractString(properties, '\$session_id') != '' LIMIT 1")
    
    if [ "$HAS_SESSIONS" == "1" ]; then
        clickhouse-client $CH_SETTINGS --query "
        INSERT INTO $DATABASE.sharded_raw_sessions 
        (team_id, session_id_v7, distinct_id, min_timestamp, max_timestamp, 
         initial_browser, initial_os, initial_device_type, initial_geoip_country_code, 
         entry_url, pageview_count)
        SELECT 
            team_id, 
            toUInt128(accurateCastOrNull(JSONExtractString(properties, '\$session_id'), 'UUID')) as session_id_v7,
            argMaxState(distinct_id, timestamp),
            minSimpleState(timestamp),
            maxSimpleState(timestamp),
            argMinState(JSONExtractString(properties, '\$browser'), timestamp),
            argMinState(JSONExtractString(properties, '\$os'), timestamp),
            argMinState(JSONExtractString(properties, '\$device_type'), timestamp),
            argMinState(JSONExtractString(properties, '\$geoip_country_code'), timestamp),
            argMinState(JSONExtractString(properties, '\$current_url'), timestamp),
            sumSimpleState(if(event = '\$pageview', 1, 0))
        FROM $DATABASE.sharded_events
        WHERE team_id = $TEAM_ID 
          AND toDate(timestamp) = '$day'
          AND JSONExtractString(properties, '\$session_id') != ''
        GROUP BY team_id, session_id_v7"
    else
        echo "    (сесій не знайдено, пропускаємо)"
    fi
done

# 3. Наповнення Web Overview
echo "Крок 2: Наповнення таблиці Overview (Visitors, Sessions, Pageviews)..."
for day in $DAYS; do
    echo "  - Обробка Overview за день: $day..."
    clickhouse-client $CH_SETTINGS --query "
    INSERT INTO $DATABASE.sharded_web_overview_preaggregated 
    (team_id, job_id, time_window_start, uniq_users_state, uniq_sessions_state, sum_pageviews_state, avg_duration_state, avg_bounce_state, computed_at, expires_at)
    SELECT team_id, generateUUIDv4(), toStartOfHour(timestamp) AS time_window_start, uniqState(person_id), uniqState(JSONExtractString(properties, '\$session_id')), sumState(cast(1, 'Int64')), avgState(cast(0, 'Float64')), avgState(cast(0, 'Int64')), now(), now() + toIntervalDay(30)
    FROM $DATABASE.sharded_events 
    WHERE event = '\$pageview' 
      AND team_id = $TEAM_ID 
      AND toDate(timestamp) = '$day'
    GROUP BY team_id, time_window_start"
done

# 4. Наповнення Web Stats (Path, Browser, Device, OS, Country)
echo "Крок 3: Наповнення таблиць статистики (Breakdowns)..."

BREAKDOWNS=("pathname" "browser" "device_type" "os" "geoip_country_code")

for breakdown in "${BREAKDOWNS[@]}"; do
    echo "  - Обробка розрізу: $breakdown..."
    for day in $DAYS; do
        echo "    - День: $day..."
        clickhouse-client $CH_SETTINGS --query "
        INSERT INTO $DATABASE.sharded_web_stats_preaggregated 
        (team_id, job_id, time_window_start, breakdown_by, breakdown_value, uniq_users_state, sum_pageviews_state, computed_at, expires_at)
        SELECT 
            team_id, 
            generateUUIDv4(), 
            toStartOfHour(timestamp) AS t, 
            '$breakdown' as breakdown_by, 
            JSONExtractString(properties, '\$$breakdown') as val, 
            uniqState(person_id), 
            sumState(cast(1, 'Int64')), 
            now(), 
            now() + toIntervalDay(30)
        FROM $DATABASE.sharded_events 
        WHERE event = '\$pageview' 
          AND team_id = $TEAM_ID 
          AND toDate(timestamp) = '$day'
        GROUP BY team_id, t, breakdown_by, val"
    done
done

DATABASE="posthog"
TEAM_ID=${1:-1}
# 5. Оновлення стану для PostHog
clickhouse-client --query "INSERT INTO $DATABASE.web_pre_aggregated_teams (team_id, last_aggregated_at) VALUES ($TEAM_ID, now())"

# 6. Оптимізація
echo "Оптимізація таблиць..."
DATABASE="posthog"
TEAM_ID=${1:-1}
clickhouse-client --query "OPTIMIZE TABLE $DATABASE.sharded_raw_sessions FINAL"
clickhouse-client --query "OPTIMIZE TABLE $DATABASE.sharded_web_overview_preaggregated FINAL"
clickhouse-client --query "OPTIMIZE TABLE $DATABASE.sharded_web_stats_preaggregated FINAL"

echo "✅ Перерахунок завершено для Team $TEAM_ID!"
echo "Не забудьте очистити кеш Redis у веб-контейнері: python3 manage.py shell -c 'from django.core.cache import cache; cache.clear()'"
