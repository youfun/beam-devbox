#!/bin/bash
set -e

echo "[minio-init] Creating MinIO buckets..."

# Wait for MinIO to be ready
for i in {1..30}; do
    if wget -qO- http://localhost:9000/minio/health/live > /dev/null 2>&1; then
        break
    fi
    echo "[minio-init] Waiting for MinIO to be ready... ($i/30)"
    sleep 2
done

# Configure mc alias
mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" > /dev/null 2>&1 || true

# Create default bucket if specified
if [ -n "$MINIO_BUCKET" ]; then
    if ! mc ls local/"$MINIO_BUCKET" > /dev/null 2>&1; then
        echo "[minio-init] Creating bucket: $MINIO_BUCKET"
        mc mb local/"$MINIO_BUCKET"
    else
        echo "[minio-init] Bucket $MINIO_BUCKET already exists"
    fi
fi

echo "[minio-init] MinIO bucket initialization complete."
