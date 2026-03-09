#!/bin/bash
# hot_sync.sh - 本地编译，远程部署，热同步到运行中的容器
#
# 核心场景：
#   1. 本地开发（利用本地 IDE、快速编译）
#   2. 部署到远程 VPS 测试（模拟公网访问、线上环境）
#   3. 热更新 BEAM 文件（无需重启容器）
#
# 使用方法:
#   ./hot_sync.sh [应用名] [目标]
#
# 目标可以是:
#   - 本地容器名: beam-devbox
#   - 远程服务器: user@vps.example.com
#   - 远程容器: user@vps.example.com:beam-devbox
#
# 环境变量:
#   APP_NAME       - 应用名称 (默认: myapp)
#   TARGET         - 部署目标 (默认: beam-devbox)
#   BUILD_ENV      - 构建环境 (默认: dev)
#   REMOTE_PATH    - 远程路径 (默认: /app)
#   IDENTITY_FILE  - SSH 私钥路径 (可选)
#
# 示例:
#   # 同步到本地容器
#   ./hot_sync.sh myapp beam-devbox
#
#   # 同步到远程服务器（直接运行）
#   ./hot_sync.sh myapp user@vps.example.com
#
#   # 同步到远程服务器的容器
#   ./hot_sync.sh myapp user@vps.example.com:beam-devbox
#
#   # 使用特定私钥
#   IDENTITY_FILE=~/.ssh/vps_key ./hot_sync.sh myapp user@vps.example.com

set -e

# =============================================================================
# 配置
# =============================================================================
APP_NAME="${1:-${APP_NAME:-myapp}}"
TARGET="${2:-${TARGET:-beam-devbox}}"
BUILD_ENV="${BUILD_ENV:-dev}"
REMOTE_PATH="${REMOTE_PATH:-/app}"
SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null}"

if [ -n "$IDENTITY_FILE" ]; then
    SSH_OPTS="$SSH_OPTS -i $IDENTITY_FILE"
fi

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# =============================================================================
# 解析目标
# =============================================================================
parse_target() {
    local target="$1"

    if [[ "$target" == *@* ]]; then
        # 远程目标 (user@host 或 user@host:container)
        REMOTE_HOST="${target%%:*}"
        if [[ "$target" == *:* ]]; then
            REMOTE_CONTAINER="${target##*:}"
            DEPLOY_MODE="remote_container"
        else
            REMOTE_CONTAINER=""
            DEPLOY_MODE="remote_direct"
        fi
    else
        # 本地容器
        REMOTE_HOST=""
        REMOTE_CONTAINER="$target"
        DEPLOY_MODE="local"
    fi
}

# =============================================================================
# 本地编译
# =============================================================================
compile_local() {
    log_info "本地编译 ${APP_NAME}..."

    if [ ! -f "mix.exs" ]; then
        log_error "未找到 mix.exs，请确保在 Elixir 项目根目录运行"
        exit 1
    fi

    MIX_ENV="$BUILD_ENV" mix deps.get
    MIX_ENV="$BUILD_ENV" mix compile

    if [ $? -ne 0 ]; then
        log_error "编译失败"
        exit 1
    fi

    log_success "编译完成"
}

# =============================================================================
# 构建 Release（用于远程部署）
# =============================================================================
build_release() {
    log_info "构建 release..."

    MIX_ENV="prod" mix deps.get --only prod
    MIX_ENV="prod" mix compile
    MIX_ENV="prod" mix assets.deploy 2>/dev/null || true
    MIX_ENV="prod" mix release

    if [ $? -ne 0 ]; then
        log_error "Release 构建失败"
        exit 1
    fi

    log_success "Release 构建完成"
}

# =============================================================================
# 同步到本地容器
# =============================================================================
sync_to_local_container() {
    local container="$1"

    log_info "同步到本地容器: $container"

    # 检查容器是否运行
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_error "容器 '$container' 未运行"
        echo "请先启动: docker run -d --name ${container} ghcr.io/youfun/beam-devbox:otp28"
        exit 1
    fi

    # 同步 .beam 文件
    local beam_source="_build/${BUILD_ENV}/lib/${APP_NAME}/ebin/"
    if [ -d "$beam_source" ]; then
        log_info "同步 .beam 文件..."
        docker exec "$container" mkdir -p "${REMOTE_PATH}/lib/${APP_NAME}"
        tar -czf - -C "$beam_source" . | docker exec -i "$container" tar -xzf - -C "${REMOTE_PATH}/lib/${APP_NAME}/"
    fi

    # 同步 release（如果存在）
    local release_tar="_build/prod/${APP_NAME}-*.tar.gz"
    if ls $release_tar 1>/dev/null 2>&1; then
        local tar_file=$(ls -t $release_tar | head -n1)
        log_info "同步 release: $(basename $tar_file)"
        docker cp "$tar_file" "${container}:${REMOTE_PATH}/${APP_NAME}.tar.gz"
        docker exec "$container" bash -c "cd ${REMOTE_PATH} && tar -xzf ${APP_NAME}.tar.gz && rm ${APP_NAME}.tar.gz"
    fi

    log_success "同步完成"
}

