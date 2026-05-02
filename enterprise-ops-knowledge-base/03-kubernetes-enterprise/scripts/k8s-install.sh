#!/bin/bash
#============================================
# Kubernetes 集群安装脚本 (kubeadm)
# 支持 CentOS 7/8, Ubuntu 20.04/22.04
#============================================
set -euo pipefail

K8S_VERSION="1.29"
POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
MASTER_IPS=()
WORKER_IPS=()
VIP=""

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# 系统前置配置
prepare_system() {
    log "配置系统基础环境..."
    
    # 关闭 swap
    swapoff -a
    sed -i '/swap/d' /etc/fstab
    
    # 加载内核模块
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    modprobe overlay
    modprobe br_netfilter
    
    # 内核参数
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
EOF
    sysctl --system
    
    # 关闭 SELinux
    setenforce 0 || true
    sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config || true
    
    # 关闭防火墙
    systemctl disable firewalld 2>/dev/null || true
    systemctl stop firewalld 2>/dev/null || true
}

# 安装 containerd
install_containerd() {
    log "安装 containerd..."
    yum install -y yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y containerd.io
    
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl enable containerd
    systemctl restart containerd
}

# 安装 kubeadm/kubelet/kubectl
install_kubeadm() {
    log "安装 kubeadm/kubelet/kubectl..."
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/repodata/repomd.xml.key
EOF
    yum install -y kubelet kubeadm kubectl
    systemctl enable kubelet
}

# 初始化 Master
init_master() {
    log "初始化 Master 节点..."
    kubeadm init \
        --pod-network-cidr="$POD_CIDR" \
        --service-network-cidr="$SERVICE_CIDR" \
        --upload-certs \
        --control-plane-endpoint="$VIP" \
        | tee /tmp/kubeadm-init.log
    
    # 配置 kubectl
    mkdir -p $HOME/.kube
    cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    
    # 安装 CNI (Calico)
    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    
    # 安装 Metrics Server
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    log "Master 初始化完成"
    kubeadm token create --print-join-command > /tmp/kubeadm-join.sh
}

# 主流程
main() {
    log "=== Kubernetes 集群安装开始 ==="
    prepare_system
    install_containerd
    install_kubeadm
    init_master
    log "=== 安装完成 ==="
    log "Join 命令保存在: /tmp/kubeadm-join.sh"
}

main "$@"
