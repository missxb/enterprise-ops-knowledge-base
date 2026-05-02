# 安全基线 (CIS Benchmark)

## 概述

CIS (Center for Internet Security) Benchmark 是全球公认的安全配置最佳实践。本章以 CentOS 7/8 和 Ubuntu 20.04/22.04 为例，介绍关键安全基线检查项和修复方法。

## 1. 文件系统加固

### 1.1 狁立 /tmp 分区

```bash
# 检查
mount | grep /tmp

# 修复：在 /etc/fstab 中添加
tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev 0 0
```

### 1.2 设置关键目录权限

```bash
# 检查
stat -c "%a %U %G" /etc/passwd /etc/shadow /etc/group /etc/gshadow

# 修复
chmod 644 /etc/passwd
chmod 000 /etc/shadow
chmod 644 /etc/group
chmod 000 /etc/gshadow
chown root:root /etc/passwd /etc/shadow /etc/group /etc/gshadow
```

### 1.3 禁用不必要的文件系统

```bash
# 禁用 cramfs, freevxfs, hfs, hfsplus, udf
echo "install cramfs /bin/true" >> /etc/modprobe.d/CIS.conf
echo "install freevxfs /bin/true" >> /etc/modprobe.d/CIS.conf
echo "install hfs /bin/true" >> /etc/modprobe.d/CIS.conf
echo "install hfsplus /bin/true" >> /etc/modprobe.d/CIS.conf
echo "install udf /bin/true" >> /etc/modprobe.d/CIS.conf
```

## 2. 服务加固

### 2.1 禁用不必要服务

```bash
# 检查并禁用
for svc in avahi-daemon cups dhcpd slapd nfs rpcbind named vsftpd dovecot smb squid snmpd ypserv; do
    systemctl disable $svc 2>/dev/null
    systemctl stop $svc 2>/dev/null
done
```

### 2.2 时间同步

```bash
# 安装 chrony
yum install -y chrony
systemctl enable chronyd

# 配置 /etc/chrony.conf
server ntp.aliyun.com iburst
server cn.pool.ntp.org iburst

systemctl restart chronyd
```

## 3. SSH 加固

```bash
# /etc/ssh/sshd_config
Port 22222                          # 修改默认端口
PermitRootLogin no                  # 禁止 root 登录
PasswordAuthentication no           # 禁用密码认证
PubkeyAuthentication yes            # 启用密钥认证
MaxAuthTries 3                      # 最大尝试次数
ClientAliveInterval 300             # 空闲超时
ClientAliveCountMax 2               # 超时次数
AllowUsers ops deploy               # 白名单用户
Protocol 2                          # 仅 SSH2
X11Forwarding no                    # 禁用 X11 转发
```

## 4. 内核安全参数

```bash
# /etc/sysctl.d/99-security.conf
# 禁用 IP 转发（非路由器）
net.ipv4.ip_forward = 0

# 禁用 ICMP 重定向
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# 启用 SYN Cookie
net.ipv4.tcp_syncookies = 1

# 记录可疑数据包
net.ipv4.conf.all.log_martians = 1

# 禁用源路由
net.ipv4.conf.all.accept_source_route = 0

# 启用反向路径过滤
net.ipv4.conf.all.rp_filter = 1

# 禁用 ICMP 广播回复
net.ipv4.icmp_echo_ignore_broadcasts = 1

# 应用
sysctl -p /etc/sysctl.d/99-security.conf
```

## 5. 审计配置

```bash
# 安装 auditd
yum install -y audit

# /etc/audit/rules.d/cis.rules
# 监控用户/组修改
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity

# 监控 sudo 使用
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# 监控登录
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins

# 监控网络配置
-w /etc/hosts -p wa -k network
-w /etc/sysconfig/network -p wa -k network

# 重启 auditd
service auditd restart
```

## 6. 密码策略

```bash
# /etc/security/pwquality.conf
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
maxrepeat = 3
maxclassrepeat = 4

# /etc/login.defs
PASS_MAX_DAYS 90
PASS_MIN_DAYS 7
PASS_WARN_AGE 14
```

## 自动化检查脚本

```bash
#!/bin/bash
# CIS 基线快速检查
echo "=== CIS Security Baseline Check ==="
echo "--- SSH Configuration ---"
grep -E "^(PermitRootLogin|PasswordAuthentication|Port)" /etc/ssh/sshd_config
echo "--- Firewall Status ---"
systemctl is-active firewalld iptables
echo "--- SELinux Status ---"
getenforce
echo "--- Kernel Parameters ---"
sysctl net.ipv4.ip_forward net.ipv4.tcp_syncookies
echo "--- Failed Logins ---"
lastb | head -5
echo "--- SUID Files ---"
find / -perm -4000 -type f 2>/dev/null | head -10
```
