# beam-devbox

[![Docker Build](https://github.com/yourusername/beam-devbox/actions/workflows/docker-build.yml/badge.svg)](https://github.com/yourusername/beam-devbox/actions/workflows/docker-build.yml)
[![GHCR](https://img.shields.io/badge/GHCR-available-blue?logo=github)](https://github.com/youfun/beam-devbox/pkgs/container/beam-devbox)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> 开源 Docker 基础镜像：BEAM 运行时 + PostgreSQL + MinIO
> 面向 Elixir/Phoenix 开发者，提供开箱即用的测试/开发环境

[English Documentation](README.md)

---

## 快速开始

5 分钟跑起来：

```bash
# 拉取镜像
docker pull ghcr.io/youfun/beam-devbox:otp28

# 使用默认设置运行
docker run -d \
  --name beam-devbox \
  -p 5432:5432 \
  -p 9000:9000 \
  -p 9001:9001 \
  -p 8080:8080 \
  ghcr.io/youfun/beam-devbox:otp28

# 查看服务是否就绪
docker logs -f beam-devbox
```

## 镜像内容

| 组件 | 版本 | 端口 | 说明 |
|-----------|---------|------|-------------|
| Erlang/OTP | 28.x / 27.x | - | BEAM 运行时，可直接运行编译好的 `.beam` 文件 |
| Elixir | 1.19.x / 1.18.x | - | Elixir 编程语言 |
| PostgreSQL | 17 | 5432 | 应用数据库 |
| MinIO | latest | 9000/9001 | 兼容 S3 的对象存储（API/控制台） |
| s6-overlay | 3.2.x | - | 进程管理器，用于管理多个服务 |

## 使用方法

### Docker 运行

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

### 注入应用代码

基础镜像不包含任何应用代码。部署你编译好的 BEAM 文件：

```bash
# 复制编译好的 .beam 文件到容器
docker cp _build/prod/lib/myapp/. beam-devbox:/app/lib/

# 或复制发布包
docker cp myapp-1.0.0.tar.gz beam-devbox:/app/
docker exec beam-devbox tar -xzf /app/myapp-1.0.0.tar.gz -C /app/

# 启动应用
docker exec beam-devbox /app/bin/myapp start
```

## 环境变量

### PostgreSQL

| 变量 | 默认值 | 说明 |
|----------|---------|-------------|
| `POSTGRES_USER` | `postgres` | PostgreSQL 超级用户名 |
| `POSTGRES_PASSWORD` | `postgres` | PostgreSQL 超级用户密码 |
| `POSTGRES_DB` | `app_dev` | 默认创建的数据库 |
| `PGDATA` | `/var/lib/postgresql/data` | PostgreSQL 数据目录 |

### MinIO

| 变量 | 默认值 | 说明 |
|----------|---------|-------------|
| `MINIO_ROOT_USER` | `minioadmin` | MinIO 根用户（访问密钥） |
| `MINIO_ROOT_PASSWORD` | `minioadmin` | MinIO 根密码（秘密密钥） |
| `MINIO_BUCKET` | `uploads` | 启动时自动创建的默认存储桶 |
| `MINIO_VOLUMES` | `/var/lib/minio/data` | MinIO 数据目录 |

### 应用

| 变量 | 默认值 | 说明 |
|----------|---------|-------------|
| `APP_NAME` | `app` | 应用名称，用于 `/app/bin/$APP_NAME` 入口点 |

## 可用标签

| 标签 | OTP | PostgreSQL | 说明 |
|-----|-----|------------|-------------|
| `latest` | 28 | 17 | 最新稳定版 |
| `otp28` | 28 | 17 | OTP 28 配最新 PostgreSQL |
| `otp28-pg17` | 28 | 17 | OTP 28 配 PostgreSQL 17（固定版本） |
| `otp27` | 27 | 17 | OTP 27 配最新 PostgreSQL |
| `otp27-pg17` | 27 | 17 | OTP 27 配 PostgreSQL 17（固定版本） |

所有镜像都支持 `linux/amd64` 和 `linux/arm64` 架构。

## 热同步工作流

为了快速开发，使用 `hot_sync.sh` 将本地更改同步到运行中的容器：

```bash
# scripts/hot_sync.sh
#!/bin/bash
APP_NAME=${APP_NAME:-myapp}
CONTAINER=${CONTAINER:-beam-devbox}

# 本地编译
mix compile

# 同步 .beam 文件到容器
rsync -avz _build/dev/lib/${APP_NAME}/ebin/ ${CONTAINER}:/app/lib/${APP_NAME}/

# 触发热重载（如果你的应用支持）
docker exec ${CONTAINER} /app/bin/${APP_NAME} rpc "Application.stop(:${APP_NAME})"
docker exec ${CONTAINER} /app/bin/${APP_NAME} rpc "Application.start(:${APP_NAME})"
```

## 健康检查

镜像内置了健康检查：

```bash
# 检查 PostgreSQL
docker exec beam-devbox pg_isready -U postgres -d app_dev

# 检查 MinIO
curl http://localhost:9000/minio/health/live

# 检查两者（Docker 健康检查）
docker inspect --format='{{.State.Health.Status}}' beam-devbox
```

## 架构

```
beam-devbox
├── s6-overlay（进程管理器）
│   ├── init-services（一次性初始化）
│   ├── postgres（长期运行的 PostgreSQL）
│   ├── minio（长期运行的 MinIO）
│   └── minio-init（存储桶创建）
├── /app/（应用目录，用户挂载）
├── /var/lib/postgresql/data/（PostgreSQL 数据）
└── /var/lib/minio/data/（MinIO 数据）
```

## 已知限制

1. **NIF 编译**：NIF（本地扩展）必须为目标架构（amd64/arm64）编译。基础镜像只提供运行时。

2. **不含应用代码**：这是一个有意为之的基础镜像，不包含任何应用代码。你必须注入编译好的 BEAM 文件，或将其作为你自己 Dockerfile 的基础。

3. **单节点**：PostgreSQL 和 MinIO 以单节点实例运行，仅适合开发使用。

## 从源码构建

```bash
# 克隆仓库
git clone https://github.com/yourusername/beam-devbox.git
cd beam-devbox

# 本地构建
docker build -t beam-devbox:local .

# 使用特定版本构建
docker build \
  --build-arg OTP_VERSION=28.0 \
  --build-arg ELIXIR_VERSION=1.19.0 \
  --build-arg POSTGRES_VERSION=17 \
  -t beam-devbox:custom .
```

## 贡献指南

1. Fork 仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 提交 Pull Request

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 致谢

- [s6-overlay](https://github.com/just-containers/s6-overlay) - 进程管理
- [erlang-dist](https://github.com/benoitc/erlang-dist) - [@benoitc](https://github.com/benoitc) 维护的预编译 Erlang/OTP 二进制包
- [PostgreSQL](https://www.postgresql.org/) - 世界上最先进的开源关系型数据库
- [MinIO](https://min.io/) - 高性能对象存储
- [Pigsty](https://pigsty.io/) - PostgreSQL 发行版，提供 PostgreSQL 和 MinIO 的 apt 仓库
- [Elixir](https://elixir-lang.org/) - 用于构建可扩展应用的动态函数式语言
