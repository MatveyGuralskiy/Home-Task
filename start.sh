#!/bin/bash
# Helfy task
# Matvey Guralskiy

set -e

start_service_and_wait() {
  local service=$1
  local host=$2
  local port=$3
  local retries=15
  local count=0

  echo "Starting $service..."
  docker-compose up -d $service

  echo "Waiting for $service on port $port..."
  until nc -z $host $port; do
    count=$((count + 1))
    if [ $count -ge $retries ]; then
      echo "Timeout waiting for $service"
      exit 1
    fi
    sleep 2
  done
  echo "$service is up"
}

start_service_and_wait zookeeper localhost 2181
start_service_and_wait kafka localhost 9092
start_service_and_wait tidb localhost 4000

echo "Starting backend..."
docker-compose up -d backend

echo "Starting frontend..."
docker-compose up -d frontend

echo "All services started."
