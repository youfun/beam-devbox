# beam-devbox

[![Docker Build](https://github.com/yourusername/beam-devbox/actions/workflows/docker-build.yml/badge.svg)](https://github.com/yourusername/beam-devbox/actions/workflows/docker-build.yml)
[![GHCR](https://img.shields.io/badge/GHCR-available-blue?logo=github)](https://github.com/youfun/beam-devbox/pkgs/container/beam-devbox)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> A Docker base image with BEAM runtime + PostgreSQL + MinIO
> One-stop development/testing environment for Elixir/Phoenix developers

[中文文档](README.zh-CN.md)

---

## Quick Start

Get started in 5 minutes:

```bash
# Pull the image
docker pull ghcr.io/youfun/beam-devbox:otp28

# Run with default settings
docker run -d \
  --name beam-devbox \
  -p 5432:5432 \
  -p 9000:9000 \
  -p 9001:9001 \
  -p 8080:8080 \
  ghcr.io/youfun/beam-devbox:otp28

# Check services are ready
docker logs -f beam-devbox
```

## What's Inside

| Component | Version | Port | Description |
|-----------|---------|------|-------------|
| Erlang/OTP | 28.x / 27.x | - | BEAM runtime for running compiled `.beam` files |
| Elixir | 1.19.x / 1.18.x | - | Elixir programming language |
| PostgreSQL | 17 | 5432 | Application database |
| MinIO | latest | 9000/9001 | S3-compatible object storage (API/Console) |
| s6-overlay | 3.2.x | - | Process supervisor for managing multiple services |

## Usage

### Docker Run

```bash
docker run -d \
  --name my-beam-app \
  -p 5432:5432 \
  -p 9000:9000 \
  -p 9001:9001 \
  -p 8080:8080 \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD=mypass \
  -e POSTGRES_DB=myapp_dev \
  -e MINIO_ROOT_USER=minio \
  -e MINIO_ROOT_PASSWORD=minio123 \
  -e MINIO_BUCKET=mybucket \
  -v /host/pgdata:/var/lib/postgresql/data \
  -v /host/miniodata:/var/lib/minio/data \
  -v /host/app:/app \
  ghcr.io/youfun/beam-devbox:otp28
```

### Docker Compose

```yaml
version: '3.8'

services:
  app:
    image: ghcr.io/youfun/beam-devbox:otp28
    container_name: beam-devbox
    ports:
      - "5432:5432"
      - "9000:9000"
      - "9001:9001"
      - "8080:8080"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app_dev
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
      MINIO_BUCKET: uploads
      APP_NAME: myapp
    volumes:
      - pgdata:/var/lib/postgresql/data
      - miniodata:/var/lib/minio/data
      - ./app:/app
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres", "-d", "app_dev"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
  miniodata:
```

### Inject Your Application

The base image contains no application code. Deploy your compiled BEAM files:

```bash
# Copy compiled .beam files to the container
docker cp _build/prod/lib/myapp/. beam-devbox:/app/lib/

# Copy release tarball
docker cp myapp-1.0.0.tar.gz beam-devbox:/app/
docker exec beam-devbox tar -xzf /app/myapp-1.0.0.tar.gz -C /app/

# Start your application
docker exec beam-devbox /app/bin/myapp start
```

## Environment Variables

### PostgreSQL

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | `postgres` | PostgreSQL superuser name |
| `POSTGRES_PASSWORD` | `postgres` | PostgreSQL superuser password |
| `POSTGRES_DB` | `app_dev` | Default database to create |
| `PGDATA` | `/var/lib/postgresql/data` | PostgreSQL data directory |

### MinIO

| Variable | Default | Description |
|----------|---------|-------------|
| `MINIO_ROOT_USER` | `minioadmin` | MinIO root user (access key) |
| `MINIO_ROOT_PASSWORD` | `minioadmin` | MinIO root password (secret key) |
| `MINIO_BUCKET` | `uploads` | Default bucket to create on startup |
| `MINIO_VOLUMES` | `/var/lib/minio/data` | MinIO data directory |

### Application

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_NAME` | `app` | Application name, used for `/app/bin/$APP_NAME` entry point |

## Available Tags

| Tag | OTP | PostgreSQL | Description |
|-----|-----|------------|-------------|
| `latest` | 28 | 17 | Latest stable release |
| `otp28` | 28 | 17 | OTP 28 with latest PostgreSQL |
| `otp28-pg17` | 28 | 17 | OTP 28 with PostgreSQL 17 (pinned) |
| `otp27` | 27 | 17 | OTP 27 with latest PostgreSQL |
| `otp27-pg17` | 27 | 17 | OTP 27 with PostgreSQL 17 (pinned) |

All images support both `linux/amd64` and `linux/arm64` architectures.

## Hot Sync Workflow

For rapid development, use `hot_sync.sh` to sync your local changes to the running container:

```bash
# scripts/hot_sync.sh
#!/bin/bash
APP_NAME=${APP_NAME:-myapp}
CONTAINER=${CONTAINER:-beam-devbox}

# Build locally
mix compile

# Sync .beam files to container
rsync -avz _build/dev/lib/${APP_NAME}/ebin/ ${CONTAINER}:/app/lib/${APP_NAME}/

# Trigger hot reload (if your app supports it)
docker exec ${CONTAINER} /app/bin/${APP_NAME} rpc "Application.stop(:${APP_NAME})"
docker exec ${CONTAINER} /app/bin/${APP_NAME} rpc "Application.start(:${APP_NAME})"
```

## Health Checks

The image includes built-in health checks:

```bash
# Check PostgreSQL
docker exec beam-devbox pg_isready -U postgres -d app_dev

# Check MinIO
curl http://localhost:9000/minio/health/live

# Check both (Docker healthcheck)
docker inspect --format='{{.State.Health.Status}}' beam-devbox
```

## Architecture

```
beam-devbox
├── s6-overlay (process supervisor)
│   ├── init-services (one-shot initialization)
│   ├── postgres (long-running PostgreSQL)
│   ├── minio (long-running MinIO)
│   └── minio-init (bucket creation)
├── /app/ (application directory, user-mounted)
├── /var/lib/postgresql/data/ (PostgreSQL data)
└── /var/lib/minio/data/ (MinIO data)
```

## Known Limitations

1. **NIF Compilation**: NIFs (native extensions) must be compiled for the target architecture (amd64/arm64). The base image provides the runtime only.

2. **No Application Code**: This is intentionally a base image without any application code. You must inject your compiled BEAM files or use this as a base for your own Dockerfile.

3. **Single Node**: PostgreSQL and MinIO run as single-node instances suitable for development only.

## Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/beam-devbox.git
cd beam-devbox

# Build locally
docker build -t beam-devbox:local .

# Build with specific versions
docker build \
  --build-arg OTP_VERSION=28.0 \
  --build-arg ELIXIR_VERSION=1.19.0 \
  --build-arg POSTGRES_VERSION=17 \
  -t beam-devbox:custom .
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [s6-overlay](https://github.com/just-containers/s6-overlay) - Process supervision
- [erlang-dist](https://github.com/benoitc/erlang-dist) - Pre-built Erlang/OTP binaries by [@benoitc](https://github.com/benoitc)
- [PostgreSQL](https://www.postgresql.org/) - World's most advanced open source relational database
- [MinIO](https://min.io/) - High-performance object storage
- [Pigsty](https://pigsty.io/) - PostgreSQL distribution with apt repository for PostgreSQL and MinIO
- [Elixir](https://elixir-lang.org/) - Dynamic, functional language designed for building scalable applications
