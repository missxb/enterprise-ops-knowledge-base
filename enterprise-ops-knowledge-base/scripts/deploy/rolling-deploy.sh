#!/bin/bash
#============================================
# 滚动部署脚本 (K8s)
# 用法: ./rolling-deploy.sh <deployment> <image> <namespace>
#============================================
set -euo pipefail

DEPLOYMENT=${1:?"用法: $0 <deployment> <image> <namespace>"}
IMAGE=${2:?"请指定镜像"}
NAMESPACE=${3:-default}
TIMEOUT=300

echo "=== 滚动部署开始 ==="
echo "Deployment: $DEPLOYMENT"
echo "Image: $IMAGE"
echo "Namespace: $NAMESPACE"
echo "时间: $(date)"

# 更新镜像
kubectl set image deployment/"$DEPLOYMENT" "$DEPLOYMENT"="$IMAGE" -n "$NAMESPACE"

# 等待 rollout 完成
echo "等待部署完成..."
if kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout="${TIMEOUT}s"; then
    echo "✅ 部署成功"
    kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE"
else
    echo "❌ 部署失败，开始回滚"
    kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE"
    kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout="${TIMEOUT}s"
    echo "已回滚到上一版本"
    exit 1
fi

echo "=== 部署完成: $(date) ==="
