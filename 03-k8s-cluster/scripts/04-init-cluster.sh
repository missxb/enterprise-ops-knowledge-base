#!/bin/bash
#============================================================================
# Kubernetes 高可用集群 - 集群初始化脚本
# 功能：使用 kubeadm 初始化 K8S 高可用集群
# 用法：./04-init-cluster.sh [init|join-master|join-worker]
#============================================================================

set -euo pipefail

# 配置
VIP="${VIP:-10.0.0.100}"
VIP_PORT="${VIP_PORT:-8443}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.96.0.0/12}"
K8S_VERSION="${K8S_VERSION:-1.28.0}"
IMAGE_REPO="${IMAGE_REPO:-registry.aliyuncs.com/google_containers}"
CERT_SANS="${CERT_SANS:-}"

MASTER_01="${MASTER_01:-10.0.0.11}"
MASTER_02="${MASTER_02:-10.0.0.12}"
MASTER_03="${MASTER_03:-10.0.0.13}"

LOG_FILE="/var/log/k8s-init-$(date +%Y%m%d_%H%M%S).log"

log() {
    local level=$1; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

#==================== 生成 kubeadm 配置 ====================
generate_kubeadm_config() {
    log "INFO" "生成 kubeadm 配置文件..."

    cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v${K8S_VERSION}
controlPlaneEndpoint: "${VIP}:${VIP_PORT}"
imageRepository: ${IMAGE_REPO}
networking:
  podSubnet: ${POD_CIDR}
  serviceSubnet: ${SERVICE_CIDR}
  dnsDomain: cluster.local
apiServer:
  certSANs:
    - "${VIP}"
    - "${MASTER_01}"
    - "${MASTER_02}"
    - "${MASTER_03}"
    - "k8s-master-01"
    - "k8s-master-02"
    - "k8s-master-03"
    - "k8s-vip"
    - "127.0.0.1"
  extraArgs:
    authorization-mode: "Node,RBAC"
    enable-admission-plugins: "NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota"
etcd:
  local:
    dataDir: /var/lib/etcd
controllerManager:
  extraArgs:
    bind-address: "0.0.0.0"
scheduler:
  extraArgs:
    bind-address: "0.0.0.0"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  taints:
    - effect: NoSchedule
      key: node-role.kubernetes.io/control-plane
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
EOF

    log "INFO" "配置文件已生成: /tmp/kubeadm-config.yaml"
}

#==================== 初始化第一个 Master ====================
init_first_master() {
    log "INFO" "========== 初始化第一个 Master 节点 =========="

    # 预拉取镜像
    log "INFO" "预拉取 K8S 镜像..."
    kubeadm config images pull --config /tmp/kubeadm-config.yaml
    log "INFO" "镜像拉取完成"

    # 初始化集群
    log "INFO" "初始化集群..."
    kubeadm init --config /tmp/kubeadm-config.yaml --upload-certs | tee /tmp/kubeadm-init.log

    # 配置 kubectl
    mkdir -p /root/.kube
    cp -f /etc/kubernetes/admin.conf /root/.kube/config
    chown $(id -u):$(id -g) /root/.kube/config

    log "INFO" "集群初始化完成"

    # 提取 join 命令
    local join_cmd=$(kubeadm token create --print-join-command)
    local cert_key=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)

    echo "$join_cmd --control-plane --certificate-key $cert_key" > /tmp/join-master-command.txt
    echo "$join_cmd" > /tmp/join-worker-command.txt

    log "INFO" "Master 加入命令已保存: /tmp/join-master-command.txt"
    log "INFO" "Worker 加入命令已保存: /tmp/join-worker-command.txt"
}

#==================== 加入其他 Master ====================
join_master() {
    log "INFO" "========== 加入 Master 节点 =========="

    if [ ! -f /tmp/join-master-command.txt ]; then
        log "ERROR" "未找到加入命令，请从第一个 Master 节点获取"
        exit 1
    fi

    local join_cmd=$(cat /tmp/join-master-command.txt)
    log "INFO" "执行加入命令..."

    eval "$join_cmd"

    # 配置 kubectl
    mkdir -p /root/.kube
    cp -f /etc/kubernetes/admin.conf /root/.kube/config
    chown $(id -u):$(id -g) /root/.kube/config

    log "INFO" "Master 节点加入成功"
}

#==================== 加入 Worker ====================
join_worker() {
    log "INFO" "========== 加入 Worker 节点 =========="

    if [ ! -f /tmp/join-worker-command.txt ]; then
        log "ERROR" "未找到加入命令，请从 Master 节点获取"
        exit 1
    fi

    local join_cmd=$(cat /tmp/join-worker-command.txt)
    log "INFO" "执行加入命令..."

    eval "$join_cmd"

    log "INFO" "Worker 节点加入成功"
}

#==================== 验证集群 ====================
verify_cluster() {
    log "INFO" "========== 验证集群状态 =========="

    # 节点状态
    log "INFO" "节点状态:"
    kubectl get nodes -o wide | tee -a "$LOG_FILE"

    # 系统组件
    log "INFO" "系统组件:"
    kubectl get pods -n kube-system | tee -a "$LOG_FILE"

    # etcd 集群
    log "INFO" "etcd 集群:"
    kubectl get pods -n kube-system -l component=etcd | tee -a "$LOG_FILE"

    # 集群信息
    log "INFO" "集群信息:"
    kubectl cluster-info | tee -a "$LOG_FILE"

    # 检查所有节点是否 Ready
    local not_ready=$(kubectl get nodes --no-headers | grep -v " Ready " | wc -l)
    if [ "$not_ready" -eq 0 ]; then
        log "INFO" "所有节点状态 Ready ✓"
    else
        log "WARN" "有 $not_ready 个节点未就绪"
    fi
}

#==================== 主函数 ====================
main() {
    local action="${1:-help}"

    mkdir -p "$(dirname "$LOG_FILE")"

    case "$action" in
        init)
            generate_kubeadm_config
            init_first_master
            verify_cluster
            ;;
        join-master)
            join_master
            ;;
        join-worker)
            join_worker
            ;;
        verify)
            verify_cluster
            ;;
        config)
            generate_kubeadm_config
            ;;
        *)
            echo "用法: $0 [init|join-master|join-worker|verify|config]"
            echo ""
            echo "  init        - 初始化第一个 Master 节点"
            echo "  join-master - 加入其他 Master 节点"
            echo "  join-worker - 加入 Worker 节点"
            echo "  verify      - 验证集群状态"
            echo "  config      - 生成配置文件"
            exit 1
            ;;
    esac
}

main "$@"
