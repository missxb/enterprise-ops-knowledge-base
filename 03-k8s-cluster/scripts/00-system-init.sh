#!/bin/bash
#============================================================================
# Kubernetes 高可用集群 - 系统初始化脚本
# 功能：CentOS 7.9 系统基础配置，为 K8S 部署做准备
# 用法：./00-system-init.sh [--all|--master|--worker]
#============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*"; }

#==================== 基础系统配置 ====================
configure_system() {
    log "========== 基础系统配置 =========="

    # 设置主机名
    local hostname="${1:-$(hostname)}"
    hostnamectl set-hostname "$hostname"
    log "主机名设置为: $hostname"

    # 配置 hosts
    cat >> /etc/hosts <<'EOF'
# K8S Cluster Nodes
10.0.0.11  k8s-master-01
10.0.0.12  k8s-master-02
10.0.0.13  k8s-master-03
10.0.0.21  k8s-worker-01
10.0.0.22  k8s-worker-02
10.0.0.23  k8s-worker-03
10.0.0.24  k8s-worker-04
10.0.0.25  k8s-worker-05
10.0.0.100 k8s-vip
EOF
    log "hosts 文件已配置"

    # 关闭 SELinux
    if getenforce | grep -q "Enforcing"; then
        setenforce 0
        sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
        log "SELinux 已关闭"
    else
        log "SELinux 已处于关闭状态"
    fi

    # 关闭防火墙（生产环境建议配置精确规则）
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    log "防火墙已关闭"

    # 关闭 swap
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    log "Swap 已关闭"

    # 配置时区和时间同步
    timedatectl set-timezone Asia/Shanghai
    yum install -y chrony >/dev/null 2>&1
    systemctl enable chronyd
    systemctl start chronyd
    log "时间同步已配置 (Asia/Shanghai)"

    # 配置系统参数
    cat > /etc/sysctl.d/k8s.conf <<'EOF'
# Kubernetes 系统参数
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
net.ipv6.conf.all.forwarding        = 1

# 网络优化
net.core.somaxconn                  = 32768
net.ipv4.tcp_max_syn_backlog        = 8096
net.core.netdev_max_backlog         = 16384
net.ipv4.tcp_keepalive_time         = 600
net.ipv4.tcp_keepalive_intvl        = 30
net.ipv4.tcp_keepalive_probes       = 10

# 文件描述符
fs.file-max                         = 1048576
fs.inotify.max_user_watches         = 1048576
fs.inotify.max_user_instances       = 8192

# 内存
vm.swappiness                       = 0
vm.overcommit_memory                = 1
vm.panic_on_oom                     = 0

# 连接跟踪
net.netfilter.nf_conntrack_max      = 131072
net.nf_conntrack_max                = 131072
EOF

    # 加载内核模块
    cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
EOF

    modprobe overlay
    modprobe br_netfilter
    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh
    modprobe nf_conntrack

    sysctl --system >/dev/null 2>&1
    log "系统参数已配置"

    # 配置文件描述符限制
    cat > /etc/security/limits.d/k8s.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65536
* hard nproc 65536
* soft memlock unlimited
* hard memlock unlimited
EOF
    log "文件描述符限制已配置"
}

#==================== 安装基础软件 ====================
install_base_packages() {
    log "========== 安装基础软件 =========="

    # 配置阿里云 YUM 源
    mkdir -p /etc/yum.repos.d/backup
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true

    cat > /etc/yum.repos.d/CentOS-Base.repo <<'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=https://mirrors.aliyun.com/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-$releasever - Updates
baseurl=https://mirrors.aliyun.com/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-$releasever - Extras
baseurl=https://mirrors.aliyun.com/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7
EOF

    # 安装 EPEL
    yum install -y epel-release >/dev/null 2>&1

    # 安装基础工具
    yum install -y \
        wget curl vim net-tools bind-utils \
        tree htop iotop iftop sysstat \
        yum-utils device-mapper-persistent-data \
        lvm2 ipvsadm ipset jq bash-completion \
        lrzsz unzip git >/dev/null 2>&1

    log "基础软件安装完成"
}

#==================== 配置 SSH 免密 ====================
configure_ssh() {
    log "========== 配置 SSH 免密登录 =========="

    if [ ! -f /root/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
        log "SSH密钥已生成"
    else
        log "SSH密钥已存在"
    fi

    # 将公钥添加到 authorized_keys
    cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    log "SSH 免密配置完成"
    log "请将以下公钥分发到所有节点:"
    cat /root/.ssh/id_rsa.pub
}

#==================== 配置日志轮转 ====================
configure_logrotate() {
    log "========== 配置日志轮转 =========="

    cat > /etc/logrotate.d/k8s <<'EOF'
/var/log/pods/*/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
    maxsize 100M
}
EOF
    log "K8S日志轮转已配置"
}

#==================== 主函数 ====================
main() {
    local role="${1:---all}"

    echo ""
    echo "============================================"
    echo "  Kubernetes 高可用集群 - 系统初始化"
    echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  角色: $role"
    echo "============================================"
    echo ""

    configure_system
    install_base_packages
    configure_ssh
    configure_logrotate

    echo ""
    echo "============================================"
    echo "  系统初始化完成！"
    echo "  请重启系统以确保所有配置生效"
    echo "============================================"
}

main "$@"
