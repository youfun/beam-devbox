# beam-devbox: BEAM runtime + PostgreSQL + MinIO
# Multi-stage build for Elixir/Phoenix development environment

ARG DEBIAN_VERSION=bookworm-slim
ARG S6_OVERLAY_VERSION=3.2.2.0
ARG OTP_VERSION=28.0
ARG ELIXIR_VERSION=1.19.0
ARG POSTGRES_VERSION=17

# ============================================================================
# Stage 1: Build Erlang and Elixir from source
# ============================================================================
FROM debian:${DEBIAN_VERSION} AS builder

ARG OTP_VERSION
ARG ELIXIR_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies (following erlang-dist build configuration)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    curl \
    ca-certificates \
    libncurses5-dev \
    libssl-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libpng-dev \
    libssh-dev \
    unixodbc-dev \
    xsltproc \
    fop \
    libxml2-utils \
    git \
    && (apt-get install -y libwxgtk3.2-dev || apt-get install -y libwxgtk3.0-gtk3-dev || true) \
    && rm -rf /var/lib/apt/lists/*

# Download and build Erlang/OTP (following erlang-dist build process)
WORKDIR /tmp/otp_src
RUN curl -fSL "https://github.com/erlang/otp/releases/download/OTP-${OTP_VERSION}/otp_src_${OTP_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 \
    && export ERL_TOP=$(pwd) \
    && ./configure \
        --prefix=/usr/local \
        --enable-threads \
        --enable-smp-support \
        --enable-kernel-poll \
        --enable-ssl \
        --enable-dynamic-ssl-lib \
        --with-ssl \
        --enable-jit \
    && make -j$(nproc) \
    && make DESTDIR=/tmp/install install

# Verify Erlang installation (skip verification in DESTDIR, will verify in runtime stage)
RUN test -f /tmp/install/usr/local/bin/erl && \
    test -f /tmp/install/usr/local/bin/erlc && \
    echo "Erlang binaries installed successfully"

# Build and install Elixir
WORKDIR /tmp/elixir
RUN curl -fsSL "https://github.com/elixir-lang/elixir/archive/v${ELIXIR_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 \
    && PATH="/tmp/install/usr/local/bin:${PATH}" make compile \
    && PATH="/tmp/install/usr/local/bin:${PATH}" make install PREFIX=/tmp/install/usr/local

# Get Mix hex and rebar
RUN PATH="/tmp/install/usr/local/bin:${PATH}" /tmp/install/usr/local/bin/mix local.hex --force \
    && PATH="/tmp/install/usr/local/bin:${PATH}" /tmp/install/usr/local/bin/mix local.rebar --force

# ============================================================================
# Stage 2: Runtime image
# ============================================================================
FROM debian:${DEBIAN_VERSION} AS runtime

ARG S6_OVERLAY_VERSION
ARG POSTGRES_VERSION
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/root

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
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Add Pigsty apt repository for MinIO (always available)
RUN curl -fsSL https://repo.pigsty.io/key | gpg --dearmor -o /usr/share/keyrings/pigsty.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/pigsty.gpg] https://repo.pigsty.io/apt/infra generic main" \
    > /etc/apt/sources.list.d/pigsty.list

# Add PostgreSQL official PGDG repository for all versions
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list \
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
RUN case "${TARGETARCH}" in \
    amd64) S6_ARCH=x86_64 ;; \
    arm64) S6_ARCH=aarch64 ;; \
    *) S6_ARCH=${TARGETARCH} ;; \
    esac \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
    | tar -C / -Jxpf - \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
    | tar -C / -Jxpf - \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz" \
    | tar -C / -Jxpf - \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz" \
    | tar -C / -Jxpf -

# Copy Erlang and Elixir from builder
COPY --from=builder /tmp/install/usr/local /usr/local

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
