#!/bin/bash
#============================================================================
# 企业级系统安全加固脚本
# 功能：一键加固 Linux 服务器，满足等保2.0三级要求
# 用法：./system-hardening.sh [full|ssh|kernel|audit|firewall|services]
# 注意：请在测试环境验证后再在生产环境执行
#============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_DIR="/var/log/security-hardening"
LOG_FILE="${LOG_DIR}/hardening-$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/var/backup/security-hardening/$(date +%Y%m%d_%H%M%S)"

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE"; }

#==================== SSH 加固 ====================
harden_ssh() {
    log "========== SSH 加固 =========="

    local sshd_config="/etc/ssh/sshd_config"
    backup_file "$sshd_config"

    # 备份原配置
    cp "$sshd_config" "${BACKUP_DIR}/sshd_config.bak"

    # SSH 加固配置
    cat > /etc/ssh/sshd_config.d/hardening.conf <<'EOF'
# ========== SSH 安全加固配置 ==========
# 基于等保2.0三级要求

# 网络配置
Port 22222                          # 修改默认端口
AddressFamily inet                  # 仅 IPv4
Protocol 2                          # 仅 SSH v2

# 认证配置
PermitRootLogin no                  # 禁止 root 登录
PasswordAuthentication no           # 禁止密码认证（仅密钥）
PubkeyAuthentication yes            # 启用公钥认证
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no

# 登录限制
MaxAuthTries 3                      # 最大尝试次数
MaxSessions 5                       # 最大并发会话
LoginGraceTime 60                   # 登录超时时间（秒）
MaxStartups 3:50:10                 # 连接速率限制

# 会话配置
ClientAliveInterval 300             # 空闲超时（秒）
ClientAliveCountMax 2               # 超时次数
TCPKeepAlive no                     # 禁用 TCP KeepAlive

# 用户白名单（根据实际情况修改）
AllowUsers opsuser deploy
AllowGroups ops sshusers

# 安全配置
X11Forwarding no                    # 禁用 X11 转发
AllowTcpForwarding no               # 禁用 TCP 转发
AllowAgentForwarding no             # 禁用 Agent 转发
PermitTunnel no                     # 禁用隧道
GatewayPorts no                     # 禁用网关端口

# 日志配置
SyslogFacility AUTH
LogLevel VERBOSE                    # 详细日志

# 加密算法（仅允许强加密）
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org

# Banner
Banner /etc/ssh/banner.txt
PrintMotd no
PrintLastLog yes
EOF

    # 创建登录 Banner
    cat > /etc/ssh/banner.txt <<'EOF'
*************************************************************
*  WARNING: Authorized access only!                         *
*  All connections are monitored and recorded.              *
*  Disconnect IMMEDIATELY if you are not an authorized user.*
*************************************************************
EOF

    # 验证配置
    if sshd -t 2>/dev/null; then
        log "SSH 配置验证通过"
        systemctl reload sshd
        log "SSH 服务已重新加载"
    else
        error "SSH 配置验证失败，请检查"
        cp "${BACKUP_DIR}/sshd_config.bak" "$sshd_config"
        return 1
    fi

    log "SSH 加固完成"
    warn "注意：SSH 端口已改为 22222，请确保防火墙已开放"
}

#==================== 内核安全参数 ====================
harden_kernel() {
    log "========== 内核安全参数加固 =========="

    cat > /etc/sysctl.d/99-security.conf <<'EOF'
# ========== 内核安全参数 ==========
# 基于 CIS Benchmark 和等保2.0

#--- 网络安全 ---
# 防止 IP 欺骗
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 禁止 ICMP 重定向（防止中间人攻击）
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# 禁止源路由（防止路由欺骗）
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# SYN Flood 防护
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# 忽略 ICMP 广播
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 记录可疑数据包
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# 禁止 IPv6 路由通告
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

#--- 内存安全 ---
# 地址空间随机化（ASLR）
kernel.randomize_va_space = 2

# 限制 core dump
fs.suid_dumpable = 0

# 限制 dmesg 访问
kernel.dmesg_restrict = 1

# 限制 kernel pointer 泄露
kernel.kptr_restrict = 2

#--- 连接跟踪 ---
net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30

#--- 性能优化 ---
net.core.somaxconn = 65535
net.ipv4.tcp_max_tw_buckets = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_tw_reuse = 1
EOF

    # 加载内核模块
    modprobe nf_conntrack 2>/dev/null || true

    # 应用参数
    sysctl --system >/dev/null 2>&1
    log "内核安全参数已生效"
}

