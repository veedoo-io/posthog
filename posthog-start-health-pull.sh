export DOMAIN=localhost

echo "Starting the stack!"

# Retry docker-compose up with --pull always up to 3 times
for attempt in 1 2 3; do
    echo "Starting stack (attempt $attempt/3)..."
    if sudo -E docker-compose -f docker-compose.yml up -d --no-build --pull always; then
        echo "Stack started successfully"
        break
    else
        if [ $attempt -lt 3 ]; then
            echo "Failed to start stack, waiting 30s before retry..."
            sleep 30
        else
            echo "Failed to start stack after 3 attempts"
            exit 1
        fi
    fi
done


if [ -z "$SKIP_HEALTH_CHECK" ]; then
    # Normal hobby deployment: wait for health check
    echo "We will need to wait ~5-10 minutes for things to settle down, migrations to finish, and TLS certs to be issued"
    echo ""
    echo "⏳ Waiting for PostHog web to boot (this will take a few minutes)"
    echo "   (timeout after 10 minutes if app doesn't start)"

    # Wait for health check with 600 second timeout
    # Track the start time to measure actual wait time
    HEALTH_START=$(date +%s)
    # shellcheck disable=SC2016 # Single quotes intentional - %{http_code} is curl format string, not shell variable
    if timeout 600 bash -c 'while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' localhost/_health)" != "200" ]]; do sleep 5; done'; then
        HEALTH_END=$(date +%s)
        HEALTH_DURATION=$((HEALTH_END - HEALTH_START))
        echo "⌛️ PostHog looks up! (after ${HEALTH_DURATION} seconds)"
        echo ""
        echo "🎉🎉🎉  Done! 🎉🎉🎉"
    else
        HEALTH_EXIT=$?
        echo ""
        if [ $HEALTH_EXIT -eq 124 ]; then
            echo "❌ Health check timed out after 10 minutes"
            echo "   The application did not start within the expected timeframe"
        else
            echo "❌ Health check failed with exit code: $HEALTH_EXIT"
        fi
        echo ""
        echo "Please check the logs with 'docker-compose logs' for more details."
        echo "Common issues:"
        echo "  - Docker image pull failed: 'docker logs <container>'"
        echo "  - Database migration stuck: 'docker-compose logs db clickhouse'"
        echo "  - Insufficient memory: 'free -h' and 'top'"
        exit 1
    fi
else
    # CI mode: skip health check, exit immediately after docker-compose up
    echo "⏭️  Skipping health check (SKIP_HEALTH_CHECK is set)"
    echo "Stack started, containers are running in background"
fi


echo ""
echo "To stop the stack run 'docker-compose stop'"
echo "To start the stack again run 'docker-compose start'"
echo "If you have any issues at all delete everything in this directory and run the curl command again"
echo ""
# shellcheck disable=SC2016 # we don't want to expand this expression
echo 'To upgrade: run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/posthog/posthog/HEAD/bin/upgrade-hobby)"'
echo ""
echo "PostHog will be up at the location you provided!"
echo "https://${DOMAIN}"
echo ""
echo "It's dangerous to go alone! Take this: 🦔"