# =============================================================================
# 同步到远程服务器（直接运行）
# =============================================================================
sync_to_remote_direct() {
    local host="$1"

    log_info "部署到远程服务器: $host"

    # 检查 SSH 连接
    if ! ssh $SSH_OPTS "$host" "echo OK" >/dev/null 2>&1; then
        log_error "无法连接到 $host"
        echo "请确保:"
        echo "  1. SSH 密钥已添加到远程服务器"
        echo "  2. 服务器地址正确"
        exit 1
    fi

    # 检查远程是否有 beam-devbox
    if ! ssh $SSH_OPTS "$host" "which erl" >/dev/null 2>&1; then
        log_warn "远程服务器没有 Erlang/OTP，尝试使用 Docker..."

        # 检查远程 Docker
        if ! ssh $SSH_OPTS "$host" "docker ps" >/dev/null 2>&1; then
            log_error "远程服务器既没有 Erlang 也没有 Docker"
            exit 1
        fi

        # 在远程启动容器
        log_info "在远程启动 beam-devbox 容器..."
        ssh $SSH_OPTS "$host" "docker run -d --name ${APP_NAME}-dev -p 4000:4000 -p 5432:5432 -p 9000:9000 ghcr.io/youfun/beam-devbox:otp28 2>/dev/null || docker start ${APP_NAME}-dev 2>/dev/null || true"

        # 递归调用，改为容器模式
        REMOTE_CONTAINER="${APP_NAME}-dev"
        sync_to_remote_container "$host" "$REMOTE_CONTAINER"
        return
    fi

    # 直接同步 release 到远程
    local release_tar="_build/prod/${APP_NAME}-*.tar.gz"
    if ls $release_tar 1>/dev/null 2>&1; then
        local tar_file=$(ls -t $release_tar | head -n1)
        log_info "上传 release 到远程..."

        # 创建远程目录
        ssh $SSH_OPTS "$host" "mkdir -p ${REMOTE_PATH}"

        # 上传并解压
        scp $SSH_OPTS "$tar_file" "$host:${REMOTE_PATH}/${APP_NAME}.tar.gz"
        ssh $SSH_OPTS "$host" "cd ${REMOTE_PATH} && tar -xzf ${APP_NAME}.tar.gz && rm ${APP_NAME}.tar.gz"

        log_success "部署完成"

        # 重启远程服务
        log_info "重启远程服务..."
        ssh $SSH_OPTS "$host" "cd ${REMOTE_PATH} && bin/${APP_NAME} restart 2>/dev/null || bin/${APP_NAME} start"
    else
        log_error "未找到 release 文件，请先运行: mix release"
        exit 1
    fi
}

