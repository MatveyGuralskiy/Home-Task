#!/bin/bash

echo "TiCDC Status Check"
echo "1. Checking TiCDC capture status"
docker exec home-task-ticdc-1 /cdc cli capture list --server=http://127.0.0.1:8300

echo -e "\n2. Checking current changefeeds"
docker exec home-task-ticdc-1 /cdc cli changefeed list --server=http://127.0.0.1:8300

echo -e "\n3. Ensuring changefeed exists with correct configuration"
CHANGEFEED_EXISTS=$(docker exec home-task-ticdc-1 /cdc cli changefeed query --server=http://127.0.0.1:8300 --changefeed-id="test-cf" >/dev/null 2>&1 && echo "1" || echo "0")

if [ "$CHANGEFEED_EXISTS" = "0" ]; then
    echo "Creating new changefeed..."
    docker exec home-task-ticdc-1 /cdc cli changefeed create \
        --server=http://127.0.0.1:8300 \
        --sink-uri="kafka://kafka:9092/ticdc-testdb-users?protocol=canal-json" \
        --changefeed-id="test-cf"
    echo "Changefeed created successfully"
else
    echo "Changefeed exists, checking configuration..."
    echo "Will check changefeed configuration in next step"
fi

echo -e "\n4. Showing changefeed details"
docker exec home-task-ticdc-1 /cdc cli changefeed query --server=http://127.0.0.1:8300 --changefeed-id="test-cf"

echo -e "\n5. Ensuring changefeed is running"
CHANGEFEED_STATE=$(docker exec home-task-ticdc-1 /cdc cli changefeed query --server=http://127.0.0.1:8300 --changefeed-id="test-cf" | jq -r '.state' 2>/dev/null || echo "unknown")

if [ "$CHANGEFEED_STATE" = "unknown" ]; then
    echo "Changefeed doesn't exist, creating it..."
    docker exec home-task-ticdc-1 /cdc cli changefeed create \
        --server=http://127.0.0.1:8300 \
        --sink-uri="kafka://kafka:9092/ticdc-testdb-users?protocol=canal-json" \
        --changefeed-id="test-cf"
    echo "Changefeed created successfully"
    sleep 3
elif [ "$CHANGEFEED_STATE" != "normal" ]; then
    echo "Changefeed state is $CHANGEFEED_STATE"
    if [ "$CHANGEFEED_STATE" = "failed" ]; then
        echo "Changefeed is in failed state, removing and recreating..."
        docker exec home-task-ticdc-1 /cdc cli changefeed remove --server=http://127.0.0.1:8300 --changefeed-id="test-cf"
        sleep 2
        docker exec home-task-ticdc-1 /cdc cli changefeed create \
            --server=http://127.0.0.1:8300 \
            --sink-uri="kafka://kafka:9092/ticdc-testdb-users?protocol=canal-json" \
            --changefeed-id="test-cf"
        echo "Changefeed recreated successfully"
    else
        echo "Resuming changefeed..."
        docker exec home-task-ticdc-1 /cdc cli changefeed resume --server=http://127.0.0.1:8300 --changefeed-id="test-cf"
    fi
    sleep 3
else
    echo "Changefeed is running normally"
fi

echo -e "\n6. Testing database changes to trigger CDC"
echo "Current users table state:"
echo "Note: MySQL client not available in TiDB container, skipping database state display"

echo -e "\nMaking login attempts to trigger CDC events:"
for i in {1..2}; do
  echo "Login attempt $i:"
  curl -s -X POST http://localhost:3000/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"adminpass"}' | jq .
  sleep 1
done

echo -e "\nUpdated users table state:"
echo "Note: MySQL client not available in TiDB container, skipping database state display"

echo -e "\n7. Starting CDC consumer in backend"
echo "Checking Kafka topic..."
docker exec home-task-kafka-1 kafka-topics.sh --bootstrap-server localhost:9092 --list | grep ticdc-testdb-users || echo "Topic will be created automatically by TiCDC"

echo "Waiting for changefeed to be ready..."
for i in {1..10}; do
    CHANGEFEED_STATE=$(docker exec home-task-ticdc-1 /cdc cli changefeed query --server=http://127.0.0.1:8300 --changefeed-id="test-cf" | jq -r '.state' 2>/dev/null || echo "unknown")
    if [ "$CHANGEFEED_STATE" = "normal" ]; then
        echo "Changefeed is ready"
        break
    fi
    echo "Waiting for changefeed to be ready... (attempt $i/10)"
    sleep 3
done

echo "Waiting for Kafka topic to be created..."
for i in {1..10}; do
    TOPIC_EXISTS=$(docker exec home-task-kafka-1 kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep -c "ticdc-testdb-users" || echo "0")
    if [ "$TOPIC_EXISTS" = "1" ]; then
        echo "Kafka topic exists"
        break
    fi
    echo "Waiting for Kafka topic to be created... (attempt $i/10)"
    sleep 3
done

echo "Starting CDC consumer..."
echo "Testing Kafka connection..."
docker exec home-task-backend-1 node -e "
const { Kafka } = require('kafkajs');
const kafka = new Kafka({
    clientId: 'test-client',
    brokers: ['kafka:9092'],
});
const admin = kafka.admin();
admin.connect().then(() => {
    console.log('Kafka connection successful');
    return admin.disconnect();
}).catch(err => {
    console.log('Kafka connection failed:', err.message);
    process.exit(1);
});
"

docker exec home-task-backend-1 node cdc-consumer.js &
CDC_CONSUMER_PID=$!

echo -e "\n8. Final changefeed status"
echo "Changefeed details:"
docker exec home-task-ticdc-1 /cdc cli changefeed query --server=http://127.0.0.1:8300 --changefeed-id="test-cf" | jq '{id, state, sink_uri, checkpoint_time}' 2>/dev/null || echo "Changefeed status unavailable"

echo -e "\nChangefeed list:"
docker exec home-task-ticdc-1 /cdc cli changefeed list --server=http://127.0.0.1:8300

echo -e "\n9. Watching TiCDC logs for change events"
echo "Press Ctrl+C to stop monitoring"
docker-compose logs -f ticdc | grep --line-buffered -E "(changefeed|kafka|sink)" &

docker-compose logs -f backend | grep --line-buffered -E "(cdc|kafka|consumer)" &

trap 'echo -e "\nStopping monitoring..."; kill $CDC_CONSUMER_PID 2>/dev/null; pkill -f "docker-compose logs" 2>/dev/null; exit 0' INT
wait