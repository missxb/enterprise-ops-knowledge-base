# 安全加固与等保合规完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. 系统安全加固（CIS Benchmark）](#2-系统安全加固cis-benchmark)
- [3. 网络安全](#3-网络安全)
- [4. SSH安全加固](#4-ssh安全加固)
- [5. 漏洞扫描与修复](#5-漏洞扫描与修复)
- [6. 等保2.0合规清单](#6-等保20合规清单)
- [7. 日志审计](#7-日志审计)
- [8. 密钥管理（HashiCorp Vault）](#8-密钥管理hashicorp-vault)
- [9. 安全事件响应流程](#9-安全事件响应流程)
- [10. 最佳实践](#10-最佳实践)

---

## 1. 项目背景与架构设计

### 1.1 安全体系架构

```
┌─────────────────────────────────────────────────────────────┐
│                    企业安全体系架构                           │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   安全管理层                          │   │
│  │   安全策略 | 安全组织 | 安全制度 | 安全培训            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ 网络安全  │ │ 主机安全  │ │ 应用安全  │ │  数据安全    │  │
│  │          │ │          │ │          │ │              │  │
│  │ 防火墙   │ │ 系统加固  │ │ WAF      │ │  加密        │  │
│  │ IDS/IPS  │ │ 漏洞管理  │ │ 代码审计  │ │  备份        │  │
│  │ VPN      │ │ 基线检查  │ │ 渗透测试  │ │  访问控制    │  │
│  │ 网络隔离 │ │ 防病毒    │ │ 安全编码  │ │  脱敏        │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   安全运营中心 (SOC)                   │   │
│  │   日志审计 | 安全监控 | 事件响应 | 合规管理            │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 安全防护层次

| 层次 | 防护内容 | 关键技术 |
|------|---------|---------|
| 网络层 | 防火墙、IDS/IPS、DDoS防护 | iptables、Suricata、云盾 |
| 主机层 | 系统加固、漏洞管理、基线检查 | CIS Benchmark、Trivy |
| 应用层 | WAF、代码审计、渗透测试 | ModSecurity、SonarQube |
| 数据层 | 加密、备份、访问控制、脱敏 | Vault、SSL/TLS |
| 管理层 | 策略、制度、培训、审计 | 等保2.0、ISO27001 |

---

## 2. 系统安全加固（CIS Benchmark）

### 2.1 CIS加固脚本

```bash
#!/bin/bash
# cis-hardening.sh - CIS Benchmark安全加固脚本
# 适用于 CentOS 7/8 和 Ubuntu 20.04/22.04

set -euo pipefail

echo "========== CIS Benchmark 安全加固 =========="

# ===== 1. 文件系统加固 =====

# 1.1 禁用不必要的文件系统
cat > /etc/modprobe.d/cis-filesystem.conf << 'EOF'
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
install vfat /bin/true
EOF

# 1.2 确保/tmp独立分区
# 检查/tmp是否独立挂载
if ! mount | grep -q "on /tmp "; then
    echo "WARNING: /tmp 不是独立分区，建议独立挂载"
fi

# 1.3 设置关键文件权限
chmod 644 /etc/passwd
chmod 600 /etc/shadow
chmod 644 /etc/group
chmod 600 /etc/gshadow
chmod 600 /etc/ssh/sshd_config
chmod 600 /boot/grub2/grub.cfg 2>/dev/null || true

# ===== 2. 服务加固 =====

# 2.1 禁用不必要的服务
for svc in avahi-daemon cups dhcpd slapd nfs rpcbind named vsftpd \
           dovecot smb squid snmpd ypserv telnet.socket rsh.socket; do
    systemctl disable "$svc" 2>/dev/null || true
    systemctl stop "$svc" 2>/dev/null || true
done

# 2.2 禁用USB存储（可选）
cat > /etc/modprobe.d/cis-usb.conf << 'EOF'
install usb-storage /bin/true
EOF

# ===== 3. 网络加固 =====

# 3.1 内核网络安全参数
cat > /etc/sysctl.d/cis-network.conf << 'EOF'
# 禁止IP转发（非路由器）
net.ipv4.ip_forward = 0

# 禁止发送ICMP重定向
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 禁止接受源路由
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# 禁止接受ICMP重定向
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# 开启SYN Cookie
net.ipv4.tcp_syncookies = 1

# 记录异常包
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# 忽略ICMP广播
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 反向路径过滤
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
sysctl -p /etc/sysctl.d/cis-network.conf

# ===== 4. SSH加固 =====
cat > /etc/ssh/sshd_config.d/cis-hardening.conf << 'EOF'
# CIS SSH加固配置
Port 22
Protocol 2
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 60
ClientAliveInterval 300
ClientAliveCountMax 3
AllowUsers ops root
PermitEmptyPasswords no
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
UseDNS no
Banner /etc/issue.net

# 加密算法限制
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
EOF

# 登录Banner
cat > /etc/issue.net << 'EOF'
*******************************************************************
*                    AUTHORIZED ACCESS ONLY                       *
*  All connections are monitored and recorded.                    *
*  Disconnect IMMEDIATELY if you are not an authorized user.      *
*******************************************************************
EOF

systemctl restart sshd

# ===== 5. 认证加固 =====

# 5.1 密码复杂度
cat > /etc/security/pwquality.conf << 'EOF'
minlen = 12
ucredit = -1
lcredit = -1
dcredit = -1
ocredit = -1
remember = 5
difok = 5
maxrepeat = 3
EOF

# 5.2 密码过期
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 7/' /etc/login.defs
sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN 12/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE 14/' /etc/login.defs

# 5.3 登录失败锁定
cat > /etc/security/faillock.conf << 'EOF'
deny = 5
unlock_time = 900
fail_interval = 900
EOF

# ===== 6. 审计配置 =====
# 详见第7节

echo "========== CIS加固完成 =========="
```

---

## 3. 网络安全

### 3.1 防火墙规则（生产环境）

```bash
#!/bin/bash
# firewall-production.sh - 生产环境防火墙

# 清空规则
iptables -F
iptables -X
iptables -Z

# 默认策略：拒绝所有入站
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 允许回环
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 允许已建立的连接
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 允许SSH（限制来源）
iptables -A INPUT -p tcp --dport 22 -s 10.10.0.0/16 -m state --state NEW -j ACCEPT

# 允许HTTP/HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# 允许ICMP
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# 允许监控
iptables -A INPUT -p tcp --dport 9100 -s 10.10.1.0/24 -j ACCEPT  # node_exporter
iptables -A INPUT -p tcp --dport 9090 -s 10.10.1.0/24 -j ACCEPT  # prometheus

# 防SYN Flood
iptables -A INPUT -p tcp --syn -m limit --limit 100/s --limit-burst 200 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP

# 防端口扫描
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP

# 记录并丢弃
iptables -A INPUT -j LOG --log-prefix "IPT-DROP: " --log-level 4 -m limit --limit 10/min
iptables -A INPUT -j DROP

# 保存
iptables-save > /etc/sysconfig/iptables
```

### 3.2 IDS/IPS部署（Suricata）

```bash
#!/bin/bash
# deploy-suricata.sh - Suricata IDS部署

# 安装
yum install -y epel-release
yum install -y suricata

# 更新规则
suricata-update
suricata-update enable-source et/open
suricata-update enable-source ptresearch/attackdetection

# 配置 /etc/suricata/suricata.yaml
cat >> /etc/suricata/suricata.yaml << 'EOF'
# 网络接口
af-packet:
  - interface: eth0
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes

# 规则文件
default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules

# 输出
outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: /var/log/suricata/eve.json
      types:
        - alert
        - dns
        - tls
        - http
        - ssh
EOF

# 启动
systemctl enable suricata
systemctl start suricata

# 查看告警
tail -f /var/log/suricata/eve.json | jq 'select(.event_type=="alert")'
```

---

## 4. SSH安全加固

### 4.1 密钥认证配置

```bash
#!/bin/bash
# ssh-key-auth.sh - SSH密钥认证配置

# 1. 生成密钥对（在客户端执行）
# ssh-keygen -t ed25519 -C "ops@example.com"
# ssh-keygen -t rsa -b 4096 -C "ops@example.com"

# 2. 部署公钥到服务器
# ssh-copy-id -i ~/.ssh/id_ed25519.pub ops@server

# 3. 服务器端配置
cat >> /etc/ssh/sshd_config << 'EOF'

# 禁用密码认证
PasswordAuthentication no
ChallengeResponseAuthentication no

# 启用公钥认证
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# 限制用户
AllowUsers ops root

# 限制尝试次数
MaxAuthTries 3
LoginGraceTime 30
EOF

systemctl restart sshd

# 4. 确保密钥权限
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

### 4.2 2FA双因子认证

```bash
#!/bin/bash
# ssh-2fa.sh - SSH双因子认证配置

# 1. 安装Google Authenticator
yum install -y google-authenticator  # CentOS
# apt install -y libpam-google-authenticator  # Ubuntu

# 2. 初始化（每个用户执行）
# google-authenticator -t -d -f -r 3 -R 30 -w 3

# 3. PAM配置
cat >> /etc/pam.d/sshd << 'EOF'
auth required pam_google_authenticator.so
EOF

# 4. SSH配置
cat >> /etc/ssh/sshd_config << 'EOF'
ChallengeResponseAuthentication yes
AuthenticationMethods publickey,keyboard-interactive
EOF

systemctl restart sshd
```

### 4.3 JumpServer堡垒机

```yaml
# JumpServer Docker Compose部署
version: '3.8'
services:
  jumpserver:
    image: jumpserver/jms_all:v3.10
    container_name: jumpserver
    ports:
      - "80:80"
      - "2222:2222"
    environment:
      SECRET_KEY: your-secret-key-here
      BOOTSTRAP_TOKEN: your-bootstrap-token
      LOG_LEVEL: ERROR
      DOMAINS: jumpserver.example.com
    volumes:
      - jumpserver-data:/opt/jumpserver/data
    restart: unless-stopped

volumes:
  jumpserver-data:
```

---

## 5. 漏洞扫描与修复

### 5.1 Trivy镜像扫描

```bash
#!/bin/bash
# trivy-scan.sh - 镜像安全扫描

IMAGE=${1:-"myapp:latest"}

# 安装Trivy
# rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v0.48.0/trivy_0.48.0_Linux-64bit.rpm

# 扫描镜像漏洞
trivy image --severity HIGH,CRITICAL "$IMAGE"

# 扫描并生成报告
trivy image --format json --output report.json "$IMAGE"

# 扫描文件系统
trivy fs --severity HIGH,CRITICAL /path/to/project

# 扫描Kubernetes集群
trivy k8s --report summary cluster

# 扫描配置文件（IaC安全）
trivy config /path/to/terraform

# CI/CD集成
trivy image --exit-code 1 --severity CRITICAL "$IMAGE"
```

### 5.2 系统漏洞扫描

```bash
#!/bin/bash
# vuln-scan.sh - 系统漏洞扫描

# 1. 检查系统已知漏洞
# CentOS
yum updateinfo list security
yum updateinfo list security | grep -i critical

# Ubuntu
apt list --upgradable 2>/dev/null | grep -i security

# 2. 检查开放端口
ss -tlnp | grep -v "127.0.0.1"

# 3. 检查SUID文件
find / -perm -4000 -type f 2>/dev/null

# 4. 检查world-writable文件
find / -xdev -type f -perm -0002 2>/dev/null

# 5. 检查无主文件
find / -xdev \( -nouser -o -nogroup \) 2>/dev/null

# 6. 检查空密码用户
awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow

# 7. 检查root权限用户
awk -F: '($3 == 0) {print $1}' /etc/passwd

# 8. 检查crontab
for user in $(cut -d: -f1 /etc/passwd); do
    crontab -l -u "$user" 2>/dev/null && echo "User: $user"
done
```

---

## 6. 等保2.0合规清单

### 6.1 等保2.0三级要求清单

```yaml
# 等保2.0三级合规检查清单

安全物理环境:
  - 机房访问控制: "□ 门禁系统 □ 访客登记 □ 视频监控"
  - 机房环境: "□ 温湿度控制 □ 防水防潮 □ 防雷接地"
  - 电力供应: "□ UPS □ 冗余供电 □ 应急发电"

安全通信网络:
  - 网络架构: "□ 分区分域 □ 冗余设计 □ 带宽保障"
  - 通信传输: "□ 数据加密 □ 完整性校验 □ 抗抵赖"
  - 可信验证: "□ 设备可信 □ 通信可信 □ 应用可信"

安全区域边界:
  - 边界防护: "□ 防火墙 □ 入侵检测 □ 访问控制"
  - 访问控制: "□ ACL规则 □ 最小权限 □ 默认拒绝"
  - 入侵防范: "□ IDS/IPS □ 异常流量检测 □ 告警机制"
  - 恶意代码防范: "□ 防病毒 □ 恶意代码库更新"

安全计算环境:
  - 身份鉴别: "□ 口令复杂度 □ 登录失败锁定 □ 多因子认证"
  - 访问控制: "□ 最小权限 □ 默认拒绝 □ 特权管理"
  - 安全审计: "□ 审计策略 □ 审计日志 □ 日志保护"
  - 入侵防范: "□ 最小安装 □ 关闭端口服务 □ 漏洞管理"
  - 恶意代码防范: "□ 防病毒软件 □ 更新机制"
  - 数据完整性: "□ 传输加密 □ 存储加密 □ 备份恢复"
  - 数据保密性: "□ 敏感数据加密 □ 数据脱敏"
  - 数据备份恢复: "□ 本地备份 □ 异地备份 □ 定期演练"
  - 剩余信息保护: "□ 会话清除 □ 临时文件清除"
  - 个人信息保护: "□ 最小采集 □ 授权使用 □ 安全存储"

安全管理中心:
  - 系统管理: "□ 专人管理 □ 远程加密 □ 审计记录"
  - 审计管理: "□ 审计管理员 □ 审计策略 □ 日志分析"
  - 安全管理: "□ 安全策略 □ 安全制度 □ 安全培训"
  - 集中管控: "□ 统一管理 □ 统一监控 □ 统一告警"
```

### 6.2 等保加固检查脚本

```bash
#!/bin/bash
# djb-check.sh - 等保2.0合规检查

echo "========== 等保2.0三级合规检查 =========="
echo "检查时间: $(date)"
echo ""

# 身份鉴别
echo "=== 身份鉴别 ==="
echo "1. 密码复杂度策略:"
grep -E "^(minlen|ucredit|lcredit|dcredit|ocredit)" /etc/security/pwquality.conf 2>/dev/null || echo "  [未配置]"

echo "2. 登录失败锁定:"
grep -E "^(deny|unlock_time)" /etc/security/faillock.conf 2>/dev/null || echo "  [未配置]"

echo "3. 密码过期策略:"
grep -E "^PASS_(MAX|MIN)_DAYS|^PASS_WARN_AGE" /etc/login.defs | grep -v "^#"

echo "4. 空密码用户:"
awk -F: '($2 == "" || $2 == "!") {print "  [WARN] " $1}' /etc/shadow
echo ""

# 访问控制
echo "=== 访问控制 ==="
echo "1. root权限用户:"
awk -F: '($3 == 0) {print "  " $1}' /etc/passwd

echo "2. SUID文件:"
find /usr/bin /usr/sbin /usr/local/bin -perm -4000 -type f 2>/dev/null | head -10

echo "3. sudo配置:"
grep -E "^[^#]" /etc/sudoers 2>/dev/null | head -10
echo ""

# 安全审计
echo "=== 安全审计 ==="
echo "1. auditd状态:"
systemctl is-active auditd 2>/dev/null || echo "  [未运行]"

echo "2. 审计规则数:"
auditctl -l 2>/dev/null | wc -l

echo "3. 日志保留:"
journalctl --disk-usage 2>/dev/null
echo ""

# 入侵防范
echo "=== 入侵防范 ==="
echo "1. 开放端口:"
ss -tlnp | grep -v "127.0.0.1" | grep -v "::1"

echo "2. 防火墙状态:"
iptables -L -n | head -5

echo "3. SELinux:"
getenforce 2>/dev/null || echo "N/A"
echo ""

# 数据安全
echo "=== 数据安全 ==="
echo "1. SSH配置:"
grep -E "^(PasswordAuthentication|PubkeyAuthentication|PermitRootLogin)" /etc/ssh/sshd_config 2>/dev/null

echo "2. 文件权限:"
for f in /etc/passwd /etc/shadow /etc/group /etc/gshadow; do
    echo "  $f: $(stat -c '%a' $f 2>/dev/null)"
done
echo ""

echo "========== 检查完成 =========="
```

---

## 7. 日志审计

### 7.1 auditd完整配置

```bash
#!/bin/bash
# audit-config.sh - 审计配置

# 安装audit
yum install -y audit

# 配置审计规则
cat > /etc/audit/rules.d/audit.rules << 'EOF'
# 清除现有规则
-D
# 缓冲区大小
-b 8192

# 用户和组操作
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# SSH配置
-w /etc/ssh/sshd_config -p wa -k sshd_config

# 认证日志
-w /var/log/lastlog -p wa -k logins
-w /var/log/faillog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins

# Cron操作
-w /etc/crontab -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /var/spool/cron/ -p wa -k cron

# 权限和属性变更
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k owner_mod

# 文件删除
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete

# 网络配置
-w /etc/sysconfig/network -p wa -k network
-w /etc/NetworkManager/ -p wa -k network

# 特权命令
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privileged

# 内核模块
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules

# 时间修改
-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# 使规则生效
-e 2
EOF

# 重启auditd
systemctl restart auditd
systemctl enable auditd

# 常用审计查询
echo "常用审计查询命令:"
echo "  ausearch -k identity --start today    # 身份变更"
echo "  ausearch -k sudoers --start today     # sudoers变更"
echo "  ausearch -k delete --start today      # 文件删除"
echo "  ausearch -k sshd_config --start today # SSH配置变更"
echo "  aureport --summary                     # 审计摘要"
echo "  aureport --login                       # 登录报告"
echo "  aureport --anomaly                     # 异常报告"
```

---

## 8. 密钥管理（HashiCorp Vault）

### 8.1 Vault部署

```yaml
# docker-compose-vault.yml
version: '3.8'
services:
  vault:
    image: hashicorp/vault:1.15
    container_name: vault
    ports:
      - "8200:8200"
    environment:
      VAULT_ADDR: "http://0.0.0.0:8200"
      VAULT_API_ADDR: "http://0.0.0.0:8200"
    volumes:
      - vault-data:/vault/data
      - ./vault-config.hcl:/vault/config/config.hcl
    cap_add:
      - IPC_LOCK
    command: server
    restart: unless-stopped

volumes:
  vault-data:
```

```hcl
# vault-config.hcl
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

ui = true
disable_mlock = true

api_addr = "http://0.0.0.0:8200"
```

### 8.2 Vault使用

```bash
# 初始化Vault
vault operator init -key-shares=5 -key-threshold=3

# 解封Vault（需要3个key）
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>

# 登录
vault login <root_token>

# 启用KV引擎
vault secrets enable -path=secret kv-v2

# 存储密钥
vault kv put secret/myapp/db username="admin" password="SecurePass123!"

# 读取密钥
vault kv get secret/myapp/db
vault kv get -field=password secret/myapp/db

# 创建策略
cat > myapp-policy.hcl << 'EOF'
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}
EOF
vault policy write myapp-policy myapp-policy.hcl

# 创建应用Token
vault token create -policy=myapp-policy -ttl=8760h

# 动态数据库凭据
vault secrets enable database
vault write database/config/mydb \
    plugin_name=mysql-database-plugin \
    connection_url="{{username}}:{{password}}@tcp(mysql:3306)/" \
    allowed_roles="myapp-role" \
    username="vault" \
    password="VaultPass123!"

vault write database/roles/myapp-role \
    db_name=mydb \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT ON mydb.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"

# 获取动态凭据
vault read database/creds/myapp-role
```

---

## 9. 安全事件响应流程

### 9.1 安全事件分级

| 级别 | 定义 | 响应时间 | 示例 |
|------|------|---------|------|
| P0 紧急 | 核心业务受影响/数据泄露 | 15分钟 | 数据库被拖、勒索软件 |
| P1 高 | 重要系统被入侵 | 1小时 | 服务器被控制、挖矿 |
| P2 中 | 存在安全威胁 | 4小时 | 异常登录、漏洞利用尝试 |
| P3 低 | 安全隐患 | 24小时 | 配置不当、弱密码 |

### 9.2 事件响应流程

```
┌─────────────────────────────────────────────────────────┐
│                安全事件响应流程                           │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │ 1.检测   │─→│ 2.遏制   │─→│ 3.根除   │             │
│  │          │  │          │  │          │             │
│  │ 监控告警 │  │ 隔离感染 │  │ 清除威胁 │             │
│  │ 异常发现 │  │ 保全证据 │  │ 修补漏洞 │             │
│  │ 人员报告 │  │ 通知相关 │  │ 恢复系统 │             │
│  └──────────┘  └──────────┘  └────┬─────┘             │
│                                    │                    │
│  ┌──────────┐  ┌──────────┐       │                    │
│  │ 5.改进   │←│ 4.恢复   │←──────┘                    │
│  │          │  │          │                            │
│  │ 复盘总结 │  │ 逐步恢复 │                            │
│  │ 优化策略 │  │ 验证功能 │                            │
│  │ 更新预案 │  │ 持续监控 │                            │
│  └──────────┘  └──────────┘                            │
└─────────────────────────────────────────────────────────┘
```

### 9.3 应急响应脚本

```bash
#!/bin/bash
# incident-response.sh - 安全事件应急响应脚本

HOSTNAME=$(hostname)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="/tmp/incident_${HOSTNAME}_${TIMESTAMP}"
mkdir -p "$REPORT_DIR"

echo "========== 安全事件应急响应 =========="
echo "主机: $HOSTNAME"
echo "时间: $(date)"
echo "报告目录: $REPORT_DIR"

# 1. 系统基本信息
echo "--- 系统信息 ---"
uname -a > "$REPORT_DIR/system_info.txt"
cat /etc/os-release >> "$REPORT_DIR/system_info.txt"
uptime >> "$REPORT_DIR/system_info.txt"

# 2. 网络连接
echo "--- 网络连接 ---"
ss -tlnp > "$REPORT_DIR/listening_ports.txt"
ss -tnp > "$REPORT_DIR/connections.txt"
ip addr > "$REPORT_DIR/network_info.txt"
ip route >> "$REPORT_DIR/network_info.txt"

# 3. 进程信息
echo "--- 进程信息 ---"
ps auxf > "$REPORT_DIR/processes.txt"
top -bn1 > "$REPORT_DIR/top.txt"

# 4. 登录信息
echo "--- 登录信息 ---"
last -n 50 > "$REPORT_DIR/last_logins.txt"
lastb -n 50 > "$REPORT_DIR/failed_logins.txt"
who > "$REPORT_DIR/current_users.txt"

# 5. 异常进程
echo "--- 异常检查 ---"
# CPU使用率TOP10
ps aux --sort=-%cpu | head -11 > "$REPORT_DIR/high_cpu.txt"
# 内存使用TOP10
ps aux --sort=-rss | head -11 > "$REPORT_DIR/high_memory.txt"
# 可疑进程（隐藏进程）
ps aux | awk '{print $2}' | sort > /tmp/ps_pids.txt
ls /proc | grep -E '^[0-9]+$' | sort > /tmp/proc_pids.txt
comm -23 /tmp/proc_pids.txt /tmp/ps_pids.txt > "$REPORT_DIR/hidden_processes.txt" 2>/dev/null

# 6. 定时任务
echo "--- 定时任务 ---"
for user in $(cut -d: -f1 /etc/passwd); do
    echo "=== $user ===" >> "$REPORT_DIR/crontabs.txt"
    crontab -l -u "$user" 2>/dev/null >> "$REPORT_DIR/crontabs.txt"
done
ls -la /etc/cron.* >> "$REPORT_DIR/cron_dirs.txt" 2>/dev/null

# 7. 最近修改的文件
echo "--- 最近修改的文件 ---"
find / -xdev -type f -mtime -1 -ls 2>/dev/null | head -100 > "$REPORT_DIR/recent_files.txt"
find /tmp /var/tmp -type f -ls 2>/dev/null > "$REPORT_DIR/tmp_files.txt"

# 8. SSH相关
echo "--- SSH信息 ---"
cat /root/.ssh/authorized_keys > "$REPORT_DIR/root_ssh_keys.txt" 2>/dev/null
find /home -name authorized_keys -exec cat {} \; > "$REPORT_DIR/user_ssh_keys.txt" 2>/dev/null

# 9. 系统日志
echo "--- 系统日志 ---"
journalctl --since "24 hours ago" --priority=err > "$REPORT_DIR/error_logs.txt" 2>/dev/null
journalctl -u sshd --since "24 hours ago" > "$REPORT_DIR/ssh_logs.txt" 2>/dev/null

# 10. 打包
echo "--- 打包报告 ---"
tar czf /tmp/incident_report_${HOSTNAME}_${TIMESTAMP}.tar.gz -C /tmp "incident_${HOSTNAME}_${TIMESTAMP}"

echo "========== 应急响应完成 =========="
echo "报告: /tmp/incident_report_${HOSTNAME}_${TIMESTAMP}.tar.gz"
echo ""
echo "后续步骤:"
echo "1. 检查异常连接和进程"
echo "2. 检查定时任务和启动项"
echo "3. 检查最近修改的文件"
echo "4. 分析系统日志"
echo "5. 如确认入侵，隔离主机并保留证据"
```

---

## 10. 最佳实践

### 10.1 安全运维Checklist

```
# 日常安全检查
□ 检查系统登录日志
□ 检查异常进程和连接
□ 检查定时任务
□ 检查磁盘使用率
□ 检查安全告警

# 每周安全检查
□ 系统漏洞扫描
□ 镜像安全扫描
□ 审计日志分析
□ 备份恢复验证
□ 安全策略Review

# 每月安全检查
□ CIS Benchmark检查
□ 密码策略检查
□ 权限Review
□ 证书有效期检查
□ 安全培训

# 每季度安全检查
□ 渗透测试
□ 灾备演练
□ 安全制度Review
□ 合规审计
```

### 10.2 安全事件预防

1. **最小权限** - 所有用户和服务使用最小权限
2. **默认拒绝** - 防火墙和安全组默认拒绝
3. **纵深防御** - 多层安全防护
4. **持续监控** - 7×24安全监控
5. **定期更新** - 及时修补安全漏洞
6. **安全培训** - 定期安全意识培训
7. **应急演练** - 定期安全事件演练
8. **日志审计** - 所有操作可追溯

---

> 📅 最后更新: 2026-05-02
