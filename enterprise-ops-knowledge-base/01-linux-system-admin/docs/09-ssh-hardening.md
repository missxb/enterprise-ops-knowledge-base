# SSH 安全加固

## 概述

SSH 是远程管理服务器的主要通道，也是攻击者的首要目标。本文涵盖 SSH 密钥管理、跳板机配置、双因素认证及审计日志。

## 1. SSH 基础安全配置

### 1.1 服务端配置

```bash
# /etc/ssh/sshd_config

# 基本安全配置
Port 22222                          # 修改默认端口
ListenAddress 10.0.0.1              # 仅监听内网地址
Protocol 2                          # 仅使用 SSH v2

# 认证配置
PermitRootLogin no                  # 禁止 root 登录
PasswordAuthentication no           # 禁用密码认证
PubkeyAuthentication yes            # 启用公钥认证
ChallengeResponseAuthentication yes # 启用挑战应答（2FA）

# 用户限制
AllowUsers ops deploy               # 仅允许特定用户
AllowGroups sshusers                # 仅允许特定组
MaxAuthTries 3                      # 最大认证尝试次数
MaxSessions 5                       # 最大会话数
LoginGraceTime 30                   # 认证超时时间（秒）

# 会话配置
ClientAliveInterval 300             # 心跳间隔（秒）
ClientAliveCountMax 3               # 心跳失败次数
TCPKeepAlive yes                    # TCP 保活

# 安全加固
X11Forwarding no                    # 禁用 X11 转发
AllowTcpForwarding no               # 禁用 TCP 转发
AllowAgentForwarding no             # 禁用 Agent 转发
PermitTunnel no                     # 禁用隧道
GatewayPorts no                     # 禁用网关端口

# 日志配置
LogLevel VERBOSE                    # 详细日志
SyslogFacility AUTH

# 加密算法限制（仅允许强加密）
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512

# Banner
Banner /etc/ssh/banner.txt
```

### 1.2 SSH Banner

```bash
# /etc/ssh/banner.txt
*************************************************************
* WARNING: Authorized access only!                          *
* All connections are monitored and recorded.               *
* Disconnect IMMEDIATELY if you are not an authorized user. *
*************************************************************
```

### 1.3 客户端配置

```bash
# ~/.ssh/config

# 全局默认配置
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    AddKeysToAgent yes
    IdentitiesOnly yes
    HashKnownHosts yes
    StrictHostKeyChecking ask

# 跳板机配置
Host bastion
    HostName bastion.example.com
    User ops
    Port 22222
    IdentityFile ~/.ssh/bastion_ed25519

# 通过跳板机访问内网服务器
Host internal-*
    ProxyJump bastion
    User ops
    IdentityFile ~/.ssh/internal_ed25519

Host internal-web01
    HostName 10.0.1.10

Host internal-db01
    HostName 10.0.1.20
```

## 2. SSH 密钥管理

### 2.1 密钥生成

```bash
# 生成 Ed25519 密钥（推荐）
ssh-keygen -t ed25519 -C "ops@example.com" -f ~/.ssh/ops_ed25519

# 生成 RSA 密钥（兼容性需要）
ssh-keygen -t rsa -b 4096 -C "ops@example.com" -f ~/.ssh/ops_rsa

# 生成带密码保护的密钥
ssh-keygen -t ed25519 -C "ops@example.com" -f ~/.ssh/ops_ed25519 -N "StrongPassphrase"

# 修改密钥密码
ssh-keygen -p -f ~/.ssh/ops_ed25519

# 查看密钥指纹
ssh-keygen -lf ~/.ssh/ops_ed25519.pub
```

### 2.2 密钥分发