# =============================================================================
# 同步到远程容器
# =============================================================================
sync_to_remote_container() {
    local host="$1"
    local container="$2"

    log_info "部署到远程容器: $host:$container"

    # 检查远程容器
    if ! ssh $SSH_OPTS "$host" "docker ps --format '{{.Names}}' | grep -q '^${container}$'"; then
        log_warn "远程容器未运行，尝试启动..."
        ssh $SSH_OPTS "$host" "docker run -d --name ${container} -p 4000:4000 -p 5432:5432 -p 9000:9000 ghcr.io/youfun/beam-devbox:otp28 2>/dev/null || docker start ${container} 2>/dev/null || true"
        sleep 5
    fi

    # 同步 .beam 文件（开发模式）
    local beam_source="_build/${BUILD_ENV}/lib/${APP_NAME}/ebin/"
    if [ "$BUILD_ENV" = "dev" ] && [ -d "$beam_source" ]; then
        log_info "同步 .beam 文件到远程容器..."

        # 创建 tar 并上传到远程，再导入容器
        tar -czf "/tmp/${APP_NAME}-beams.tar.gz" -C "$beam_source" .
        scp $SSH_OPTS "/tmp/${APP_NAME}-beams.tar.gz" "$host:/tmp/"
        ssh $SSH_OPTS "$host" "docker exec ${container} mkdir -p ${REMOTE_PATH}/lib/${APP_NAME} && cat /tmp/${APP_NAME}-beams.tar.gz | docker exec -i ${container} tar -xzf - -C ${REMOTE_PATH}/lib/${APP_NAME}/"
        rm -f "/tmp/${APP_NAME}-beams.tar.gz"

        log_success "热同步完成"
    fi

    # 同步 release（生产模式）
    local release_tar="_build/prod/${APP_NAME}-*.tar.gz"
    if ls $release_tar 1>/dev/null 2>&1; then
        local tar_file=$(ls -t $release_tar | head -n1)
        log_info "同步 release 到远程容器..."

        scp $SSH_OPTS "$tar_file" "$host:/tmp/${APP_NAME}.tar.gz"
        ssh $SSH_OPTS "$host" "docker cp /tmp/${APP_NAME}.tar.gz ${container}:${REMOTE_PATH}/ && docker exec ${container} bash -c 'cd ${REMOTE_PATH} && tar -xzf ${APP_NAME}.tar.gz && rm ${APP_NAME}.tar.gz'"

        # 重启远程容器中的应用
        log_info "重启远程应用..."
        ssh $SSH_OPTS "$host" "docker exec ${container} bash -c '${REMOTE_PATH}/bin/${APP_NAME} restart 2>/dev/null || ${REMOTE_PATH}/bin/${APP_NAME} start'"

        log_success "Release 部署完成"
    fi
}

# =============================================================================
# 显示状态
# =============================================================================
show_status() {
    log_info "部署状态:"
    echo ""

    case "$DEPLOY_MODE" in
        local)
            docker ps --filter "name=$REMOTE_CONTAINER" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            ;;
        remote_direct)
            ssh $SSH_OPTS "$REMOTE_HOST" "ps aux | grep beam.smp | grep -v grep || echo 'BEAM not running'"
            ;;
        remote_container)
            ssh $SSH_OPTS "$REMOTE_HOST" "docker ps --filter name=$REMOTE_CONTAINER --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
            ;;
    esac
}

# =============================================================================
# 使用说明
# =============================================================================
usage() {
    cat << 'EOF'
hot_sync.sh - 本地编译，远程部署，热同步

使用方法:
  ./hot_sync.sh [应用名] [目标]

目标格式:
  本地容器:  beam-devbox
  远程主机:  user@vps.example.com
  远程容器:  user@vps.example.com:beam-devbox

示例:
  # 本地开发热同步
  ./hot_sync.sh myapp beam-devbox

  # 部署到远程 VPS 测试
  ./hot_sync.sh myapp user@vps.example.com

  # 部署到远程的特定容器
  ./hot_sync.sh myapp user@vps.example.com:myapp-dev

  # 使用特定 SSH 密钥
  IDENTITY_FILE=~/.ssh/vps ./hot_sync.sh myapp user@vps.example.com

环境变量:
  APP_NAME       - 应用名称 (默认: myapp)
  BUILD_ENV      - 构建环境: dev|prod (默认: dev)
  REMOTE_PATH    - 远程部署路径 (默认: /app)
  IDENTITY_FILE  - SSH 私钥路径

EOF
    exit 0
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    echo "========================================"
    echo "       beam-devbox 热同步工具"
    echo "========================================"
    echo ""

    # 解析参数
    parse_target "$TARGET"

    log_info "应用: $APP_NAME"
    log_info "目标: $TARGET"
    log_info "模式: $DEPLOY_MODE"
    echo ""

    # 编译
    if [ "$BUILD_ENV" = "prod" ]; then
        build_release
    else
        compile_local
    fi

    # 部署
    case "$DEPLOY_MODE" in
        local)
            sync_to_local_container "$REMOTE_CONTAINER"
            ;;
        remote_direct)
            sync_to_remote_direct "$REMOTE_HOST"
            ;;
        remote_container)
            sync_to_remote_container "$REMOTE_HOST" "$REMOTE_CONTAINER"
            ;;
    esac

    echo ""
    show_status
    echo ""
    log_success "完成!"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -r|--release)
            BUILD_ENV="prod"
            shift
            ;;
        -d|--dev)
            BUILD_ENV="dev"
            shift
            ;;
        -*)
            log_error "未知选项: $1"
            usage
            ;;
        *)
            break
            ;;
    esac
done

# 设置位置参数
if [ $# -ge 1 ]; then
    APP_NAME="$1"
fi
if [ $# -ge 2 ]; then
    TARGET="$2"
fi

# 执行
main
