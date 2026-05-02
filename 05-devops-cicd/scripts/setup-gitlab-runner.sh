#!/bin/bash
#============================================================================
# GitLab Runner 安装与配置脚本
# 功能：安装 GitLab Runner、注册 Runner、配置并发构建
# 用法：./setup-gitlab-runner.sh [install|register|config|status]
#============================================================================

set -euo pipefail

# 配置
GITLAB_URL="${GITLAB_URL:-https://gitlab.example.com}"
REGISTRATION_TOKEN="${REGISTRATION_TOKEN:-}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-runner}"
RUNNER_TAGS="${RUNNER_TAGS:-docker,linux,production}"
RUNNER_EXECUTOR="${RUNNER_EXECUTOR:-docker}"
DOCKER_IMAGE="${DOCKER_IMAGE:-docker:24.0-dind}"
MAX_CONCURRENT="${MAX_CONCURRENT:-10}"
RUNNER_CONFIG="/etc/gitlab-runner/config.toml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*"; }

#==================== 安装 GitLab Runner ====================
do_install() {
    log "========== 安装 GitLab Runner =========="

    # 检查是否已安装
    if command -v gitlab-runner >/dev/null 2>&1; then
        local current_ver=$(gitlab-runner --version | head -1)
        warn "GitLab Runner 已安装: $current_ver"
        read -p "是否重新安装？(y/N): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 0
    fi

    # 添加 GitLab 官方仓库
    log "添加 GitLab Runner 仓库..."
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | bash

    # 安装
    log "安装 GitLab Runner..."
    yum install -y gitlab-runner

    # 验证安装
    local version=$(gitlab-runner --version | head -1)
    log "安装完成: $version"

    # 设置开机自启
    systemctl enable gitlab-runner
    systemctl start gitlab-runner
    log "GitLab Runner 服务已启动"
}

#==================== 注册 Runner ====================
do_register() {
    log "========== 注册 GitLab Runner =========="

    if [ -z "$REGISTRATION_TOKEN" ]; then
        error "请设置 REGISTRATION_TOKEN 环境变量"
        error "获取方式: GitLab → Admin → CI/CD → Runners → Registration token"
        exit 1
    fi

    # 注册共享 Runner
    gitlab-runner register \
        --non-interactive \
        --url "${GITLAB_URL}" \
        --registration-token "${REGISTRATION_TOKEN}" \
        --executor "${RUNNER_EXECUTOR}" \
        --name "${RUNNER_NAME}" \
        --tag-list "${RUNNER_TAGS}" \
        --run-untagged="true" \
        --locked="false" \
        --docker-image "${DOCKER_IMAGE}" \
        --docker-privileged="true" \
        --docker-volumes "/certs/client" \
        --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
        --cache-dir "/var/cache/gitlab-runner" \
        --builds-dir "/home/gitlab-runner/builds"

    if [ $? -eq 0 ]; then
        log "Runner 注册成功！"
        log "  名称: ${RUNNER_NAME}"
        log "  标签: ${RUNNER_TAGS}"
        log "  执行器: ${RUNNER_EXECUTOR}"
    else
        error "Runner 注册失败"
        exit 1
    fi
}

#==================== 配置优化 ====================
do_config() {
    log "========== 配置 Runner 优化 =========="

    # 备份原配置
    cp "$RUNNER_CONFIG" "${RUNNER_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

    # 生成优化配置
    cat > "$RUNNER_CONFIG" <<EOF
concurrent = ${MAX_CONCURRENT}
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "${RUNNER_NAME}"
  url = "${GITLAB_URL}"
  token = "$(gitlab-runner list 2>/dev/null | grep -oP 'Token=\K[^ ]+' | head -1 || echo 'YOUR_TOKEN')"
  executor = "${RUNNER_EXECUTOR}"
  [runners.cache]
    Type = "local"
    Path = "/var/cache/gitlab-runner"
    Shared = true
    [runners.cache.s3]
      ServerAddress = "minio.example.com"
      BucketName = "gitlab-runner-cache"
      Insecure = false
  [runners.docker]
    image = "${DOCKER_IMAGE}"
    privileged = true
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = ["/certs/client", "/var/run/docker.sock:/var/run/docker.sock", "/var/cache/gitlab-runner:/cache"]
    shm_size = 0
    network_mtu = 0
    # 安全配置
    pull_policy = ["if-not-present"]
    # 资源限制
    memory = "4g"
    memory_swap = "4g"
    cpus = "2"
    # DNS 配置
    dns = ["8.8.8.8", "114.114.114.114"]
EOF

    # 重启服务
    systemctl restart gitlab-runner
    log "配置已更新并重启服务"

    # 验证配置
    gitlab-runner verify
    log "Runner 验证通过"
}

#==================== 状态查看 ====================
do_status() {
    log "========== Runner 状态 =========="

    # 服务状态
    systemctl status gitlab-runner --no-pager

    echo ""
    log "已注册的 Runner:"
    gitlab-runner list 2>/dev/null || echo "无法获取 Runner 列表"

    echo ""
    log "Runner 验证:"
    gitlab-runner verify --delete 2>/dev/null || echo "验证失败"
}

#==================== 主函数 ====================
main() {
    local action="${1:-help}"

    case "$action" in
        install)
            do_install
            ;;
        register)
            do_register
            ;;
        config)
            do_config
            ;;
        status)
            do_status
            ;;
        *)
            echo "用法: $0 [install|register|config|status]"
            echo ""
            echo "  install  - 安装 GitLab Runner"
            echo "  register - 注册 Runner 到 GitLab"
            echo "  config   - 优化 Runner 配置"
            echo "  status   - 查看 Runner 状态"
            echo ""
            echo "环境变量:"
            echo "  GITLAB_URL         - GitLab 地址 (默认: https://gitlab.example.com)"
            echo "  REGISTRATION_TOKEN - Runner 注册 Token (必须)"
            echo "  RUNNER_NAME        - Runner 名称"
            echo "  RUNNER_TAGS        - Runner 标签 (逗号分隔)"
            echo "  MAX_CONCURRENT     - 最大并发数 (默认: 10)"
            exit 1
            ;;
    esac
}

main "$@"