#==================== 审计日志 ====================
harden_audit() {
    log "========== 审计日志配置 =========="

    # 安装 auditd
    yum install -y audit >/dev/null 2>&1 || apt-get install -y auditd >/dev/null 2>&1

    # 配置审计规则
    cat > /etc/audit/rules.d/hardening.rules <<'EOF'
# ========== 审计规则 ==========
# 基于等保2.0三级要求

# 删除所有现有规则
-D

# 设置缓冲区大小
-b 8192

# 审计失败的系统调用
-a always,exit -F arch=b64 -S execve -F uid>=1000 -F auid!=4294967295 -k exec_log
-a always,exit -F arch=b32 -S execve -F uid>=1000 -F auid!=4294967295 -k exec_log

# 审计用户认证相关
-w /etc/pam.d/ -p wa -k pam_config
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/shadow -p wa -k shadow
-w /etc/passwd -p wa -k passwd
-w /etc/group -p wa -k group
-w /etc/gshadow -p wa -k gshadow
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# 审计关键目录
-w /etc/ -p wa -k etc_changes
-w /var/log/ -p wa -k log_changes
-w /usr/bin/ -p wa -k bin_changes
-w /usr/sbin/ -p wa -k sbin_changes
-w /usr/local/bin/ -p wa -k local_bin
-w /usr/local/sbin/ -p wa -k local_sbin

# 审计网络配置
-w /etc/hosts -p wa -k network_config
-w /etc/sysconfig/network -p wa -k network_config
-w /etc/NetworkManager/ -p wa -k network_config

# 审计 cron 任务
-w /etc/crontab -p wa -k cron_config
-w /etc/cron.d/ -p wa -k cron_config
-w /var/spool/cron/ -p wa -k cron_config

# 审计内核模块加载
-w /sbin/insmod -p x -k kernel_modules
-w /sbin/rmmod -p x -k kernel_modules
-w /sbin/modprobe -p x -k kernel_modules

# 审计文件权限变更
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k owner_mod

# 审计删除操作
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete

# 审计时间修改
-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time_change
-w /etc/localtime -p wa -k time_change

# 设置审计规则不可变（需重启才能修改）
-e 2
EOF

    # 重启 auditd
    systemctl restart auditd 2>/dev/null || service auditd restart 2>/dev/null
    systemctl enable auditd 2>/dev/null || true

    log "审计日志配置完成"
}

#==================== 防火墙配置 ====================
harden_firewall() {
    log "========== 防火墙配置 =========="

    # 安装 iptables-services
    yum install -y iptables-services >/dev/null 2>&1 || true

    # 清空现有规则
    iptables -F
    iptables -X
    iptables -Z

    # 默认策略：拒绝所有入站，允许所有出站
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # 允许本地回环
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # 允许已建立的连接
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # 允许 SSH（自定义端口）
    iptables -A INPUT -p tcp --dport 22222 -m state --state NEW -m recent --set --name SSH
    iptables -A INPUT -p tcp --dport 22222 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
    iptables -A INPUT -p tcp --dport 22222 -j ACCEPT

    # 允许 HTTP/HTTPS
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT

    # 允许 ICMP（限制速率）
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

    # 允许 NTP
    iptables -A INPUT -p udp --dport 123 -j ACCEPT

    # 允许 DNS
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p tcp --dport 53 -j ACCEPT

    # 防止 SYN Flood
    iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
    iptables -A INPUT -p tcp --syn -j DROP

    # 防止端口扫描
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP
    iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
    iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP

    # 日志记录被拒绝的连接
    iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-dropped: " --log-level 4

    # 保存规则
    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/sysconfig/iptables
        log "iptables 规则已保存"
    fi

    log "防火墙配置完成"
}

