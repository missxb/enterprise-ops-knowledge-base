#!/bin/bash
#============================================================================
# 企业级监控系统 - 一键部署脚本
# 功能：部署 Prometheus + Grafana + Alertmanager 全套监控
# 用法：./deploy.sh [install|start|stop|restart|status|upgrade|backup|restore]
#============================================================================

set -euo pipefail

# 配置
DEPLOY_DIR="/opt/monitoring"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"
BACKUP_DIR="/data/backup/monitoring"
LOG_FILE="/var/log/monitoring-deploy-$(date +%Y%m%d_%H%M%S).log"

log() {
    local level=$1; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

#==================== 安装 ====================
do_install() {
    log "INFO" "========== 安装监控系统 =========="

    # 检查 Docker
    if ! command -v docker >/dev/null 2>&1; then
        log "ERROR" "Docker 未安装，请先安装 Docker"
        exit 1
    fi

    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log "ERROR" "Docker Compose 未安装"
        exit 1
    fi

    # 创建目录
    mkdir -p "${DEPLOY_DIR}"/{prometheus/{rules,targets},grafana/provisioning/{datasources,dashboards},alertmanager,exporters/blackbox-exporter}

    # 复制配置文件
    log "INFO" "复制配置文件..."
    cp -r ../prometheus/* "${DEPLOY_DIR}/prometheus/"
    cp -r ../grafana/* "${DEPLOY_DIR}/grafana/"
    cp -r ../alertmanager/* "${DEPLOY_DIR}/alertmanager/"
    cp -r ../exporters/* "${DEPLOY_DIR}/exporters/"
    cp ../docker-compose.yml "${DEPLOY_DIR}/"

    # 创建 Grafana 数据源配置
    cat > "${DEPLOY_DIR}/grafana/provisioning/datasources/prometheus.yml" <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false

  - name: Alertmanager
    type: alertmanager
    access: proxy
    url: http://alertmanager:9093
    editable: false
    jsonData:
      implementation: prometheus
EOF

    # 创建 Grafana Dashboard 配置
    cat > "${DEPLOY_DIR}/grafana/provisioning/dashboards/dashboards.yml" <<'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
      foldersFromFilesStructure: true
EOF

    # 创建节点配置
    cat > "${DEPLOY_DIR}/prometheus/targets/nodes.json" <<'EOF'
[
  {
    "targets": [
      "10.0.0.11:9100",
      "10.0.0.12:9100",
      "10.0.0.13:9100",
      "10.0.0.21:9100",
      "10.0.0.22:9100",
      "10.0.0.23:9100",
      "10.0.0.24:9100",
      "10.0.0.25:9100"
    ],
    "labels": {
      "env": "production",
      "team": "ops"
    }
  }
]
EOF

    # 创建 Blackbox Exporter 配置
    cat > "${DEPLOY_DIR}/exporters/blackbox-exporter/blackbox.yml" <<'EOF'
modules:
  http_2xx:
    prober: http
    timeout: 10s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 301, 302, 403]
      method: GET
      follow_redirects: true
      preferred_ip_protocol: "ip4"

  tcp_connect:
    prober: tcp
    timeout: 5s

  icmp:
    prober: icmp
    timeout: 5s
EOF

    log "INFO" "安装完成！配置文件位于: ${DEPLOY_DIR}"
    log "INFO" "请根据实际情况修改配置后执行: $0 start"
}

#==================== 启动 ====================
do_start() {
    log "INFO" "========== 启动监控系统 =========="

    cd "$DEPLOY_DIR"

    # 拉取镜像
    log "INFO" "拉取镜像..."
    docker compose pull 2>/dev/null || docker-compose pull

    # 启动服务
    log "INFO" "启动服务..."
    docker compose up -d 2>/dev/null || docker-compose up -d

    # 等待服务就绪
    log "INFO" "等待服务就绪..."
    sleep 10

    # 检查服务状态
    do_status

    log "INFO" "=========================================="
    log "INFO" "  监控系统已启动！"
    log "INFO" "  Prometheus:   http://localhost:9090"
    log "INFO" "  Grafana:      http://localhost:3000"
    log "INFO" "  Alertmanager: http://localhost:9093"
    log "INFO" "  Node Exporter: http://localhost:9100"
    log "INFO" "=========================================="
    log "INFO" "  Grafana 默认账号: admin / admin123456"
    log "INFO" "=========================================="
}

#==================== 停止 ====================
do_stop() {
    log "INFO" "停止监控系统..."
    cd "$DEPLOY_DIR"
    docker compose down 2>/dev/null || docker-compose down
    log "INFO" "监控系统已停止"
}

#==================== 状态 ====================
do_status() {
    log "INFO" "========== 服务状态 =========="
    cd "$DEPLOY_DIR"
    docker compose ps 2>/dev/null || docker-compose ps

    echo ""
    log "INFO" "========== 健康检查 =========="

    # Prometheus
    local prom_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy 2>/dev/null || echo "000")
    if [ "$prom_status" = "200" ]; then
        log "INFO" "  Prometheus: ✓ 正常"
    else
        log "WARN" "  Prometheus: ✗ 异常 (HTTP $prom_status)"
    fi

    # Grafana
    local grafana_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health 2>/dev/null || echo "000")
    if [ "$grafana_status" = "200" ]; then
        log "INFO" "  Grafana:    ✓ 正常"
    else
        log "WARN" "  Grafana:    ✗ 异常 (HTTP $grafana_status)"
    fi

    # Alertmanager
    local alert_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9093/-/healthy 2>/dev/null || echo "000")
    if [ "$alert_status" = "200" ]; then
        log "INFO" "  Alertmanager: ✓ 正常"
    else
        log "WARN" "  Alertmanager: ✗ 异常 (HTTP $alert_status)"
    fi
}

#==================== 备份 ====================
do_backup() {
    log "INFO" "========== 备份监控数据 =========="
    mkdir -p "$BACKUP_DIR"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/backup-${timestamp}"
    mkdir -p "$backup_path"

    # 备份 Prometheus 数据
    log "INFO" "备份 Prometheus 数据..."
    docker exec prometheus tar czf /tmp/prometheus-data.tar.gz -C / prometheus 2>/dev/null
    docker cp prometheus:/tmp/prometheus-data.tar.gz "${backup_path}/"

    # 备份 Grafana 数据
    log "INFO" "备份 Grafana 数据..."
    docker exec grafana tar czf /tmp/grafana-data.tar.gz -C / var/lib/grafana 2>/dev/null
    docker cp grafana:/tmp/grafana-data.tar.gz "${backup_path}/"

    # 备份配置文件
    log "INFO" "备份配置文件..."
    tar czf "${backup_path}/configs.tar.gz" -C "$DEPLOY_DIR" .

    local size=$(du -sh "$backup_path" | awk '{print $1}')
    log "INFO" "备份完成: $backup_path ($size)"
}

#==================== 主函数 ====================
main() {
    local action="${1:-help}"

    mkdir -p "$(dirname "$LOG_FILE")"

    case "$action" in
        install)
            do_install
            ;;
        start)
            do_start
            ;;
        stop)
            do_stop
            ;;
        restart)
            do_stop
            sleep 3
            do_start
            ;;
        status)
            do_status
            ;;
        backup)
            do_backup
            ;;
        *)
            echo "用法: $0 [install|start|stop|restart|status|backup]"
            echo ""
            echo "  install  - 安装监控系统"
            echo "  start    - 启动监控系统"
            echo "  stop     - 停止监控系统"
            echo "  restart  - 重启监控系统"
            echo "  status   - 查看服务状态"
            echo "  backup   - 备份监控数据"
            exit 1
            ;;
    esac
}

main "$@"
