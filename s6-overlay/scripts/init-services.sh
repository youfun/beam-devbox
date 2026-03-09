#!/command/execlineb -P

# Initialize PostgreSQL and MinIO services
# This script runs once before the long-running services start

foreground { echo "=== Initializing beam-devbox services ===" }

# Run PostgreSQL initialization
foreground { /etc/s6-overlay/scripts/init-postgres.sh }

# Run MinIO initialization
foreground { /etc/s6-overlay/scripts/init-minio.sh }

foreground { echo "=== Initialization complete ===" }
