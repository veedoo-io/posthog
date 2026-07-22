Щоб виправити помилку 500 Internal Server Error на вашому сервері шляхом видалення пошкоджених даних, виконайте наступну команду безпосередньо на сервері:
docker compose exec -T db psql -U posthog -d posthog -c "
DELETE FROM posthog_externaldataschema
WHERE source_id IS NOT NULL
AND source_id NOT IN (SELECT id FROM posthog_externaldatasource);

DELETE FROM posthog_datawarehousetable
WHERE external_data_source_id IS NOT NULL
AND external_data_source_id NOT IN (SELECT id FROM posthog_externaldatasource);
"