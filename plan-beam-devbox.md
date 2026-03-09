# beam-devbox — 开发计划

> 开源 Docker 基础镜像：BEAM 运行时 + PostgreSQL + MinIO
> 面向 Elixir/Phoenix 开发者，提供开箱即用的测试/开发环境

---

## 一、背景与目标

**问题：** Elixir 项目每次部署测试环境需要重建完整 Docker 镜像（含编译），耗时长。

**解法：** 提供一个包含所有基础设施的"底座镜像"：
- BEAM/OTP 运行时（可直接运行 `.beam` 文件）
- PostgreSQL（应用数据库）
- MinIO（S3 兼容对象存储）

使用方式：
```bash
# 拉基础镜像
docker pull ghcr.io/youfun/beam-devbox:otp28

# 把编译好的 .beam 注入进去就能跑
docker cp myapp.tar.gz beamdevbox:/app/lib/
```

配合 `hot_sync.sh`（本地编译 → rsync beam → 热加载），实现秒级代码更新。

---

## 二、项目信息

| 项 | 内容 |
|----|------|
| 项目名 | `beam-devbox` |
| GitHub | `github.com/你的账号/beam-devbox` |
| Docker Hub | `ghcr.io/youfun/beam-devbox` |
| License | MIT |
| 目标用户 | Elixir/Phoenix 开发者、CI 流水线 |

---

## 三、镜像设计

### 3.1 包含内容

```
beam-devbox
├── Erlang/OTP 28
├── Elixir 1.19.x
├── PostgreSQL 17
├── MinIO (latest stable)
└── 基础工具：bash, wget, curl, ca-certificates
```

### 3.2 进程管理

多进程用 **s6-overlay**（轻量，比 supervisord 更适合容器）：

```
s6-overlay
├── PostgreSQL 服务
├── MinIO 服务
└── 应用进程（由用户注入）
```

### 3.3 目录结构

```
/app/          ← 应用根目录（用户注入 .beam 到这里）
/var/lib/pg/   ← PostgreSQL 数据目录
/var/lib/minio/← MinIO 数据目录
/etc/s6-overlay/services/  ← 服务定义
```

### 3.4 暴露端口

| 端口 | 服务 |
|------|------|
| 5432 | PostgreSQL |
| 9000 | MinIO API |
| 9001 | MinIO Console |
| 8080 | 预留给应用 |

---

## 四、Tag 策略

```
ghcr.io/youfun/beam-devbox:latest          → 最新稳定版
ghcr.io/youfun/beam-devbox:otp28           → OTP 28 + 最新 PG + MinIO
ghcr.io/youfun/beam-devbox:otp28-pg17      → 固定 PG 版本
ghcr.io/youfun/beam-devbox:otp27           → OTP 27 版本
```

---

## 五、环境变量

```bash
# PostgreSQL
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=app_dev

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
MINIO_BUCKET=uploads         # 自动创建的默认 bucket

# 应用
APP_NAME=app                 # 决定 /app/bin/app 入口
```

---

## 六、交付物清单

### P0 — 核心镜像（必须完成）

- [ ] `Dockerfile` 多阶段构建
  - 基于 `debian:bookworm-slim`（兼容性最好）
  - 安装 Erlang/OTP + Elixir（通过 asdf 或官方包）
  - 安装 PostgreSQL 17
  - 安装 MinIO
  - 集成 s6-overlay 管理多进程
- [ ] s6 服务定义
  - `/etc/s6-overlay/s6-rc.d/postgres/`
  - `/etc/s6-overlay/s6-rc.d/minio/`
- [ ] 启动脚本
  - PG 初始化（首次启动自动 initdb）
  - MinIO bucket 自动创建
  - 等待 PG ready 的 healthcheck
- [ ] GitHub Actions：多架构构建并推送
  - `linux/amd64` + `linux/arm64`
  - 推送到 Docker Hub + GHCR
- [ ] Healthcheck
  ```dockerfile
  HEALTHCHECK CMD pg_isready && wget -qO- http://localhost:9000/minio/health/live
  ```

### P1 — 易用性

- [ ] `README.md`
  - 快速开始（5 分钟跑起来）
  - 环境变量说明
  - 与 `hot_sync.sh` 配合使用说明
  - 已知限制（NIF 需要在目标架构编译）
- [ ] `docker-compose.yml` 示例
- [ ] `.env.example`

### P2 — 持续维护

- [ ] 每月自动 rebuild（GitHub Actions schedule）
- [ ] 版本矩阵：OTP 27 / 28
- [ ] Dependabot 或脚本跟踪 PG/MinIO 新版本

---

## 七、关键约束（执行者必读）

**1. NIF 不在基础镜像职责范围内**
基础镜像只提供运行时，NIF（`.so` 文件）由各项目的 deps 层负责，不内置。

**2. 不内置任何应用代码**
镜像里不应有 `mix.exs`、`beam` 应用文件，保持通用性。

**3. 多架构是强制要求**
必须同时提供 `amd64` 和 `arm64`，这是该镜像的核心价值之一。

**4. PG 数据目录可选挂载**
```bash
docker run -v /host/pgdata:/var/lib/pg ghcr.io/youfun/beam-devbox:otp28
```
不挂载时数据在容器内（测试用）。

---

## 八、参考资料

| 资源 | 说明 |
|------|------|
| [s6-overlay](https://github.com/just-containers/s6-overlay) | 容器多进程管理 |
| [hexpm/docker-elixir](https://github.com/hexpm/docker-elixir) | 官方 Elixir 镜像参考 |
| [minio/minio](https://hub.docker.com/r/minio/minio) | MinIO 官方镜像 |
| [postgres](https://hub.docker.com/_/postgres) | PostgreSQL 官方镜像 |
| hot_sync.sh | 本项目 `scripts/hot_sync.sh` |

---

## 九、验收标准

```bash
# 能跑起来
docker run -p 5432:5432 -p 9000:9000 ghcr.io/youfun/beam-devbox:otp28

# PG 可连接
psql -h localhost -U postgres -c "SELECT 1"

# MinIO 可访问
curl http://localhost:9000/minio/health/live

# 注入 .beam 后应用能跑
docker cp myapp_beams.tar.gz container:/app/lib/
docker exec container /app/bin/app start
```
