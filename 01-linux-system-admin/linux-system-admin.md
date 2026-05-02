# Linux系统管理与优化完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. 环境准备与依赖说明](#2-环境准备与依赖说明)
- [3. 系统初始化](#3-系统初始化)
- [4. 内核参数优化](#4-内核参数优化)
- [5. 磁盘IO与存储管理](#5-磁盘io与存储管理)
- [6. systemd服务管理](#6-systemd服务管理)
- [7. 网络配置](#7-网络配置)
- [8. 性能分析工具链](#8-性能分析工具链)
- [9. 故障排查手册](#9-故障排查手册)
- [10. 安全加固](#10-安全加固)
- [11. 运维手册](#11-运维手册)
- [12. 最佳实践与注意事项](#12-最佳实践与注意事项)

---

## 1. 项目背景与架构设计

### 1.1 为什么需要系统级优化

在企业生产环境中，Linux服务器是所有上层应用的基石。未经优化的默认配置会导致：
- 内核参数不匹配高并发场景，导致连接数受限、文件描述符耗尽
- 磁盘IO调度策略不当，造成数据库等IO密集型应用性能瓶颈
- 安全配置薄弱，面临未授权访问、暴力破解等风险
- 缺乏系统级监控和审计，故障定位困难

### 1.2 整体架构

```
┌─────────────────────────────────────────────────────┐
│                    应用层                             │
│   Java / Python / Go / Node.js / PHP                │
├─────────────────────────────────────────────────────┤
│                   中间件层                            │
│   Nginx / Tomcat / Redis / MySQL / RabbitMQ         │
├─────────────────────────────────────────────────────┤
│                  容器/虚拟化层                        │
│   Docker / K8s / KVM                                │
├─────────────────────────────────────────────────────┤
│                   系统层（本手册）                     │
│   Kernel / systemd / Network / Storage / Security   │
├─────────────────────────────────────────────────────┤
│                   硬件层                             │
│   CPU / Memory / Disk / NIC / RAID Controller       │
└─────────────────────────────────────────────────────┘
```

### 1.3 适用范围

| 发行版 | 版本 | 支持状态 |
|--------|------|---------|
| CentOS | 7.x | ✅ 完全支持 |
| CentOS | 8.x (Stream) | ✅ 完全支持 |
| Ubuntu | 20.04 LTS | ✅ 完全支持 |
| Ubuntu | 22.04 LTS | ✅ 完全支持 |
| Rocky Linux | 8.x / 9.x | ✅ 完全支持 |
| Debian | 11 / 12 | ✅ 部分支持 |

---

## 2. 环境准备与依赖说明

### 2.1 硬件要求

| 角色 | CPU | 内存 | 磁盘 | 网络 |
|------|-----|------|------|------|
| 基础服务器 | 2核+ | 4GB+ | 50GB+ SSD | 千兆网卡 |
| 数据库服务器 | 8核+ | 32GB+ | 500GB+ SSD (RAID10) | 万兆网卡 |
| 应用服务器 | 4核+ | 16GB+ | 100GB+ SSD | 千兆/万兆 |
| 监控/日志服务器 | 4核+ | 16GB+ | 1TB+ HDD/SSD | 千兆网卡 |

### 2.2 网络规划模板

```bash
# 企业标准网络规划示例
# 管理网络：10.10.1.0/24     - SSH、监控、管理流量
# 业务网络：10.10.2.0/24     - 应用对外服务
# 存储网络：10.10.3.0/24     - NFS、Ceph、数据库复制
# 心跳网络：10.10.4.0/24     - 集群心跳（可选bond）

# 主机命名规范
# {环境}-{角色}-{区域}-{序号}
# 示例：prod-web-bj-01, staging-db-sh-02
```

---

## 3. 系统初始化

### 3.1 CentOS 7/8 初始化脚本

```bash
#!/bin/bash
# centos-init.sh - CentOS 7/8 系统初始化脚本
# 用法: bash centos-init.sh

set -euo pipefail

echo "========== CentOS 系统初始化开始 =========="

# ---- 1. 设置主机名 ----
hostnamectl set-hostname prod-server-01

# ---- 2. 关闭SELinux ----
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
setenforce 0 || true

# ---- 3. 关闭防火墙（生产环境建议配置iptables/nftables） ----
systemctl stop firewalld
systemctl disable firewalld

# ---- 4. 配置时区和NTP ----
timedatectl set-timezone Asia/Shanghai
# CentOS 7
if command -v yum &>/dev/null && [ "$(rpm -E %{rhel})" == "7" ]; then
    yum install -y chrony
    systemctl enable chronyd
    systemctl start chronyd
fi
# CentOS 8 / Rocky 8+
if command -v dnf &>/dev/null; then
    dnf install -y chrony
    systemctl enable chronyd
    systemctl start chronyd
fi

# ---- 5. 配置阿里云YUM源 ----
# CentOS 7
if [ "$(rpm -E %{rhel})" == "7" ]; then
    mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup 2>/dev/null || true
    curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
    yum clean all && yum makecache
fi

# ---- 6. 安装基础软件包 ----
yum install -y \
    vim wget curl net-tools bind-utils tree htop iotop \
    sysstat dstat strace lsof tcpdump nmap \
    gcc gcc-c++ make cmake \
    openssl-devel readline-devel zlib-devel \
    bash-completion lrzsz unzip zip \
    lvm2 mdadm

# ---- 7. 配置系统语言 ----
localectl set-locale LANG=en_US.UTF-8

# ---- 8. 关闭不需要的服务 ----
for svc in postfix avahi-daemon cups bluetooth; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done

# ---- 9. 创建运维用户 ----
useradd -m -s /bin/bash ops
echo "ops ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ops
chmod 440 /etc/sudoers.d/ops

# ---- 10. 配置SSH ----
cat >> /etc/ssh/sshd_config << 'EOF'

# === Security Hardening ===
Port 22
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 60
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ops root
X11Forwarding no
UseDNS no
EOF

# ---- 11. 配置ulimit ----
cat > /etc/security/limits.d/99-custom.conf << 'EOF'
*    soft    nofile    655360
*    hard    nofile    655360
*    soft    nproc     655360
*    hard    nproc     655360
*    soft    memlock   unlimited
*    hard    memlock   unlimited
root soft    nofile    655360
root hard    nofile    655360
EOF

# ---- 12. 禁用Transparent Huge Pages（数据库服务器必选） ----
cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
EOF
systemctl daemon-reload
systemctl enable disable-thp

echo "========== CentOS 系统初始化完成，请重启服务器 =========="
```

### 3.2 Ubuntu 20.04/22.04 初始化脚本

```bash
#!/bin/bash
# ubuntu-init.sh - Ubuntu 20.04/22.04 系统初始化脚本

set -euo pipefail

echo "========== Ubuntu 系统初始化开始 =========="

# ---- 1. 设置主机名 ----
hostnamectl set-hostname prod-server-01

# ---- 2. 配置时区和NTP ----
timedatectl set-timezone Asia/Shanghai
apt-get update -y
apt-get install -y chrony
systemctl enable chrony
systemctl start chrony

# ---- 3. 配置阿里云APT源 ----
cp /etc/apt/sources.list /etc/apt/sources.list.backup
cat > /etc/apt/sources.list << 'EOF'
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
EOF
apt-get update -y

# ---- 4. 安装基础软件包 ----
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    vim wget curl net-tools dnsutils tree htop iotop \
    sysstat dstat strace lsof tcpdump nmap \
    build-essential cmake \
    libssl-dev libreadline-dev zlib1g-dev \
    bash-completion lrzsz unzip zip \
    lvm2 mdadm \
    ufw

# ---- 5. 关闭swap（K8s节点必须） ----
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

# ---- 6. 配置ulimit ----
cat > /etc/security/limits.d/99-custom.conf << 'EOF'
*    soft    nofile    655360
*    hard    nofile    655360
*    soft    nproc     655360
*    hard    nproc     655360
*    soft    memlock   unlimited
*    hard    memlock   unlimited
EOF

# ---- 7. 配置SSH ----
cat >> /etc/ssh/sshd_config << 'EOF'

# === Security Hardening ===
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 60
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
UseDNS no
EOF
systemctl restart sshd

# ---- 8. 创建运维用户 ----
useradd -m -s /bin/bash ops
echo "ops ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ops
chmod 440 /etc/sudoers.d/ops

# ---- 9. 禁用THP ----
cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
EOF
systemctl daemon-reload
systemctl enable disable-thp

echo "========== Ubuntu 系统初始化完成，请重启服务器 =========="
```

### 3.3 系统初始化检查清单

```bash
#!/bin/bash
# check-init.sh - 初始化结果检查脚本

echo "========== 系统初始化检查 =========="

# 检查项
checks=(
    "hostname|当前主机名"
    "timezone|时区设置"
    "selinux|SELinux状态"
    "ulimit|文件描述符限制"
    "swap|Swap状态"
    "thp|THP状态"
    "ntp|NTP同步"
    "ssh|SSH配置"
)

echo "主机名: $(hostname)"
echo "时区: $(timedatectl | grep 'Time zone')"
echo "SELinux: $(getenforce 2>/dev/null || echo 'N/A')"
echo "ulimit -n: $(ulimit -n)"
echo "Swap: $(swapon --show | tail -1 || echo 'disabled')"
echo "THP: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
echo "NTP: $(chronyc tracking | grep 'Leap status' || echo 'N/A')"
echo "内核版本: $(uname -r)"
echo "系统版本: $(cat /etc/os-release | grep PRETTY_NAME)"
```

---

## 4. 内核参数优化

### 4.1 完整sysctl.conf配置

```bash
# /etc/sysctl.d/99-production.conf
# 生产环境内核参数优化配置
# 应用: sysctl -p /etc/sysctl.d/99-production.conf

# ==================== 网络参数优化 ====================

# TCP连接队列大小
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535

# TCP内存优化（单位：页，4KB/页）
# min / pressure / max
net.ipv4.tcp_mem = 786432 1048576 1572864
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 87380 16777216

# TCP连接复用和回收
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 50000
net.ipv4.tcp_max_syn_backlog = 65535

# TCP keepalive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

# TCP窗口和缓冲区
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# 端口范围
net.ipv4.ip_local_port_range = 1024 65535

# SYN Flood防护
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# 路由和转发
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 禁用IPv6（如不需要）
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# ARP优化
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 4096
net.ipv4.neigh.default.gc_thresh3 = 8192

# ==================== 文件系统参数 ====================

# 文件描述符限制
fs.file-max = 6553600
fs.nr_open = 6553600
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 65536

# AIO
fs.aio-max-nr = 1048576

# ==================== 内存参数 ====================

# 内存 overcommit
vm.overcommit_memory = 1
vm.overcommit_ratio = 80

# Swap控制
vm.swappiness = 10

# 脏页写回策略
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500

# 内存映射
vm.max_map_count = 262144

# OOM控制
vm.panic_on_oom = 0
vm.oom_kill_allocating_task = 0

# ==================== 安全参数 ====================

# 禁止IP源路由
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# 禁止ICMP重定向
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 开启SYN Cookie
net.ipv4.tcp_syncookies = 1

# 记录异常包
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# 忽略ICMP广播
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
```

### 4.2 按场景优化模板

```bash
#!/bin/bash
# apply-sysctl-by-role.sh - 按服务器角色应用内核参数

ROLE=${1:-"web"}

apply_common() {
    sysctl -p /etc/sysctl.d/99-production.conf
    echo "[OK] 通用参数已应用"
}

apply_web() {
    # Web服务器重点：高并发连接
    cat >> /etc/sysctl.d/99-web.conf << 'EOF'
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
EOF
    sysctl -p /etc/sysctl.d/99-web.conf
    echo "[OK] Web服务器参数已应用"
}

apply_db() {
    # 数据库服务器重点：内存和IO
    cat >> /etc/sysctl.d/99-db.conf << 'EOF'
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.max_map_count = 262144
net.core.somaxconn = 65535
EOF
    sysctl -p /etc/sysctl.d/99-db.conf
    echo "[OK] 数据库服务器参数已应用"
}

apply_k8s() {
    # K8s节点重点：网络转发和桥接
    cat >> /etc/sysctl.d/99-k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.all.forwarding = 1
EOF
    # 需要加载br_netfilter模块
    modprobe br_netfilter
    modprobe overlay
    sysctl -p /etc/sysctl.d/99-k8s.conf
    echo "[OK] K8s节点参数已应用"
}

apply_common
case "$ROLE" in
    web)   apply_web ;;
    db)    apply_db ;;
    k8s)   apply_k8s ;;
    *)     echo "未知角色: $ROLE，仅应用通用参数" ;;
esac
```

---

## 5. 磁盘IO与存储管理

### 5.1 IO调度器优化

```bash
#!/bin/bash
# optimize-io-scheduler.sh - IO调度器优化

echo "当前IO调度器:"
for disk in /sys/block/sd*; do
    name=$(basename "$disk")
    scheduler=$(cat "$disk/queue/scheduler" 2>/dev/null)
    echo "  $name: $scheduler"
done

# SSD推荐使用noop/none（CFQ对SSD无意义）
# HDD推荐使用deadline/mq-deadline

# 临时修改
echo noop > /sys/block/sda/queue/scheduler      # CentOS 7
echo none > /sys/block/sda/queue/scheduler       # CentOS 8+ (blk-mq)

# 永久修改 - CentOS
cat > /etc/udev/rules.d/60-io-scheduler.rules << 'EOF'
# SSD使用noop/none
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
# HDD使用mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF

# 优化队列深度（SSD）
echo 256 > /sys/block/sda/queue/nr_requests
echo 256 > /sys/block/sda/queue/read_ahead_kb

# 永久生效
cat >> /etc/rc.local << 'EOF'
echo 256 > /sys/block/sda/queue/nr_requests
echo 256 > /sys/block/sda/queue/read_ahead_kb
EOF
chmod +x /etc/rc.local
```

### 5.2 LVM管理完整指南

```bash
#!/bin/bash
# lvm-management.sh - LVM完整管理指南

# ==================== 创建LVM ====================

# 1. 创建物理卷（PV）
pvcreate /dev/sdb /dev/sdc
pvs  # 查看物理卷

# 2. 创建卷组（VG）
vgcreate datavg /dev/sdb /dev/sdc
vgs  # 查看卷组

# 3. 创建逻辑卷（LV）
# 固定大小
lvcreate -L 100G -n data_lv datavg

# 使用全部空间
lvcreate -l 100%FREE -n data_lv datavg

# 4. 格式化并挂载
mkfs.xfs /dev/datavg/data_lv           # XFS推荐
# mkfs.ext4 /dev/datavg/data_lv        # ext4也可以

mkdir -p /data
mount /dev/datavg/data_lv /data

# 写入fstab
echo "/dev/datavg/data_lv /data xfs defaults,noatime,nodiratime 0 0" >> /etc/fstab

# ==================== LVM扩容 ====================

# 1. 添加新磁盘到VG
pvcreate /dev/sdd
vgextend datavg /dev/sdd

# 2. 扩展逻辑卷
lvextend -L +50G /dev/datavg/data_lv      # 增加50G
# 或
lvextend -l +100%FREE /dev/datavg/data_lv  # 使用所有剩余空间

# 3. 扩展文件系统
xfs_growfs /data                            # XFS
# resize2fs /dev/datavg/data_lv            # ext4

# ==================== LVM快照（备份用） ====================

# 创建快照（建议大小为原LV的10-20%）
lvcreate -L 10G -s -n data_snap /dev/datavg/data_lv

# 挂载快照
mkdir -p /mnt/snap
mount -o ro /dev/datavg/data_snap /mnt/snap

# 备份快照
tar czf /backup/data_$(date +%Y%m%d).tar.gz -C /mnt/snap .

# 删除快照
umount /mnt/snap
lvremove -f /dev/datavg/data_snap

# ==================== LVM扩容在线操作（不停机） ====================

# 以MySQL数据目录为例
# 1. 确认当前空间
df -h /var/lib/mysql
lvs

# 2. 添加新磁盘
pvcreate /dev/sde
vgextend datavg /dev/sde

# 3. 在线扩容
lvextend -L +100G /dev/datavg/mysql_lv
xfs_growfs /var/lib/mysql    # XFS在线扩容，无需卸载

echo "LVM扩容完成，MySQL无感知"
```

### 5.3 RAID配置

```bash
#!/bin/bash
# raid-config.sh - RAID配置指南

# ==================== RAID级别选择 ====================
# RAID 0: 条带化，高性能，无冗余（临时数据/缓存）
# RAID 1: 镜像，2倍冗余（系统盘）
# RAID 5: 条带+奇偶校验，允许1块盘故障（读密集型）
# RAID 6: 双奇偶校验，允许2块盘故障（大容量存储）
# RAID 10: 镜像+条带，高性能+冗余（数据库推荐）
# RAID 50/60: 大规模存储

# ==================== 创建RAID 10 ====================

# 安装mdadm
yum install -y mdadm

# 创建RAID 10（4块盘）
mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/sd[b-e]

# 查看RAID状态
cat /proc/mdstat
mdadm --detail /dev/md0

# 保存RAID配置
mdadm --detail --scan >> /etc/mdadm.conf

# 格式化并挂载
mkfs.xfs /dev/md0
mkdir -p /data
mount /dev/md0 /data
echo "/dev/md0 /data xfs defaults,noatime 0 0" >> /etc/fstab

# ==================== RAID监控 ====================

# 配置邮件告警
echo "MAILADDR admin@example.com" >> /etc/mdadm.conf

# 创建监控脚本
cat > /usr/local/bin/raid-monitor.sh << 'SCRIPT'
#!/bin/bash
# RAID健康检查
if [ -f /proc/mdstat ]; then
    if grep -q '_' /proc/mdstat; then
        echo "ALERT: RAID degraded! Check /proc/mdstat"
        # 发送告警
        echo "RAID降级告警 - $(hostname) - $(date)" | mail -s "RAID Alert" admin@example.com
    fi
fi
SCRIPT
chmod +x /usr/local/bin/raid-monitor.sh

# 添加cron检查
echo "*/5 * * * * /usr/local/bin/raid-monitor.sh" >> /var/spool/cron/root

# ==================== RAID故障替换 ====================

# 1. 标记故障磁盘
mdadm /dev/md0 --fail /dev/sdc

# 2. 移除故障磁盘
mdadm /dev/md0 --remove /dev/sdc

# 3. 添加新磁盘（热插拔后）
mdadm /dev/md0 --add /dev/sdf

# 4. 查看重建进度
watch cat /proc/mdstat
```

---

## 6. systemd服务管理

### 6.1 自定义systemd服务

```ini
# /etc/systemd/system/myapp.service
# Java应用服务示例

[Unit]
Description=My Java Application
Documentation=https://docs.example.com/myapp
After=network.target mysql.service
Requires=mysql.service
# 启动失败后等待30秒再重试
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=myapp
Group=myapp
WorkingDirectory=/opt/myapp

# 环境变量
Environment="JAVA_HOME=/usr/local/jdk17"
Environment="APP_ENV=production"
EnvironmentFile=-/opt/myapp/conf/env.conf

# 启动命令
ExecStart=/usr/local/jdk17/bin/java \
    -Xms2g -Xmx2g \
    -XX:+UseG1GC \
    -XX:MaxGCPauseMillis=200 \
    -Dspring.config.location=/opt/myapp/conf/ \
    -jar /opt/myapp/app.jar

# 优雅停止
ExecStop=/bin/kill -SIGTERM $MAINPID
TimeoutStopSec=30
KillMode=mixed
KillSignal=SIGTERM

# 重启策略
Restart=on-failure
RestartSec=10

# 资源限制
LimitNOFILE=655360
LimitNPROC=655360
LimitCORE=infinity

# 安全加固
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/myapp/logs /opt/myapp/data
PrivateTmp=true

# OOM保护
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
```

### 6.2 systemd定时器（替代cron）

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Daily backup timer

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=600

[Install]
WantedBy=timers.target

# /etc/systemd/system/backup.service
[Unit]
Description=Daily backup service

[Service]
Type=oneshot
ExecStart=/opt/scripts/backup.sh
User=backup
StandardOutput=journal
StandardError=journal
```

```bash
# 启用定时器
systemctl enable --now backup.timer
systemctl list-timers --all
```

### 6.3 journald日志管理

```bash
# /etc/systemd/journald.conf
[Journal]
# 持久化存储
Storage=persistent
# 日志大小限制
SystemMaxUse=10G
SystemMaxFileSize=256M
# 保留时间
MaxRetentionSec=30day
# 压缩
Compress=yes
# 转发到syslog
ForwardToSyslog=yes

# 常用命令
journalctl -u myapp.service --since "1 hour ago"
journalctl -u myapp.service -f                        # 实时跟踪
journalctl -p err --since today                       # 今天的错误
journalctl --disk-usage                               # 日志占用空间
journalctl --vacuum-time=7d                           # 清理7天前日志
journalctl --vacuum-size=5G                           # 限制日志大小
```

---

## 7. 网络配置

### 7.1 网卡绑定（Bond）

```bash
#!/bin/bash
# network-bond.sh - 网卡绑定配置

# CentOS 7/8 - 使用NetworkManager
# 创建Bond接口
nmcli connection add type bond ifname bond0 mode 802.3ad \
    bond.options "miimon=100,lacp_rate=fast,xmit_hash_policy=layer3+4"

# 添加slave接口
nmcli connection add type ethernet slave-type bond \
    con-name bond0-slave1 ifname eth1 master bond0
nmcli connection add type ethernet slave-type bond \
    con-name bond0-slave2 ifname eth2 master bond0

# 配置IP
nmcli connection modify bond0 ipv4.addresses 10.10.1.10/24
nmcli connection modify bond0 ipv4.gateway 10.10.1.1
nmcli connection modify bond0 ipv4.dns "223.5.5.5 114.114.114.114"
nmcli connection modify bond0 ipv4.method manual

# 启用
nmcli connection up bond0

# Bond模式说明
# mode=0 (balance-rr)   轮询，负载均衡
# mode=1 (active-backup) 主备，高可用
# mode=2 (balance-xor)   XOR哈希
# mode=4 (802.3ad)       LACP动态聚合（推荐）
# mode=5 (balance-tlb)   发送负载均衡
# mode=6 (balance-alb)   收发负载均衡

# Ubuntu 20.04/22.04 - 使用Netplan
cat > /etc/netplan/01-bond.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eth1:
      dhcp4: false
    eth2:
      dhcp4: false
  bonds:
    bond0:
      interfaces: [eth1, eth2]
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        lacp-rate: fast
        transmit-hash-policy: layer3+4
      addresses: [10.10.1.10/24]
      gateway4: 10.10.1.1
      nameservers:
        addresses: [223.5.5.5, 114.114.114.114]
EOF
netplan apply
```

### 7.2 VLAN配置

```bash
# 创建VLAN子接口
ip link add link eth0 name eth0.100 type vlan id 100
ip addr add 192.168.100.1/24 dev eth0.100
ip link set dev eth0.100 up

# 持久化（NetworkManager）
nmcli connection add type vlan con-name vlan100 \
    dev eth0 id 100 ip4 192.168.100.1/24

# Netplan方式
cat > /etc/netplan/02-vlan.yaml << 'EOF'
network:
  version: 2
  vlans:
    vlan100:
      id: 100
      link: eth0
      addresses: [192.168.100.1/24]
EOF
netplan apply
```

### 7.3 iptables防火墙规则

```bash
#!/bin/bash
# iptables-production.sh - 生产环境iptables规则模板

# 清空规则
iptables -F
iptables -X
iptables -Z

# 默认策略
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 允许回环
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 允许已建立的连接
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 允许SSH（限制来源IP段）
iptables -A INPUT -p tcp --dport 22 -s 10.10.0.0/16 -j ACCEPT

# 允许HTTP/HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# 允许ICMP（ping）
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# 允许监控端口（Prometheus等）
iptables -A INPUT -p tcp --dport 9100 -s 10.10.1.0/24 -j ACCEPT

# 防SYN Flood
iptables -A INPUT -p tcp --syn -m limit --limit 100/s --limit-burst 200 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP

# 防端口扫描
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# 日志记录被丢弃的包
iptables -A INPUT -j LOG --log-prefix "IPT-DROP: " --log-level 4
iptables -A INPUT -j DROP

# 保存规则
iptables-save > /etc/sysconfig/iptables     # CentOS
# iptables-save > /etc/iptables/rules.v4    # Ubuntu
```

### 7.4 nftables（iptables替代）

```bash
#!/usr/sbin/nft -f
# /etc/nftables.conf - nftables生产环境配置

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # 允许回环
        iif lo accept
        
        # 允许已建立的连接
        ct state established,related accept
        
        # 允许SSH
        tcp dport 22 ip saddr 10.10.0.0/16 accept
        
        # 允许HTTP/HTTPS
        tcp dport { 80, 443 } accept
        
        # 允许ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        
        # 速率限制
        tcp dport 22 ct state new limit rate 3/minute accept
        
        # 日志并丢弃
        log prefix "nft-drop: " drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
```

---

## 8. 性能分析工具链

### 8.1 CPU分析

```bash
#!/bin/bash
# cpu-analysis.sh - CPU性能分析工具集

# ---- top 快速查看 ----
# 按1查看每个CPU核心，按P按CPU排序，按M按内存排序
top -bn1 | head -20

# ---- mpstat 多核CPU分析 ----
# 每秒采样，共10次
mpstat -P ALL 1 10

# ---- pidstat 进程级CPU ----
# 查看每个进程的CPU使用
pidstat -u 1 5

# ---- perf CPU火焰图 ----
# 采样30秒
perf record -g -p $(pgrep java) -- sleep 30
perf report

# 生成火焰图
# git clone https://github.com/brendangregg/FlameGraph.git
perf script | ./FlameGraph/stackcollapse-perf.pl | ./FlameGraph/flamegraph.pl > cpu-flame.svg

# ---- perf 统计系统调用 ----
perf stat -e 'syscalls:sys_enter_read,syscalls:sys_enter_write' -p $(pgrep java) -- sleep 10

# ---- strace 系统调用追踪 ----
# 追踪进程的系统调用
strace -p $(pgrep java) -f -e trace=network -c
# 统计系统调用耗时
strace -p $(pgrep java) -c -S time

# ---- 使用场景 ----
# CPU飙高 → top/pidstat定位进程 → perf record分析热点 → 火焰图可视化
# 上下文切换多 → pidstat -w 定位 → strace分析系统调用
```

### 8.2 内存分析

```bash
#!/bin/bash
# memory-analysis.sh - 内存性能分析

# ---- 系统内存概览 ----
free -h
cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree"

# ---- 进程内存使用 ----
# 按RSS排序
ps aux --sort=-rss | head -20

# ---- smaps 详细内存映射 ----
# 查看某进程的详细内存使用
cat /proc/$(pgrep java)/smaps_rollup

# ---- vmstat 内存和IO ----
vmstat 1 10
# 关注：si/so（swap交换）、free、buff、cache

# ---- 内存泄漏检测 ----
# 使用valgrind（需要编译debug版本）
valgrind --leak-check=full --show-leak-kinds=all ./myapp

# ---- pmap 进程内存映射 ----
pmap -x $(pgrep java) | tail -5

# ---- slab 内核内存 ----
slabtop -s c

# ---- OOM分析 ----
dmesg | grep -i "out of memory"
journalctl -k | grep -i oom
```

### 8.3 磁盘IO分析

```bash
#!/bin/bash
# disk-io-analysis.sh - 磁盘IO性能分析

# ---- iostat IO统计 ----
# 每秒输出，显示扩展信息
iostat -xdm 1 10
# 关注：await（平均IO等待时间）、%util（使用率）、avgqu-sz（队列长度）
# SSD: await < 1ms为佳，%util参考意义不大
# HDD: await < 10ms为佳，%util > 80%说明IO瓶颈

# ---- iotop 进程IO ----
iotop -oP

# ---- pidstat 进程IO ----
pidstat -d 1 5

# ---- blktrace 块设备追踪 ----
blktrace -d /dev/sda -o - | blkparse -i -

# ---- fio 磁盘基准测试 ----
# 顺序读
fio --name=seq-read --rw=read --bs=1M --size=1G --numjobs=1 --runtime=30 --direct=1

# 随机读（模拟数据库）
fio --name=rand-read --rw=randread --bs=4k --size=1G --numjobs=8 --runtime=30 --direct=1 --iodepth=32

# 随机读写混合
fio --name=rand-rw --rw=randrw --rwmixread=70 --bs=4k --size=1G --numjobs=8 --runtime=30 --direct=1

# ---- 使用场景 ----
# IO等待高 → iostat定位磁盘 → iotop找进程 → strace分析IO模式
# 数据库慢 → fio测磁盘性能 → 检查IO调度器 → 检查RAID配置
```

### 8.4 网络分析

```bash
#!/bin/bash
# network-analysis.sh - 网络性能分析

# ---- ss 连接统计 ----
ss -s                          # 连接汇总
ss -tnp | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head  # 连接数TOP IP
ss -tn state established | wc -l  # 当前连接数

# ---- sar 网络统计 ----
sar -n DEV 1 5                 # 网卡流量
sar -n TCP 1 5                 # TCP统计
sar -n ETCP 1 5                # TCP错误统计

# ---- tcpdump 抓包 ----
# 抓取80端口的HTTP请求
tcpdump -i eth0 port 80 -A -s 0 | grep -E "GET|POST|HTTP"

# 抓取特定主机的流量
tcpdump -i eth0 host 10.10.1.100 -w capture.pcap

# 分析TCP连接问题
tcpdump -i eth0 'tcp[tcpflags] & (tcp-syn|tcp-fin|tcp-rst) != 0' -n

# ---- netstat 网络统计 ----
netstat -s | grep -E "retransmit|timeout|overflow|drop"

# ---- iftop 实时流量 ----
iftop -i eth0 -nNP

# ---- mtr 网络路径诊断 ----
mtr -n -c 100 10.10.1.100
```

---

## 9. 故障排查手册

### 9.1 CPU飙高排查

```bash
#!/bin/bash
# troubleshoot-cpu.sh - CPU飙高排查流程

echo "========== CPU飙高排查 =========="

# Step 1: 查看系统负载
echo "--- 系统负载 ---"
uptime
echo ""

# Step 2: 查看CPU使用率
echo "--- CPU使用率 ---"
mpstat -P ALL 1 3
echo ""

# Step 3: 定位高CPU进程
echo "--- CPU TOP 10 进程 ---"
ps aux --sort=-%cpu | head -11
echo ""

# Step 4: 查看具体进程的线程
read -p "输入高CPU的PID: " PID
echo "--- 进程 $PID 的线程 ---"
top -Hp $PID -bn1 | head -20
echo ""

# Step 5: 如果是Java进程，打印线程栈
echo "--- Java线程栈分析 ---"
read -p "是否是Java进程? (y/n): " IS_JAVA
if [ "$IS_JAVA" == "y" ]; then
    # 找到高CPU线程ID
    echo "找到高CPU线程ID后，转换为16进制"
    printf "0x%x\n" $PID
    # 打印jstack
    jstack $PID > /tmp/jstack_$(date +%Y%m%d%H%M%S).txt
    echo "线程栈已保存到 /tmp/jstack_*.txt"
    echo "搜索对应的nid（16进制线程ID）"
fi

# Step 6: 使用perf分析
echo "--- perf快速分析 ---"
perf top -p $PID
```

**常见原因及解决方案：**

| 原因 | 排查方法 | 解决方案 |
|------|---------|---------|
| 死循环 | jstack/strace | 修复代码 |
| GC频繁 | jstat -gcutil | 调整JVM参数 |
| 锁竞争 | jstack分析BLOCKED | 优化锁粒度 |
| 正则回溯 | strace + perf | 优化正则表达式 |
| 大量计算 | perf record | 优化算法 |

### 9.2 内存泄漏排查

```bash
#!/bin/bash
# troubleshoot-memory.sh - 内存问题排查

echo "========== 内存问题排查 =========="

# Step 1: 系统内存概览
echo "--- 内存概览 ---"
free -h
echo ""

# Step 2: 进程内存排序
echo "--- 内存TOP 10进程 ---"
ps aux --sort=-rss | head -11
echo ""

# Step 3: 检查是否在使用swap
echo "--- Swap使用 ---"
swapon --show
echo ""
for pid in $(ls /proc/ | grep -E '^[0-9]+$'); do
    swap=$(awk '/VmSwap/{print $2}' /proc/$pid/status 2>/dev/null)
    if [ -n "$swap" ] && [ "$swap" -gt 0 ] 2>/dev/null; then
        name=$(cat /proc/$pid/comm 2>/dev/null)
        echo "PID $pid ($name): ${swap}kB swap"
    fi
done | sort -t: -k2 -rn | head -10
echo ""

# Step 4: 内核slab内存
echo "--- Slab内存 ---"
cat /proc/meminfo | grep -E "Slab|SReclaimable|SUnreclaim"
slabtop -s c -o | head -15
echo ""

# Step 5: OOM Killer记录
echo "--- OOM记录 ---"
dmesg | grep -i "out of memory" | tail -5
echo ""

# Java内存分析
echo "--- Java内存分析 ---"
for pid in $(pgrep java); do
    echo "Java PID: $pid"
    echo "  RSS: $(ps -o rss= -p $pid) KB"
    echo "  Heap: $(jstat -gcutil $pid 2>/dev/null | tail -1)"
done
```

### 9.3 磁盘IO问题排查

```bash
#!/bin/bash
# troubleshoot-disk-io.sh - 磁盘IO问题排查

echo "========== 磁盘IO排查 =========="

# Step 1: 磁盘空间检查
echo "--- 磁盘空间 ---"
df -hT
echo ""

# Step 2: IO使用率
echo "--- IO统计 ---"
iostat -xdm 1 3
echo ""

# Step 3: 进程IO
echo "--- 进程IO TOP ---"
iotop -oP -bn1 | head -20
echo ""

# Step 4: inode使用率
echo "--- inode使用 ---"
df -i | grep -v "^none"
echo ""

# Step 5: 大文件查找
echo "--- /目录下TOP 10大文件 ---"
find / -xdev -type f -exec du -sh {} + 2>/dev/null | sort -rh | head -10
echo ""

# Step 6: 删除但仍被占用的文件
echo "--- 已删除但未释放的文件 ---"
lsof | grep deleted | sort -k7 -rn | head -10
echo ""

# 解决方案提示
echo "常见解决方案:"
echo "  1. 清理大文件: find /var/log -name '*.gz' -mtime +30 -delete"
echo "  2. 清理docker: docker system prune -af"
echo "  3. 释放已删除文件: 重启对应进程"
echo "  4. 扩容LVM: lvextend -l +100%FREE /dev/vg/lv && xfs_growfs /mount"
```

### 9.4 网络不通排查

```bash
#!/bin/bash
# troubleshoot-network.sh - 网络问题排查

echo "========== 网络问题排查 =========="

TARGET=${1:-"8.8.8.8"}

# Step 1: 检查本机网络接口
echo "--- 网络接口 ---"
ip addr show
echo ""

# Step 2: 检查路由
echo "--- 路由表 ---"
ip route show
echo ""

# Step 3: 检查DNS
echo "--- DNS解析 ---"
nslookup baidu.com 2>/dev/null || dig baidu.com +short
echo ""

# Step 4: ping测试
echo "--- Ping测试 ($TARGET) ---"
ping -c 3 -W 2 $TARGET
echo ""

# Step 5: 端口连通性
echo "--- 端口测试 ---"
read -p "输入要测试的端口 (默认80): " PORT
PORT=${PORT:-80}
timeout 5 bash -c "echo >/dev/tcp/$TARGET/$PORT" 2>/dev/null && echo "端口 $PORT 可达" || echo "端口 $PORT 不可达"
echo ""

# Step 6: traceroute
echo "--- 路由追踪 ---"
traceroute -n -m 15 $TARGET 2>/dev/null || tracepath $TARGET
echo ""

# Step 7: 本机连接状态
echo "--- 连接状态统计 ---"
ss -s
echo ""

# Step 8: 防火墙规则
echo "--- iptables规则 ---"
iptables -L -n --line-numbers | head -30
echo ""

# Step 9: 网卡错误统计
echo "--- 网卡错误 ---"
ip -s link show
```

---

## 10. 安全加固

### 10.1 SSH安全加固

```bash
#!/bin/bash
# ssh-hardening.sh - SSH安全加固

# 备份原配置
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)

cat > /etc/ssh/sshd_config << 'EOF'
# === SSH安全加固配置 ===

# 基本设置
Port 22
AddressFamily inet
ListenAddress 0.0.0.0

# 认证
PermitRootLogin prohibit-password
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# 安全限制
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 60
ClientAliveInterval 300
ClientAliveCountMax 2

# 用户限制
AllowUsers ops root
# AllowGroups sshusers

# 功能限制
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no

# 加密算法（只允许强加密）
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512

# 日志
LogLevel VERBOSE
SyslogFacility AUTH

# Banner
Banner /etc/ssh/banner
EOF

# 创建登录Banner
cat > /etc/ssh/banner << 'EOF'
*******************************************************************
*                    AUTHORIZED ACCESS ONLY                       *
*  All connections are monitored and recorded.                    *
*  Disconnect IMMEDIATELY if you are not an authorized user.      *
*******************************************************************
EOF

# 重启SSH
systemctl restart sshd

echo "SSH加固完成，请确保已配置好密钥认证再禁用密码登录！"
```

### 10.2 PAM安全配置

```bash
#!/bin/bash
# pam-hardening.sh - PAM安全加固

# 密码复杂度策略
cat > /etc/security/pwquality.conf << 'EOF'
# 最小密码长度
minlen = 12
# 至少包含大写字母
ucredit = -1
# 至少包含小写字母
lcredit = -1
# 至少包含数字
dcredit = -1
# 至少包含特殊字符
ocredit = -1
# 密码历史（防止重复使用）
remember = 5
# 新旧密码至少30%不同
difok = 5
# 最大重复字符数
maxrepeat = 3
EOF

# 登录失败锁定
cat > /etc/security/faillock.conf << 'EOF'
# 5次失败后锁定
deny = 5
# 锁定时间15分钟
unlock_time = 900
# 失败计数窗口
fail_interval = 900
EOF

# 密码过期策略
cat >> /etc/login.defs << 'EOF'
# 密码最长有效期90天
PASS_MAX_DAYS 90
# 密码最短有效期7天
PASS_MIN_DAYS 7
# 密码最小长度
PASS_MIN_LEN 12
# 密码过期前14天警告
PASS_WARN_AGE 14
EOF

echo "PAM安全加固完成"
```

### 10.3 审计配置（auditd）

```bash
#!/bin/bash
# audit-config.sh - 系统审计配置

# 安装audit
yum install -y audit     # CentOS
# apt install -y auditd  # Ubuntu

# 配置审计规则
cat > /etc/audit/rules.d/audit.rules << 'EOF'
# 清除现有规则
-D
# 设置缓冲区大小
-b 8192

# === 用户和组操作审计 ===
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# === SSH配置审计 ===
-w /etc/ssh/sshd_config -p wa -k sshd_config

# === 系统启动审计 ===
-w /etc/crontab -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /var/spool/cron/ -p wa -k cron

# === 权限和属性变更 ===
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k owner_mod

# === 文件删除审计 ===
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete

# === 网络配置审计 ===
-w /etc/sysconfig/network -p wa -k network
-w /etc/sysconfig/network-scripts/ -p wa -k network

# === 登录审计 ===
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins

# === 特权命令审计 ===
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privileged

# === 内核模块审计 ===
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules

# 使规则生效
-e 2
EOF

# 重启auditd
systemctl restart auditd
systemctl enable auditd

# 查看审计日志
echo "常用审计查询命令:"
echo "  ausearch -k identity --start today    # 查看今天的身份变更"
echo "  ausearch -k sudoers --start today     # 查看今天的sudoers变更"
echo "  aureport --summary                     # 审计报告摘要"
echo "  aureport --login                       # 登录报告"
```

### 10.4 CIS Benchmark检查

```bash
#!/bin/bash
# cis-benchmark-check.sh - CIS Benchmark快速检查

echo "========== CIS Benchmark 检查 =========="
echo "检查时间: $(date)"
echo ""

# ---- 文件系统检查 ----
echo "--- 文件系统检查 ---"
echo "不必要的文件系统:"
for fs in cramfs freevxfs jffs2 hfs hfsplus squashfs udf vfat; do
    if lsmod | grep -q "$fs"; then
        echo "  [WARN] $fs 模块已加载"
    else
        echo "  [OK] $fs 模块未加载"
    fi
done
echo ""

# ---- 服务检查 ----
echo "--- 不必要的服务 ---"
for svc in avahi-daemon cups dhcpd slapd nfs rpcbind named vsftpd dovecot smb squid snmpd ypserv; do
    if systemctl is-active "$svc" &>/dev/null; then
        echo "  [WARN] $svc 正在运行"
    fi
done
echo ""

# ---- SSH检查 ----
echo "--- SSH配置检查 ---"
sshd_config="/etc/ssh/sshd_config"
checks=(
    "Protocol 2"
    "PermitRootLogin prohibit-password"
    "PasswordAuthentication no"
    "X11Forwarding no"
    "MaxAuthTries 3"
    "PermitEmptyPasswords no"
)
for check in "${checks[@]}"; do
    key=$(echo "$check" | awk '{print $1}')
    value=$(echo "$check" | awk '{print $2}')
    actual=$(grep -i "^$key" "$sshd_config" 2>/dev/null | awk '{print $2}')
    if [ "$actual" == "$value" ]; then
        echo "  [OK] $key = $value"
    else
        echo "  [WARN] $key = ${actual:-未设置} (应为 $value)"
    fi
done
echo ""

# ---- 文件权限检查 ----
echo "--- 关键文件权限 ---"
declare -A perms=(
    ["/etc/passwd"]="644"
    ["/etc/shadow"]="600"
    ["/etc/group"]="644"
    ["/etc/gshadow"]="600"
    ["/etc/ssh/sshd_config"]="600"
)
for file in "${!perms[@]}"; do
    expected="${perms[$file]}"
    actual=$(stat -c '%a' "$file" 2>/dev/null)
    if [ "$actual" == "$expected" ]; then
        echo "  [OK] $file: $actual"
    else
        echo "  [WARN] $file: $actual (应为 $expected)"
    fi
done
echo ""

# ---- 密码策略检查 ----
echo "--- 密码策略 ---"
echo "  最大有效期: $(grep PASS_MAX_DAYS /etc/login.defs | grep -v '^#' | awk '{print $2}')"
echo "  最小长度: $(grep PASS_MIN_LEN /etc/login.defs | grep -v '^#' | awk '{print $2}')"
echo ""

echo "========== 检查完成 =========="
```

---

## 11. 运维手册

### 11.1 日常巡检脚本

```bash
#!/bin/bash
# daily-check.sh - 日常巡检脚本

LOG="/var/log/daily-check-$(date +%Y%m%d).log"
exec > >(tee -a "$LOG") 2>&1

echo "=============================="
echo "日常巡检报告 - $(date)"
echo "=============================="

# 系统信息
echo ""
echo "=== 系统信息 ==="
echo "主机名: $(hostname)"
echo "系统版本: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "内核版本: $(uname -r)"
echo "运行时间: $(uptime -p)"

# CPU
echo ""
echo "=== CPU ==="
echo "负载: $(uptime | awk -F'load average:' '{print $2}')"
echo "CPU使用率:"
mpstat 1 1 | tail -1

# 内存
echo ""
echo "=== 内存 ==="
free -h

# 磁盘
echo ""
echo "=== 磁盘 ==="
df -hT | grep -v tmpfs
echo ""
echo "inode使用:"
df -i | grep -v tmpfs | grep -v none

# 网络
echo ""
echo "=== 网络连接 ==="
echo "总连接数: $(ss -s | grep 'estab' | awk '{print $4}')"
echo "TIME_WAIT: $(ss -t state time-wait | wc -l)"
echo "CLOSE_WAIT: $(ss -t state close-wait | wc -l)"

# 关键服务状态
echo ""
echo "=== 服务状态 ==="
for svc in sshd chronyd docker kubelet; do
    if systemctl is-active "$svc" &>/dev/null; then
        echo "  [OK] $svc"
    elif systemctl is-enabled "$svc" &>/dev/null; then
        echo "  [WARN] $svc 已启用但未运行"
    fi
done

# 最近登录
echo ""
echo "=== 最近登录 ==="
last -n 5

# 最近错误日志
echo ""
echo "=== 最近1小时错误日志 ==="
journalctl --since "1 hour ago" -p err --no-pager | tail -20

# 安全事件
echo ""
echo "=== 最近SSH失败登录 ==="
journalctl -u sshd --since "1 day ago" | grep "Failed" | wc -l
echo "次失败登录"

echo ""
echo "=============================="
echo "巡检完成 - $(date)"
echo "=============================="
```

### 11.2 系统清理脚本

```bash
#!/bin/bash
# system-cleanup.sh - 系统清理脚本

echo "========== 系统清理开始 =========="

# 1. 清理YUM/APT缓存
echo "--- 清理包管理缓存 ---"
if command -v yum &>/dev/null; then
    yum clean all
elif command -v apt &>/dev/null; then
    apt-get autoremove -y
    apt-get clean
fi

# 2. 清理旧内核
echo "--- 清理旧内核 ---"
if command -v package-cleanup &>/dev/null; then
    package-cleanup --oldkernels --count=2 -y
fi

# 3. 清理日志
echo "--- 清理旧日志 ---"
journalctl --vacuum-time=7d
find /var/log -name "*.gz" -mtime +30 -delete
find /var/log -name "*.old" -mtime +30 -delete
find /var/log -name "*.[0-9]" -mtime +30 -delete

# 4. 清理/tmp
echo "--- 清理/tmp ---"
find /tmp -type f -atime +7 -delete

# 5. 清理Docker（如已安装）
if command -v docker &>/dev/null; then
    echo "--- 清理Docker ---"
    docker system prune -af --volumes --filter "until=168h"
fi

# 6. 清理core dump
echo "--- 清理core dump ---"
find / -name "core.*" -mtime +7 -delete 2>/dev/null

# 7. 清理用户缓存
echo "--- 清理用户缓存 ---"
find /home/*/.cache -type f -atime +30 -delete 2>/dev/null

echo "========== 清理完成 =========="
df -h
```

### 11.3 系统升级注意事项

```bash
# CentOS 7 → 8 不建议直接升级，推荐重新安装
# CentOS 8 → Rocky Linux 8 迁移脚本:
# https://github.com/rocky-linux/rocky-tools/tree/main/migrate2rocky

# Ubuntu 升级流程:
# 1. 备份
# 2. 更新当前版本
apt update && apt upgrade -y
# 3. 安装update-manager
apt install update-manager-core -y
# 4. 执行升级
do-release-upgrade

# 内核升级后检查:
# 1. 验证驱动加载
lsmod
# 2. 检查网络
ip addr
# 3. 检查磁盘挂载
mount | grep -v tmpfs
# 4. 检查关键服务
systemctl --failed
```

---

## 12. 最佳实践与注意事项

### 12.1 系统管理黄金法则

1. **变更前备份** - 任何配置修改前，先备份原文件
2. **测试环境先行** - 所有变更先在测试环境验证
3. **灰度发布** - 批量服务器分批操作，先小批量验证
4. **监控先行** - 变更后观察监控指标是否异常
5. **回滚方案** - 准备好回滚方案再操作
6. **记录变更** - 所有变更记录到CMDB/变更系统

### 12.2 常见坑和解决方案

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| sshd重启后断连 | 配置错误 | 先用`sshd -t`测试配置 |
| 内核参数不生效 | sysctl.d优先级 | 检查`/etc/sysctl.d/`和`/etc/sysctl.conf` |
| LVM扩容后空间未变 | 文件系统未扩展 | 扩展LV后还需`xfs_growfs`或`resize2fs` |
| 时钟不同步 | chrony未运行 | `chronyc tracking`检查 |
| 文件描述符不够 | limits.d配置 | 检查`/etc/security/limits.d/` |
| OOM Killer杀进程 | 内存不足 | 设置`oom_score_adj`保护关键进程 |
| iptables规则丢失 | 未持久化 | `iptables-save > /etc/sysconfig/iptables` |

### 12.3 性能优化速查表

```
CPU问题:     top → pidstat → perf record → 火焰图
内存问题:    free → vmstat → pidstat -r → pmap
IO问题:      iostat → iotop → strace → fio
网络问题:    ss → sar → tcpdump → mtr
```

### 12.4 配置管理建议

```bash
# 使用Git管理服务器配置
cd /etc
git init
git add .
git commit -m "Initial configuration"

# 推荐使用Ansible统一管理，而不是手动SSH到每台服务器
```

---

> 📅 最后更新: 2026-05-02
> 📝 本手册涵盖Linux系统管理的核心内容，持续更新中
