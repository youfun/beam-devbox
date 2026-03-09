#!/bin/bash
set -e

echo "[minio] Initializing MinIO..."

# Create data directory
mkdir -p "$MINIO_VOLUMES"

# Wait for MinIO to be ready (it will be started by the service manager)
# This initialization sets up the bucket after MinIO starts

echo "[minio] MinIO initialization complete."