```bash
# 复制公钥到服务器
ssh-copy-id -i ~/.ssh/ops_ed25519.pub user@server

# 批量分发公钥
#!/bin/bash
KEY_FILE="~/.ssh/ops_ed25519.pub"
SERVERS="web01 web02 db01 db02"

for server in $SERVERS; do
    ssh-copy-id -i $KEY_FILE ops@$server
    echo "已分发到 $server"
done

# 手动添加公钥
cat ~/.ssh/ops_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

### 2.3 密钥轮换

```bash
#!/bin/bash
# SSH 密钥轮换脚本

KEY_AGE_DAYS=90
KEY_FILE="$HOME/.ssh/ops_ed25519"

# 检查密钥年龄
if [ -f "$KEY_FILE" ]; then
    KEY_DATE=$(stat -c %Y "$KEY_FILE")
    CURRENT_DATE=$(date +%s)
    KEY_AGE=$(( (CURRENT_DATE - KEY_DATE) / 86400 ))

    if [ $KEY_AGE -gt $KEY_AGE_DAYS ]; then
        echo "密钥已使用 $KEY_AGE 天，超过 $KEY_AGE_DAYS 天限制"
        echo "生成新密钥..."
        mv "$KEY_FILE" "${KEY_FILE}.old.$(date +%Y%m%d)"
        ssh-keygen -t ed25519 -C "ops@example.com" -f "$KEY_FILE" -N ""
        echo "请将新公钥分发到所有服务器"
    fi
fi
```

### 2.4 authorized_keys 管理

```bash
# authorized_keys 限制选项
# 限制命令
command="/usr/bin/rsync --server" ssh-ed25519 AAAA...

# 限制来源 IP
from="10.0.0.*" ssh-ed25519 AAAA...

# 禁止端口转发
no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA...

# 组合限制
from="10.0.0.*",command="/usr/bin/backup.sh",no-port-forwarding ssh-ed25519 AAAA...

# 查看当前用户的所有公钥
cat ~/.ssh/authorized_keys | awk '{print $3}' | while read key; do
    ssh-keygen -lf /dev/stdin <<< "$key" 2>/dev/null
done
```

## 3. 跳板机（堡垒机）配置

### 3.1 跳板机架构

```
互联网 → 跳板机(公网) → 内网服务器(私网)
```

### 3.2 跳板机配置

```bash
# 跳板机 /etc/ssh/sshd_config
Port 22222
ListenAddress 0.0.0.0
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowGroups bastion-users

# 禁止在跳板机上进行操作
ForceCommand echo "请通过 ProxyJump 访问目标服务器"

# 或使用自定义脚本
ForceCommand /usr/local/bin/bastion-shell.sh
```

### 3.3 ProxyJump 配置

```bash
# 通过跳板机连接内网服务器
ssh -J bastion:22222 ops@10.0.1.10

# ~/.ssh/config 配置
Host bastion
    HostName bastion.example.com
    Port 22222
    User ops

Host 10.0.1.*
    ProxyJump bastion
    User ops
```

### 3.4 审计日志

```bash
# 记录所有通过跳板机的命令
# /usr/local/bin/bastion-shell.sh
#!/bin/bash
LOG_DIR="/var/log/bastion"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y%m%d)_${USER}.log"

echo "=== $(date) === User: $USER From: $SSH_CLIENT ===" >> "$LOG_FILE"
echo "Command: $SSH_ORIGINAL_COMMAND" >> "$LOG_FILE"

# 执行原始命令
eval "$SSH_ORIGINAL_COMMAND" 2>&1 | tee -a "$LOG_FILE"
```

## 4. 双因素认证（2FA）

### 4.1 Google Authenticator

```bash
# 安装
yum install google-authenticator -y

# 用户配置
google-authenticator -t -d -f -r 3 -R 30 -w 3

# /etc/pam.d/sshd
auth required pam_google_authenticator.so nullok

# /etc/ssh/sshd_config
ChallengeResponseAuthentication yes
AuthenticationMethods publickey,keyboard-interactive