#==================== 服务最小化 ====================
harden_services() {
    log "========== 服务最小化 =========="

    # 需要禁用的服务列表
    local services_to_disable=(
        "avahi-daemon"      # mDNS
        "cups"              # 打印服务
        "rpcbind"           # RPC绑定
        "nfs-server"        # NFS服务
        "vsftpd"            # FTP服务
        "telnet.socket"     # Telnet
        "rsh.socket"        # RSH
        "rlogin.socket"     # RLogin
        "tftp.socket"       # TFTP
        "ypserv"            # NIS服务
    )

    for svc in "${services_to_disable[@]}"; do
        if systemctl is-active "$svc" >/dev/null 2>&1; then
            systemctl stop "$svc"
            systemctl disable "$svc"
            log "已禁用: $svc"
        fi
    done

    # 确保关键服务运行
    local services_to_enable=(
        "sshd"
        "rsyslog"
        "auditd"
        "crond"
        "chronyd"
    )

    for svc in "${services_to_enable[@]}"; do
        if systemctl list-unit-files | grep -q "$svc"; then
            systemctl enable "$svc" 2>/dev/null || true
            log "已启用: $svc"
        fi
    done

    log "服务最小化配置完成"
}

#==================== 文件权限加固 ====================
harden_file_permissions() {
    log "========== 文件权限加固 =========="

    # 关键文件权限
    chmod 600 /etc/shadow
    chmod 600 /etc/gshadow
    chmod 644 /etc/passwd
    chmod 644 /etc/group
    chmod 600 /etc/ssh/sshd_config
    chmod 700 /root
    chmod 600 /boot/grub2/grub.cfg 2>/dev/null || true

    # 设置关键目录 sticky bit
    chmod 1777 /tmp
    chmod 1777 /var/tmp

    # 限制 cron 访问
    if [ ! -f /etc/cron.allow ]; then
        echo "root" > /etc/cron.allow
        chmod 600 /etc/cron.allow
    fi

    if [ ! -f /etc/at.allow ]; then
        echo "root" > /etc/at.allow
        chmod 600 /etc/at.allow
    fi

    # 删除不必要的 SUID/SGID 文件（谨慎操作）
    log "检查 SUID/SGID 文件:"
    find / -type f \( -perm -4000 -o -perm -2000 \) -exec ls -la {} \; 2>/dev/null | tee -a "$LOG_FILE"

    log "文件权限加固完成"
}

#==================== 密码策略 ====================
harden_password_policy() {
    log "========== 密码策略配置 =========="

    # 安装 pam_pwquality
    yum install -y pam_pwquality >/dev/null 2>&1 || true

    # 密码复杂度要求
    cat > /etc/security/pwquality.conf <<'EOF'
# 密码最小长度
minlen = 12
# 至少包含大写字母
ucredit = -1
# 至少包含小写字母
lcredit = -1
# 至少包含数字
dcredit = -1
# 至少包含特殊字符
ocredit = -1
# 密码历史（记住最近5个密码）
remember = 5
# 最大重复字符
maxrepeat = 3
# 最大连续相同字符类
maxclassrepeat = 4
EOF

    # 登录失败锁定
    cat > /etc/security/faillock.conf <<'EOF'
# 登录失败5次锁定
deny = 5
# 锁定时间15分钟
unlock_time = 900
# 失败计数窗口时间
fail_interval = 900
# root 也锁定
even_deny_root
EOF

    # 密码过期策略
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
    sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN    12/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs

    log "密码策略配置完成"
}

#==================== 辅助函数 ====================
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file" "${BACKUP_DIR}/$(basename $file).bak"
    fi
}

#==================== 主函数 ====================
main() {
    local action="${1:-full}"

    mkdir -p "$LOG_DIR" "$BACKUP_DIR"

    echo ""
    echo "============================================"
    echo "  企业级系统安全加固工具 v1.0"
    echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  主机: $(hostname)"
    echo "============================================"
    echo ""

    case "$action" in
        full)
            harden_ssh
            harden_kernel
            harden_audit
            harden_firewall
            harden_services
            harden_file_permissions
            harden_password_policy
            ;;
        ssh)       harden_ssh ;;
        kernel)    harden_kernel ;;
        audit)     harden_audit ;;
        firewall)  harden_firewall ;;
        services)  harden_services ;;
        files)     harden_file_permissions ;;
        password)  harden_password_policy ;;
        *)
            echo "用法: $0 [full|ssh|kernel|audit|firewall|services|files|password]"
            exit 1
            ;;
    esac

    echo ""
    echo "============================================"
    echo "  加固完成！详细日志: $LOG_FILE"
    echo "  备份目录: $BACKUP_DIR"
    echo "============================================"
}

main "$@"
