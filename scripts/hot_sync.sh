#!/bin/bash
# hot_sync.sh - 热同步本地 BEAM 文件到运行中的容器
#
# 使用方法:
#   ./hot_sync.sh [应用名] [容器名]
#
# 环境变量:
#   APP_NAME    - 应用名称 (默认: myapp)
#   CONTAINER   - 容器名称 (默认: beam-devbox)
#   BUILD_ENV   - 构建环境 (默认: dev)
#   RSYNC_OPTS  - rsync 额外选项 (默认: -avz --delete)

set -e

# 配置
APP_NAME="${1:-${APP_NAME:-myapp}}"
CONTAINER="${2:-${CONTAINER:-beam-devbox}}"
BUILD_ENV="${BUILD_ENV:-dev}"
RSYNC_OPTS="${RSYNC_OPTS:--avz --delete}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查容器是否运行
check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        log_error "容器 '${CONTAINER}' 未运行"
        echo "请先启动容器: docker run -d --name ${CONTAINER} ghcr.io/youfun/beam-devbox:otp28"
        exit 1
    fi
    log_info "容器 '${CONTAINER}' 运行中"
}

# 本地编译
compile_local() {
    log_info "本地编译 ${APP_NAME}..."

    if [ ! -f "mix.exs" ]; then
        log_error "未找到 mix.exs，请确保在 Elixir 项目根目录运行"
        exit 1
    fi

    mix deps.get
    mix compile

    if [ $? -ne 0 ]; then
        log_error "编译失败"
        exit 1
    fi

    log_info "编译完成"
}

# 同步 .beam 文件到容器
sync_beams() {
    log_info "同步 .beam 文件到容器..."

    local beam_source="_build/${BUILD_ENV}/lib/${APP_NAME}/ebin/"
    local beam_dest="${CONTAINER}:/app/lib/${APP_NAME}/"

    if [ ! -d "${beam_source}" ]; then
        log_error "未找到 BEAM 文件目录: ${beam_source}"
        exit 1
    fi

    # 确保目标目录存在
    docker exec "${CONTAINER}" mkdir -p "/app/lib/${APP_NAME}"

    # 使用 rsync 通过 docker cp 的替代方法
    # 由于 docker cp 不支持 rsync 协议，我们使用 tar 流
    tar -czf - -C "${beam_source}" . | docker exec -i "${CONTAINER}" tar -xzf - -C "/app/lib/${APP_NAME}/"

    log_info "同步完成"
}

# 同步整个 release
sync_release() {
    log_info "同步 release 到容器..."

    local release_tar="_build/${BUILD_ENV}/${APP_NAME}-*.tar.gz"

    if ls ${release_tar} 1> /dev/null 2>&1; then
        local tar_file=$(ls -t ${release_tar} | head -n1)
        log_info "找到 release: ${tar_file}"

        docker cp "${tar_file}" "${CONTAINER}:/app/${APP_NAME}.tar.gz"
        docker exec "${CONTAINER}" bash -c "cd /app && tar -xzf ${APP_NAME}.tar.gz && rm ${APP_NAME}.tar.gz"

        log_info "Release 同步完成"
    else
        log_warn "未找到 release tar 包，跳过 release 同步"
    fi
}

# 热重载应用 (如果应用已在运行)
hot_reload() {
    log_info "尝试热重载应用..."

    # 检查应用是否已在运行
    if docker exec "${CONTAINER}" pgrep -f "/app/bin/${APP_NAME}" > /dev/null 2>&1; then
        log_info "应用正在运行，执行热重载..."

        # 尝试 graceful 重启
        docker exec "${CONTAINER}" "/app/bin/${APP_NAME}" restart || {
            log_warn "Graceful 重启失败，尝试 stop/start..."
            docker exec "${CONTAINER}" "/app/bin/${APP_NAME}" stop || true
            sleep 2
            docker exec "${CONTAINER}" "/app/bin/${APP_NAME}" start
        }
    else
        log_info "应用未运行，尝试启动..."
        docker exec "${CONTAINER}" "/app/bin/${APP_NAME}" start || {
            log_warn "启动失败，请检查应用配置"
        }
    fi
}

# 主函数
main() {
    echo "========================================"
    echo "       beam-devbox 热同步工具"
    echo "========================================"
    echo ""

    check_container
    compile_local
    sync_beams
    sync_release
    hot_reload

    echo ""
    log_info "热同步完成!"
    echo ""
    echo "容器状态:"
    docker ps --filter "name=${CONTAINER}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# 解析命令行参数
usage() {
    echo "用法: $0 [选项] [应用名] [容器名]"
    echo ""
    echo "选项:"
    echo "  -h, --help      显示帮助信息"
    echo "  -b, --build     仅编译，不同步"
    echo "  -s, --sync      仅同步，不编译"
    echo "  -n, --no-reload 不同步后不重载"
    echo ""
    echo "示例:"
    echo "  $0                          # 使用默认值"
    echo "  $0 myapp beam-devbox        # 指定应用和容器名"
    echo "  $0 -s                       # 仅同步"
    exit 0
}

# 解析参数
DO_COMPILE=true
DO_SYNC=true
DO_RELOAD=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -b|--build)
            DO_SYNC=false
            DO_RELOAD=false
            shift
            ;;
        -s|--sync)
            DO_COMPILE=false
            shift
            ;;
        -n|--no-reload)
            DO_RELOAD=false
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

# 重新设置位置参数
if [ $# -ge 1 ]; then
    APP_NAME="$1"
fi
if [ $# -ge 2 ]; then
    CONTAINER="$2"
fi

# 执行
if [ "$DO_COMPILE" = true ] && [ "$DO_SYNC" = true ] && [ "$DO_RELOAD" = true ]; then
    main
else
    check_container

    if [ "$DO_COMPILE" = true ]; then
        compile_local
    fi

    if [ "$DO_SYNC" = true ]; then
        sync_beams
        sync_release
    fi

    if [ "$DO_RELOAD" = true ]; then
        hot_reload
    fi
fi
