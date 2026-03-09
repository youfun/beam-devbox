#!/bin/bash
# Wait for PostgreSQL to be ready

set -e

host="${1:-localhost}"
port="${2:-5432}"
user="${3:-$POSTGRES_USER}"
db="${4:-$POSTGRES_DB}"
timeout="${5:-60}"

echo "Waiting for PostgreSQL at $host:$port..."

for i in $(seq 1 $timeout); do
    if pg_isready -h "$host" -p "$port" -U "$user" -d "$db" >/dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        exit 0
    fi
    echo "Waiting... ($i/$timeout)"
    sleep 1
done

echo "Timeout waiting for PostgreSQL"
exit 1
