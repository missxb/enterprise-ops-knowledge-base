#!/bin/bash
#============================================================================
# Kubernetes 高可用集群 - etcd 备份与恢复脚本
# 功能：etcd 集群备份、恢复、定时备份管理
# 用法：./07-etcd-backup.sh [backup|restore|list|verify|cleanup]
#============================================================================

set -euo pipefail

# etcd 配置
ETCD_ENDPOINTS="${ETCD_ENDPOINTS:-https://127.0.0.1:2379}"
ETCD_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/server.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/server.key"
ETCD_DATA_DIR="/var/lib/etcd"

# 备份配置
BACKUP_DIR="/data/backup/etcd"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_PREFIX="etcd-snapshot"
LOG_FILE="/var/log/etcd-backup-$(date +%Y%m%d_%H%M%S).log"

log() {
    local level=$1; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

#==================== 备份操作 ====================
do_backup() {
    log "INFO" "========== 开始 etcd 备份 =========="

    mkdir -p "$BACKUP_DIR"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/${BACKUP_PREFIX}-${timestamp}.db"
    local backup_meta="${BACKUP_DIR}/${BACKUP_PREFIX}-${timestamp}.meta"

    # 检查 etcd 连接
    if ! etcdctl --endpoints="$ETCD_ENDPOINTS" \
        --cacert="$ETCD_CACERT" \
        --cert="$ETCD_CERT" \
        --key="$ETCD_KEY" \
        endpoint health >/dev/null 2>&1; then
        log "ERROR" "etcd 连接失败"
        return 1
    fi

    # 执行备份
    log "INFO" "备份文件: $backup_file"
    etcdctl snapshot save "$backup_file" \
        --endpoints="$ETCD_ENDPOINTS" \
        --cacert="$ETCD_CACERT" \
        --cert="$ETCD_CERT" \
        --key="$ETCD_KEY"

    if [ $? -eq 0 ]; then
        local size=$(du -sh "$backup_file" | awk '{print $1}')
        log "INFO" "备份成功: $backup_file ($size)"

        # 保存元数据
        cat > "$backup_meta" <<EOF
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份文件: $backup_file
文件大小: $size
etcd版本: $(etcdctl version | head -1)
集群ID: $(etcdctl --endpoints="$ETCD_ENDPOINTS" \
    --cacert="$ETCD_CACERT" --cert="$ETCD_CERT" --key="$ETCD_KEY" \
    endpoint status --write-out=json 2>/dev/null | jq -r '.[0].Status.header.cluster_id' 2>/dev/null || echo "N/A")
成员ID: $(etcdctl --endpoints="$ETCD_ENDPOINTS" \
    --cacert="$ETCD_CACERT" --cert="$ETCD_CERT" --key="$ETCD_KEY" \
    endpoint status --write-out=json 2>/dev/null | jq -r '.[0].Status.header.member_id' 2>/dev/null || echo "N/A")
EOF
        log "INFO" "元数据已保存: $backup_meta"

        # 验证备份
        verify_backup "$backup_file"
    else
        log "ERROR" "备份失败"
        return 1
    fi
}

#==================== 验证备份 ====================
verify_backup() {
    local backup_file="${1:-}"

    if [ -z "$backup_file" ]; then
        # 获取最新备份
        backup_file=$(ls -t "${BACKUP_DIR}/${BACKUP_PREFIX}"-*.db 2>/dev/null | head -1)
    fi

    if [ ! -f "$backup_file" ]; then
        log "ERROR" "备份文件不存在: $backup_file"
        return 1
    fi

    log "INFO" "验证备份文件: $backup_file"

    local status=$(etcdctl snapshot status "$backup_file" --write-out=json 2>/dev/null)
    if [ $? -eq 0 ]; then
        local hash=$(echo "$status" | jq -r '.hash')
        local revision=$(echo "$status" | jq -r '.revision')
        local total_key=$(echo "$status" | jq -r '.totalKey')
        local total_size=$(echo "$status" | jq -r '.totalSize')

        log "INFO" "  备份验证通过 ✓"
        log "INFO" "  Hash: $hash"
        log "INFO" "  Revision: $revision"
        log "INFO" "  Key总数: $total_key"
        log "INFO" "  总大小: $total_size bytes"
    else
        log "ERROR" "  备份验证失败 ✗"
        return 1
    fi
}

#==================== 恢复操作 ====================
do_restore() {
    local backup_file="${1:-}"

    if [ -z "$backup_file" ]; then
        backup_file=$(ls -t "${BACKUP_DIR}/${BACKUP_PREFIX}"-*.db 2>/dev/null | head -1)
    fi

    if [ ! -f "$backup_file" ]; then
        log "ERROR" "备份文件不存在"
        exit 1
    fi

    log "WARN" "=========================================="
    log "WARN" "  警告：此操作将覆盖当前 etcd 数据！"
    log "WARN" "  备份文件: $backup_file"
    log "WARN" "=========================================="

    read -p "确认执行恢复操作？(输入 YES): " confirm
    if [ "$confirm" != "YES" ]; then
        log "INFO" "恢复操作已取消"
        return 0
    fi

    log "INFO" "========== 开始 etcd 恢复 =========="

    # 1. 停止所有 Master 节点的 etcd 和 API Server
    log "INFO" "步骤1: 停止 etcd 和相关服务..."
    systemctl stop etcd
    systemctl stop kubelet

    # 2. 备份当前数据
    log "INFO" "步骤2: 备份当前数据..."
    if [ -d "$ETCD_DATA_DIR" ]; then
        mv "${ETCD_DATA_DIR}" "${ETCD_DATA_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
        log "INFO" "  当前数据已备份"
    fi

    # 3. 执行恢复
    log "INFO" "步骤3: 执行恢复..."
    etcdctl snapshot restore "$backup_file" \
        --data-dir="$ETCD_DATA_DIR" \
        --name="etcd-$(hostname)" \
        --initial-cluster="etcd-master-01=https://${MASTER_01}:2380,etcd-master-02=https://${MASTER_02}:2380,etcd-master-03=https://${MASTER_03}:2380" \
        --initial-advertise-peer-urls="https://$(hostname -I | awk '{print $1}'):2380" \
        --initial-cluster-token="etcd-cluster-1"

    # 4. 修复权限
    log "INFO" "步骤4: 修复文件权限..."
    chown -R etcd:etcd "$ETCD_DATA_DIR"

    # 5. 启动服务
    log "INFO" "步骤5: 启动服务..."
    systemctl start etcd
    systemctl start kubelet

    # 6. 验证
    sleep 10
    if etcdctl --endpoints="$ETCD_ENDPOINTS" \
        --cacert="$ETCD_CACERT" --cert="$ETCD_CERT" --key="$ETCD_KEY" \
        endpoint health >/dev/null 2>&1; then
        log "INFO" "  etcd 恢复成功 ✓"
    else
        log "ERROR" "  etcd 恢复后健康检查失败"
        return 1
    fi
}

#==================== 列出备份 ====================
do_list() {
    log "INFO" "========== 备份列表 =========="

    if [ ! -d "$BACKUP_DIR" ]; then
        log "WARN" "备份目录不存在: $BACKUP_DIR"
        return 0
    fi

    local count=0
    for f in "${BACKUP_DIR}/${BACKUP_PREFIX}"-*.db; do
        if [ -f "$f" ]; then
            local size=$(du -sh "$f" | awk '{print $1}')
            local date=$(stat -c %y "$f" 2>/dev/null | cut -d. -f1)
            log "INFO" "  $(basename $f)  $size  $date"
            count=$((count+1))
        fi
    done

    log "INFO" "共 $count 个备份"
    log "INFO" "备份目录: $BACKUP_DIR"
    log "INFO" "保留策略: ${BACKUP_RETENTION_DAYS}天"
}

#==================== 清理旧备份 ====================
do_cleanup() {
    log "INFO" "========== 清理旧备份 =========="

    local deleted=0
    find "$BACKUP_DIR" -name "${BACKUP_PREFIX}-*.db" -mtime "+${BACKUP_RETENTION_DAYS}" | while read f; do
        log "INFO" "删除: $(basename $f)"
        rm -f "$f" "${f%.db}.meta"
        deleted=$((deleted+1))
    done

    log "INFO" "清理完成，删除 $deleted 个过期备份"
}

#==================== 配置定时备份 ====================
setup_cron() {
    log "INFO" "========== 配置定时备份 =========="

    local cron_job="0 2 * * * /bin/bash $(realpath $0) backup >> /var/log/etcd-backup-cron.log 2>&1"

    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -q "etcd-backup"; then
        log "INFO" "定时备份已存在"
    else
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log "INFO" "定时备份已配置: 每天凌晨2点执行"
    fi

    # 配置日志轮转
    cat > /etc/logrotate.d/etcd-backup <<'EOF'
/var/log/etcd-backup*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
}
EOF
    log "INFO" "日志轮转已配置"
}

#==================== 主函数 ====================
main() {
    local action="${1:-help}"

    mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

    case "$action" in
        backup)
            do_backup
            ;;
        restore)
            do_restore "${2:-}"
            ;;
        verify)
            verify_backup "${2:-}"
            ;;
        list)
            do_list
            ;;
        cleanup)
            do_cleanup
            ;;
        cron)
            setup_cron
            ;;
        *)
            echo "用法: $0 [backup|restore|verify|list|cleanup|cron]"
            echo ""
            echo "  backup           - 执行一次备份"
            echo "  restore [file]   - 从备份恢复"
            echo "  verify [file]    - 验证备份文件"
            echo "  list             - 列出所有备份"
            echo "  cleanup          - 清理过期备份"
            echo "  cron             - 配置定时备份"
            exit 1
            ;;
    esac
}

main "$@"
