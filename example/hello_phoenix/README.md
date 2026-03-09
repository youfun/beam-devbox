# HelloPhoenix - BeamDevbox Example

A simple Phoenix application demonstrating how to use `beam-devbox` for **development and testing**.

> **Note**: beam-devbox is designed for development/test environments, not production.
> For production deployment, consider using separate PostgreSQL and MinIO services,
> or a container orchestration platform like Kubernetes.

## Features

- 🚀 **Phoenix 1.7** with LiveView
- 🐘 **PostgreSQL** integration (via beam-devbox)
- 📦 **MinIO S3** file uploads (via beam-devbox)
- 🔥 **Hot reload** development workflow
- 🐳 **Single command** infrastructure setup

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Elixir 1.18+ and Erlang/OTP 27+ installed locally (for development)
- beam-devbox image: `docker pull ghcr.io/youfun/beam-devbox:otp28`

### Step 1: Start Infrastructure

```bash
# Start PostgreSQL + MinIO with one command
docker-compose up -d

# Check status
docker-compose ps
docker logs -f phoenix-infra
```

Access the services:
- MinIO Console: http://localhost:9001 (minioadmin/minioadmin)
- PostgreSQL: localhost:5432

### Step 2: Setup Phoenix Locally

```bash
# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Start Phoenix with hot reload
mix phx.server
```

Access the app: http://localhost:4000

## Using beam-devbox

### Development Mode (Recommended)

The recommended workflow is to run infrastructure in Docker and develop locally:

```yaml
# docker-compose.yml
services:
  infra:
    image: ghcr.io/youfun/beam-devbox:otp28  # PostgreSQL + MinIO
    ports:
      - "5432:5432"
      - "9000:9000"
      - "9001:9001"
```

```bash
# Terminal 1: Start infrastructure
docker-compose up -d

# Terminal 2: Develop locally
mix phx.server
```

Benefits:
- Fast code reloading with `mix`
- IDE integration (breakpoints, etc.)
- Familiar local development experience
- Infrastructure is disposable

### CI/CD Testing

For CI/CD pipelines, you can run tests against the beam-devbox container:

```yaml
# .github/workflows/test.yml
jobs:
  test:
    services:
      beam-devbox:
        image: ghcr.io/youfun/beam-devbox:otp28
        ports:
          - 5432:5432
          - 9000:9000
    steps:
      - uses: actions/checkout@v3
      - run: mix deps.get
      - run: mix test
```

### Alternative: Develop Inside Container

If you prefer developing inside the container (e.g., for consistent environments):

```bash
# Uncomment the 'app' service in docker-compose.yml, then:
docker-compose up -d
```

Or use `hot_sync.sh` for rapid development:

```bash
# From project root
../scripts/hot_sync.sh hello_phoenix phoenix-infra
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_HOST` | localhost | PostgreSQL host |
| `POSTGRES_USER` | postgres | Database user |
| `POSTGRES_PASSWORD` | postgres | Database password |
| `POSTGRES_DB` | hello_phoenix_dev | Database name |
| `MINIO_HOST` | localhost | MinIO host |
| `MINIO_PORT` | 9000 | MinIO API port |
| `MINIO_BUCKET` | uploads | Default S3 bucket |

## Project Structure

```
hello_phoenix/
├── config/              # Configuration files
├── lib/
│   ├── hello_phoenix/        # Business logic
│   └── hello_phoenix_web/    # Web interface
├── priv/                # Database migrations, static assets
├── docker-compose.yml   # Infrastructure orchestration
└── README.md
```

## Why beam-devbox for Development?

1. **One container for everything**: No need to manage separate PG and MinIO containers
2. **Pre-configured**: Database and bucket are initialized automatically
3. **Portable**: Same image works on macOS, Linux, Windows (WSL)
4. **Fast setup**: `docker-compose up` and you're ready to code

## Production Considerations

For production deployment:

1. Use managed PostgreSQL (AWS RDS, Google Cloud SQL, etc.)
2. Use managed S3 (AWS S3, Google Cloud Storage, etc.) or dedicated MinIO cluster
3. Build a release with `mix release` and deploy to containers/VMs
4. Do NOT use beam-devbox as the production base image

## Learn More

- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html)
- [beam-devbox Documentation](../../README.md)
- [Elixir School](https://elixirschool.com/)

## License

MIT