# 重启 SSH
systemctl restart sshd
```

### 4.2 TOTP 配置流程

```bash
# 1. 服务器安装 google-authenticator
# 2. 用户运行 google-authenticator 生成密钥
# 3. 用户将密钥添加到手机 Authenticator 应用
# 4. 配置 PAM 和 sshd
# 5. 测试登录流程

# 批量部署脚本
#!/bin/bash
USERS="alice bob charlie"
for user in $USERS; do
    su - $user -c "google-authenticator -t -d -f -r 3 -R 30 -w 3"
    echo "已为 $user 配置 2FA"
done
```

## 5. SSH 审计与监控

### 5.1 登录日志分析

```bash
# 查看 SSH 登录日志
journalctl -u sshd --since "1 week ago"

# 查看成功登录
grep "Accepted" /var/log/secure

# 查看失败登录
grep "Failed" /var/log/secure

# 统计失败登录 IP
grep "Failed password" /var/log/secure | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -20

# 统计登录用户
grep "Accepted" /var/log/secure | awk '{print $9}' | sort | uniq -c | sort -rn

# 实时监控登录
tail -f /var/log/secure | grep --color "Failed\|Accepted"
```

### 5.2 登录告警

```bash
#!/bin/bash
# SSH 登录告警脚本（通过 cron 定期执行）

LOG="/var/log/secure"
ALERT_EMAIL="ops@example.com"
FAILED_THRESHOLD=10

# 检查过去 5 分钟的失败登录
FAILED_COUNT=$(journalctl --since "5 min ago" -u sshd | grep -c "Failed")

if [ "$FAILED_COUNT" -gt "$FAILED_THRESHOLD" ]; then
    DETAILS=$(journalctl --since "5 min ago" -u sshd | grep "Failed" | tail -10)
    echo "SSH 登录失败告警：过去 5 分钟 $FAILED_COUNT 次失败

详情：
$DETAILS" | mail -s "SSH 登录告警 - $(hostname)" "$ALERT_EMAIL"
fi

# 检查异常登录（非工作时间）
HOUR=$(date +%H)
if [ "$HOUR" -lt 6 ] || [ "$HOUR" -gt 22 ]; then
    RECENT_LOGINS=$(journalctl --since "1 hour ago" -u sshd | grep "Accepted")
    if [ -n "$RECENT_LOGINS" ]; then
        echo "非工作时间 SSH 登录：

$RECENT_LOGINS" | mail -s "SSH 异常登录 - $(hostname)" "$ALERT_EMAIL"
    fi
fi
```

## 6. SSH 安全加固清单

```bash
#!/bin/bash
# SSH 安全检查脚本

echo "=== SSH 安全检查 ==="

# 检查 SSH 版本
echo "SSH 版本："
ssh -V 2>&1

# 检查配置
echo -e "\n关键配置检查："
grep -E "^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|MaxAuthTries)" /etc/ssh/sshd_config | grep -v "^#"

# 检查是否有弱密钥
echo -e "\n密钥类型检查："
ls -la /etc/ssh/ssh_host_*

# 检查 authorized_keys
echo -e "\nauthorized_keys 内容："
for user_home in /home/*/; do
    if [ -f "${user_home}.ssh/authorized_keys" ]; then
        echo "用户: $(basename $user_home)"
        wc -l "${user_home}.ssh/authorized_keys"
    fi
done

# 检查 SSH 会话
echo -e "\n当前 SSH 会话："
who | grep pts

# 检查近期登录
echo -e "\n最近 10 次登录："
last -10
```

## 7. 生产环境建议

1. **统一使用 Ed25519 密钥**：安全性高，性能好
2. **禁止密码认证**：仅使用公钥 + 2FA
3. **跳板机集中管控**：所有 SSH 访问必须经过跳板机
4. **定期轮换密钥**：每 90 天轮换一次
5. **审计所有操作**：记录所有 SSH 会话和命令
6. **限制来源 IP**：通过防火墙限制 SSH 访问来源
7. **监控异常登录**：实时告警异常登录行为
