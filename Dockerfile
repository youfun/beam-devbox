# beam-devbox: BEAM runtime + PostgreSQL + MinIO
# Multi-stage build for Elixir/Phoenix development environment

ARG DEBIAN_VERSION=bookworm-slim
ARG S6_OVERLAY_VERSION=3.2.0.0
ARG OTP_VERSION=28.0
ARG ELIXIR_VERSION=1.19.0
ARG POSTGRES_VERSION=17
ARG ERLANG_DIST_VERSION=28.4

# ============================================================================
# Stage 1: Elixir Builder (we still need to build Elixir)
# ============================================================================
FROM debian:${DEBIAN_VERSION} AS elixir-builder

ARG ELIXIR_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies for Elixir
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    make \
    git \
    && rm -rf /var/lib/apt/lists/*

# Download and install pre-built Erlang from erlang-dist with checksum verification
# Repository: https://github.com/benoitc/erlang-dist
# The tarball structure is: erlang-VERSION/usr/local/{bin,lib,...}
ARG ERLANG_DIST_VERSION
ARG TARGETARCH

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) ERLANG_ARCH='amd64' ;; \
        arm64) ERLANG_ARCH='arm64' ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    ERLANG_TARBALL="erlang-${ERLANG_DIST_VERSION}-linux-${ERLANG_ARCH}.tar.gz"; \
    ERLANG_URL="https://github.com/benoitc/erlang-dist/releases/download/OTP-${ERLANG_DIST_VERSION}/${ERLANG_TARBALL}"; \
    CHECKSUMS_URL="https://github.com/benoitc/erlang-dist/releases/download/OTP-${ERLANG_DIST_VERSION}/SHA256SUMS"; \
    \
    echo "Downloading Erlang/OTP ${ERLANG_DIST_VERSION} for ${ERLANG_ARCH}..."; \
    curl -fsSL "${ERLANG_URL}" -o "/tmp/${ERLANG_TARBALL}"; \
    curl -fsSL "${CHECKSUMS_URL}" -o "/tmp/SHA256SUMS"; \
    \
    echo "Verifying checksum..."; \
    ACTUAL_SHA=$(sha256sum "/tmp/${ERLANG_TARBALL}" | awk '{print $1}'); \
    echo "Actual SHA256: ${ACTUAL_SHA}"; \
    if ! grep -q "${ACTUAL_SHA}" "/tmp/SHA256SUMS"; then \
        echo "ERROR: Checksum verification failed!"; \
        echo "Downloaded file checksum not found in SHA256SUMS"; \
        exit 1; \
    fi; \
    echo "Checksum verified successfully"; \
    \
    echo "Extracting to /usr/local..."; \
    tar -xzf "/tmp/${ERLANG_TARBALL}" -C /usr/local --strip-components=2; \
    rm -rf "/tmp/${ERLANG_TARBALL}" "/tmp/SHA256SUMS"; \
    ldconfig

# Set PATH to include Erlang binaries
ENV PATH="/usr/local/bin:${PATH}"

# Verify Erlang installation
RUN which erl && which erlc && erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell

# Build and install Elixir
WORKDIR /tmp/elixir
RUN curl -fsSL "https://github.com/elixir-lang/elixir/archive/v${ELIXIR_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 \
    && make compile \
    && make install PREFIX=/usr/local

# Get Mix hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# ============================================================================
# Stage 2: Runtime image
# ============================================================================
FROM debian:${DEBIAN_VERSION} AS runtime

ARG S6_OVERLAY_VERSION
ARG POSTGRES_VERSION
ARG TARGETARCH
ARG ERLANG_DIST_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/root

# Install s6-overlay architecture mapping
RUN case "${TARGETARCH}" in \
    amd64) S6_ARCH=x86_64 ;; \
    arm64) S6_ARCH=aarch64 ;; \
    *) S6_ARCH=${TARGETARCH} ;; \
    esac \
    && echo "S6_ARCH=${S6_ARCH}" > /tmp/s6-arch

# Install base system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    bash \
    procps \
    netcat-traditional \
    libncurses6 \
    libssl3 \
    libwxgtk3.2-1 \
    && rm -rf /var/lib/apt/lists/*

# Add Pigsty apt repository for MinIO (always available)
RUN curl -fsSL https://repo.pigsty.io/key | gpg --dearmor -o /usr/share/keyrings/pigsty.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/pigsty.gpg] https://repo.pigsty.io/apt/infra generic main" \
    > /etc/apt/sources.list.d/pigsty.list

# For PostgreSQL 18+, use official PGDG repository as Pigsty may not have it yet
# For PostgreSQL 17, use Pigsty repository
RUN if [ "${POSTGRES_VERSION}" = "18" ]; then \
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg \
        && echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
    fi \
    && apt-get update

# Install PostgreSQL (from appropriate source) and MinIO from Pigsty
RUN apt-get install -y --no-install-recommends \
    postgresql-${POSTGRES_VERSION} \
    postgresql-client-${POSTGRES_VERSION} \
    postgresql-contrib-${POSTGRES_VERSION} \
    minio \
    mcli \
    && rm -rf /var/lib/apt/lists/*

# Install s6-overlay
RUN S6_ARCH=$(cat /tmp/s6-arch) \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
    | tar -C / -Jxpf - \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
    | tar -C / -Jxpf - \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz" \
    | tar -C / -Jxpf - \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz" \
    | tar -C / -Jxpf -

# Download and install pre-built Erlang from erlang-dist with checksum verification
# Repository: https://github.com/benoitc/erlang-dist
RUN case "${TARGETARCH}" in \
    amd64) ERLANG_ARCH="amd64" ;; \
    arm64) ERLANG_ARCH="arm64" ;; \
    *) ERLANG_ARCH="${TARGETARCH}" ;; \
    esac \
    && ERLANG_TARBALL="erlang-${ERLANG_DIST_VERSION}-linux-${ERLANG_ARCH}.tar.gz" \
    && ERLANG_URL="https://github.com/benoitc/erlang-dist/releases/download/OTP-${ERLANG_DIST_VERSION}/${ERLANG_TARBALL}" \
    && CHECKSUMS_URL="https://github.com/benoitc/erlang-dist/releases/download/OTP-${ERLANG_DIST_VERSION}/SHA256SUMS" \
    && echo "Downloading Erlang/OTP ${ERLANG_DIST_VERSION} from ${ERLANG_URL}" \
    && curl -fsSL "${ERLANG_URL}" -o "/tmp/${ERLANG_TARBALL}" \
    && curl -fsSL "${CHECKSUMS_URL}" -o "/tmp/SHA256SUMS" \
    && ACTUAL_SHA=$(sha256sum "/tmp/${ERLANG_TARBALL}" | awk '{print $1}') \
    && echo "Actual SHA256: ${ACTUAL_SHA}" \
    && if ! grep -q "${ACTUAL_SHA}" "/tmp/SHA256SUMS"; then \
        echo "ERROR: Checksum verification failed!"; \
        exit 1; \
    fi \
    && echo "Checksum verified successfully" \
    && tar -xzf "/tmp/${ERLANG_TARBALL}" -C /usr/local --strip-components=2 \
    && rm -rf "/tmp/${ERLANG_TARBALL}" "/tmp/SHA256SUMS" \
    && ldconfig

# Copy Elixir from builder
COPY --from=elixir-builder /usr/local /usr/local

# Create necessary directories
RUN mkdir -p \
    /app \
    /app/bin \
    /app/lib \
    /var/lib/postgresql/data \
    /var/lib/minio/data \
    /var/run/postgresql \
    /etc/s6-overlay/s6-rc.d \
    /etc/postgres-init.d \
    /etc/minio-init.d

# Set environment variables
ENV PATH="/usr/local/bin:/usr/local/sbin:/usr/lib/postgresql/${POSTGRES_VERSION}/bin:${PATH}" \
    # PostgreSQL settings
    POSTGRES_USER=postgres \
    POSTGRES_PASSWORD=postgres \
    POSTGRES_DB=app_dev \
    PGDATA=/var/lib/postgresql/data \
    PGPORT=5432 \
    # MinIO settings
    MINIO_ROOT_USER=minioadmin \
    MINIO_ROOT_PASSWORD=minioadmin \
    MINIO_VOLUMES=/var/lib/minio/data \
    MINIO_OPTS="--console-address :9001" \
    MINIO_BUCKET=uploads \
    # App settings
    APP_NAME=app \
    # s6-overlay settings
    S6_KEEP_ENV=1 \
    S6_LOGGING=0 \
    S6_SYNC_DISKS=1 \
    S6_SERVICES_GRACETIME=10000 \
    S6_KILL_GRACETIME=5000

# Create postgres user and set permissions
RUN groupadd -r postgres --gid=999 \
    && useradd -r -g postgres --uid=999 --home-dir=/var/lib/postgresql postgres \
    && chown -R postgres:postgres /var/lib/postgresql /var/run/postgresql \
    && chmod 2777 /var/run/postgresql

# Copy s6 service definitions and scripts
COPY s6-overlay/ /etc/s6-overlay/s6-rc.d/
COPY scripts/ /etc/s6-overlay/scripts/

# Make scripts executable
RUN chmod -R +x /etc/s6-overlay/scripts/

# Create bundle directory for s6-rc
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/postgres \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/minio \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/init-services \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/minio-init

# Set ownership for data directories
RUN chown -R postgres:postgres /var/lib/postgresql \
    && chown -R root:root /var/lib/minio

# Expose ports
# 5432: PostgreSQL
# 9000: MinIO API
# 9001: MinIO Console
# 8080: Application (reserved)
EXPOSE 5432 9000 9001 8080

# Volume definitions
VOLUME ["/var/lib/postgresql/data", "/var/lib/minio/data", "/app"]

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB} && \
    wget -qO- http://localhost:9000/minio/health/live

# Use s6-overlay as init system
ENTRYPOINT ["/init"]

# Default command (s6-overlay will manage services)
CMD []
