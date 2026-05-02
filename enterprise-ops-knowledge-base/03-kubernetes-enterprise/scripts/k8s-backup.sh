#!/bin/bash
#============================================
# Kubernetes 集群备份脚本
# 备份 etcd + 资源对象
#============================================
set -euo pipefail

BACKUP_DIR="/backup/kubernetes/$(date +%Y%m%d-%H%M%S)"
ETCD_ENDPOINTS="https://127.0.0.1:2379"
ETCD_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/server.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/server.key"

mkdir -p "$BACKUP_DIR"

echo "=== K8s 集群备份开始: $(date) ==="

# 1. etcd 快照备份
echo "[1/3] 备份 etcd..."
ETCDCTL_API=3 etcdctl snapshot save "$BACKUP_DIR/etcd-snapshot.db" \
    --endpoints="$ETCD_ENDPOINTS" \
    --cacert="$ETCD_CACERT" \
    --cert="$ETCD_CERT" \
    --key="$ETCD_KEY"

# 验证快照
ETCDCTL_API=3 etcdctl snapshot status "$BACKUP_DIR/etcd-snapshot.db" --write-table

# 2. 备份关键资源对象
echo "[2/3] 备份资源对象..."
for resource in namespaces deployments services configmaps secrets ingresses; do
    kubectl get "$resource" -A -o yaml > "$BACKUP_DIR/${resource}.yaml"
done

# 3. 备份 PKI 证书
echo "[3/3] 备份 PKI..."
cp -r /etc/kubernetes/pki "$BACKUP_DIR/pki"
cp /etc/kubernetes/admin.conf "$BACKUP_DIR/"

# 压缩
tar czf "$BACKUP_DIR.tar.gz" -C "$(dirname $BACKUP_DIR)" "$(basename $BACKUP_DIR)"
rm -rf "$BACKUP_DIR"

# 清理 30 天前的备份
find /backup/kubernetes -name "*.tar.gz" -mtime +30 -delete

echo "=== 备份完成: $BACKUP_DIR.tar.gz ==="
echo "大小: $(du -sh "$BACKUP_DIR.tar.gz" | awk '{print $1}')"
