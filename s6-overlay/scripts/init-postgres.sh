#!/bin/bash
set -e

echo "[postgres] Initializing PostgreSQL..."

# Create data directory if it doesn't exist
if [ ! -d "$PGDATA" ]; then
    mkdir -p "$PGDATA"
fi

# Initialize database if not already initialized
if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "[postgres] Running initdb..."
    chown -R postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"

    su - postgres -c "initdb -D $PGDATA --encoding=UTF8 --locale=C.UTF-8"

    # Configure PostgreSQL to listen on all interfaces
    cat >> "$PGDATA/postgresql.conf" << EOF

# beam-devbox configuration
listen_addresses = '*'
port = 5432
max_connections = 100
shared_buffers = 128MB
EOF

    # Configure pg_hba.conf for local and remote access
    cat >> "$PGDATA/pg_hba.conf" << EOF

# beam-devbox authentication
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
EOF

    echo "[postgres] Database initialized."
fi

# Start PostgreSQL temporarily to create user and database
echo "[postgres] Starting temporary PostgreSQL for setup..."
su - postgres -c "pg_ctl -D $PGDATA start -w -t 30"

# Create user and database
if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$POSTGRES_USER'\"" | grep -q 1; then
    echo "[postgres] Creating user: $POSTGRES_USER"
    su - postgres -c "psql -c \"CREATE USER \"$POSTGRES_USER\" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';\""
fi

if ! su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$POSTGRES_DB'\"" | grep -q 1; then
    echo "[postgres] Creating database: $POSTGRES_DB"
    su - postgres -c "createdb -O \"$POSTGRES_USER\" \"$POSTGRES_DB\""
fi

# Stop temporary PostgreSQL
echo "[postgres] Stopping temporary PostgreSQL..."
su - postgres -c "pg_ctl -D $PGDATA stop -w -t 30"

echo "[postgres] PostgreSQL initialization complete."
