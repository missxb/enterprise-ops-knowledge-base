# 用户权限管理

## 概述

用户权限管理是系统安全的基础。本文涵盖 sudo 配置、PAM 认证、ACL 访问控制、Linux Capabilities 及生产环境权限管理最佳实践。

## 1. sudo 权限管理

### 1.1 sudoers 配置

```bash
# /etc/sudoers 或 /etc/sudoers.d/ 下的文件
# 注意：必须使用 visudo 编辑，语法错误会导致 sudo 不可用

# 基本语法
# 用户 主机=(身份) 命令

# 用户别名
User_Alias ADMINS = alice, bob, charlie
User_Alias DBAS = david, eve
User_Alias DEVS = frank, grace

# 主机别名
Host_Alias WEBSERVERS = web01, web02, web03
Host_Alias DBSERVERS = db01, db02

# 命令别名
Cmnd_Alias SERVICE_CMDS = /usr/bin/systemctl restart *, /usr/bin/systemctl status *
Cmnd_Alias LOG_CMDS = /usr/bin/tail, /usr/bin/less, /usr/bin/cat /var/log/*
Cmnd_Alias NETWORK_CMDS = /usr/sbin/iptables, /usr/sbin/ip, /usr/bin/ss
Cmnd_Alias USER_CMDS = /usr/sbin/useradd, /usr/sbin/usermod, /usr/sbin/userdel

# 运维团队权限
ADMINS ALL=(ALL) NOPASSWD: ALL

# DBA 权限（仅数据库相关）
DBAS DBSERVERS=(ALL) NOPASSWD: /usr/bin/systemctl restart mysql*, \
    /usr/bin/systemctl status mysql*, \
    /usr/bin/mysql

# 开发者权限（受限）
DEVS WEBSERVERS=(ALL) NOPASSWD: SERVICE_CMDS, LOG_CMDS

# 审计日志
Defaults logfile=/var/log/sudo.log
Defaults log_input, log_output
Defaults iolog_dir=/var/log/sudo-io/%{user}

# 安全设置
Defaults timestamp_timeout=5      # sudo 缓存 5 分钟
Defaults passwd_tries=3           # 密码重试 3 次
Defaults requiretty               # 要求有终端
Defaults use_pty                  # 使用伪终端
```

### 1.2 sudo 审计

```bash
# 查看 sudo 日志
tail -f /var/log/sudo.log

# 查看会话回放
sudoreplay -l                    # 列出所有会话
sudoreplay -f <session_id>       # 回放指定会话

# 搜索 sudo 操作
grep "COMMAND" /var/log/sudo.log
```

## 2. PAM 认证配置

### 2.1 PAM 模块基础

```bash
# PAM 配置文件：/etc/pam.d/
# 配置格式：type control module [options]

# type 类型
# auth     - 认证（验证用户身份）
# account  - 账户（检查账户有效性）
# password - 密码（修改密码规则）
# session  - 会话（会话管理）

# control 类型
# required   - 必须通过，失败继续检查
# requisite  - 必须通过，失败立即返回
# sufficient - 成功则通过，失败继续
# optional   - 可选
```

### 2.2 密码策略配置

```bash
# /etc/pam.d/system-auth 或 /etc/pam.d/common-password

# 密码复杂度（pam_pwquality）
password requisite pam_pwquality.so \
    minlen=12 \
    dcredit=-1 \
    ucredit=-1 \
    lcredit=-1 \
    ocredit=-1 \
    minclass=3 \
    maxrepeat=3 \
    maxclassrepeat=4 \
    dictcheck=1 \
    enforce_for_root

# 密码历史（pam_pwhistory）
password required pam_pwhistory.so remember=5 use_authtok

# 密码过期
# /etc/login.defs
PASS_MAX_DAYS   90      # 密码最长有效期
PASS_MIN_DAYS   7       # 密码最短更改间隔
PASS_MIN_LEN    12      # 密码最小长度
PASS_WARN_AGE   14      # 过期前提醒天数
```

### 2.3 登录限制

```bash
# /etc/pam.d/sshd

# 登录失败锁定（pam_faillock）
auth required pam_faillock.so preauth silent deny=5 unlock_time=900 fail_interval=900
auth [default=die] pam_faillock.so authfail deny=5 unlock_time=900 fail_interval=900
account required pam_faillock.so

# 限制 root 远程登录
auth required pam_securetty.so

# 限制登录时间
account required pam_time.so

# 资源限制
session required pam_limits.so

# 登录审计
session required pam_loginuid.so
session required pam_lastlog.so showfailed
```

### 2.4 双因素认证

```bash
# /etc/pam.d/sshd
# Google Authenticator
auth required pam_google_authenticator.so nullok

# /etc/ssh/sshd_config
ChallengeResponseAuthentication yes
AuthenticationMethods publickey,keyboard-interactive
```

## 3. ACL 访问控制

### 3.1 ACL 基础操作

```bash
# 查看 ACL
getfacl /path/to/file

# 设置 ACL
# 基本 ACL
setfacl -m u:alice:rwx /data/project
setfacl -m g:developers:rx /data/project

# 默认 ACL（新建文件自动继承）
setfacl -d -m g:developers:rwx /data/project

# 递归设置
setfacl -R -m g:developers:rwx /data/project

# 删除 ACL
setfacl -x u:alice /data/project    # 删除特定条目
setfacl -b /data/project             # 删除所有 ACL

# 备份和恢复 ACL
getfacl -R /data/project > acl_backup.txt
setfacl --restore=acl_backup.txt
```

### 3.2 ACL 最佳实践

```bash
# 场景：开发团队共享目录
# 需求：开发组读写，测试组只读，运维完全控制

# 创建共享目录
mkdir -p /data/shared/project
chown root:root /data/shared/project
chmod 770 /data/shared/project

# 设置 ACL
setfacl -m g:ops:rwx /data/shared/project
setfacl -m g:dev:rwx /data/shared/project
setfacl -m g:qa:rx /data/shared/project

# 默认 ACL（新建文件自动继承权限）
setfacl -d -m g:ops:rwx /data/shared/project
setfacl -d -m g:dev:rwx /data/shared/project
setfacl -d -m g:qa:rx /data/shared/project

# 验证
getfacl /data/shared/project
```

## 4. Linux Capabilities

### 4.1 Capabilities 概述

```bash
# 传统模型：root 拥有所有权限
# Capabilities 模型：将 root 权限细分为独立的能力

# 常用 Capabilities
# CAP_NET_BIND_SERVICE - 绑定 1024 以下端口
# CAP_NET_RAW          - 使用原始套接字
# CAP_SYS_ADMIN        - 系统管理操作
# CAP_DAC_OVERRIDE     - 绕过文件权限检查
# CAP_CHOWN            - 修改文件所有者
# CAP_SETUID/CAP_SETGID - 设置 UID/GID
# CAP_SYS_PTRACE       - 跟踪进程
# CAP_DAC_READ_SEARCH  - 绕过文件读取权限
```

### 4.2 Capabilities 管理

```bash
# 查看文件 Capabilities
getcap /usr/bin/ping
# /usr/bin/ping = cap_net_raw+ep

# 设置文件 Capabilities
setcap cap_net_bind_service=ep /usr/local/bin/myapp

# 查看进程 Capabilities
getpcaps $PID

# 通过 Capabilities 让普通用户绑定特权端口
setcap 'cap_net_bind_service=+ep' /opt/myapp/bin/server

# 删除 Capabilities
setcap -r /opt/myapp/bin/server

# 安全搜索带 Capabilities 的文件
getcap -r / 2>/dev/null
```

### 4.3 systemd 服务 Capabilities

```ini
# /etc/systemd/system/myapp.service
[Service]
# 限制 Capabilities
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_BIND_SERVICE

# 降权运行
User=myapp
Group=myapp
NoNewPrivileges=true

# 安全限制
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
```

## 5. 文件权限与特殊位

### 5.1 特殊权限位

```bash
# SUID (4000) - 以文件所有者身份执行
chmod u+s /usr/bin/passwd
chmod 4755 /usr/bin/passwd

# SGID (2000) - 以文件所属组身份执行/目录下新建文件继承组
chmod g+s /data/shared/
chmod 2775 /data/shared/

# Sticky Bit (1000) - 目录内文件只有所有者能删除
chmod +t /tmp
chmod 1777 /tmp

# 查找 SUID/SGID 文件（安全审计）
find / -perm -4000 -type f 2>/dev/null
find / -perm -2000 -type f 2>/dev/null
```

### 5.2 文件属性（chattr）

```bash
# 不可修改
chattr +i /etc/passwd
chattr +i /etc/shadow

# 仅追加
chattr +a /var/log/messages

# 安全删除
chattr +s /tmp/secret

# 查看属性
lsattr /etc/passwd

# 常用属性
# a - 仅追加
# i - 不可修改
# s - 安全删除
# S - 同步写入
# u - 不可删除
```

## 6. 生产环境权限管理实践

### 6.1 最小权限原则

```bash
# 1. 服务运行用户分离
useradd -r -s /sbin/nologin nginx
useradd -r -s /sbin/nologin mysql
useradd -r -s /sbin/nologin myapp

# 2. 目录权限规划
/data/
├── app/           # myapp:myapp 750
├── logs/          # myapp:logviewers 750
├── config/        # root:myapp 750
├── tmp/           # myapp:myapp 1777
└── backup/        # backup:backup 700

# 3. 使用 ACL 进行精细权限控制
setfacl -d -m g:logviewers:r /data/logs/
```

### 6.2 权限审计脚本

```bash
#!/bin/bash
# 权限审计脚本

echo "=== SUID/SGID 文件检查 ==="
find / -perm -4000 -type f -exec ls -la {} \; 2>/dev/null
find / -perm -2000 -type f -exec ls -la {} \; 2>/dev/null

echo "=== 全局可写文件检查 ==="
find / -xdev -perm -o+w -type f ! -path "/proc/*" ! -path "/sys/*" 2>/dev/null

echo "=== 无主文件检查 ==="
find / -xdev \( -nouser -o -nogroup \) -exec ls -la {} \; 2>/dev/null

echo "=== /etc/passwd 与 /etc/shadow 一致性 ==="
diff <(awk -F: '{print $1}' /etc/passwd | sort) \
     <(awk -F: '{print $1}' /etc/shadow | sort)

echo "=== 空密码账户检查 ==="
awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow

echo "=== UID 0 账户检查 ==="
awk -F: '$3 == 0 {print $1}' /etc/passwd
```

### 6.3 权限变更审批流程

1. **申请**：提交权限变更申请，说明原因和范围
2. **审批**：安全团队或直属领导审批
3. **实施**：运维团队按审批内容实施
4. **验证**：申请人验证权限是否满足需求
5. **审计**：定期审计权限变更记录
6. **回收**：不再需要的权限及时回收

## 7. 安全加固清单

- [ ] 禁用 root 远程登录
- [ ] 配置 sudo 日志审计
- [ ] 设置密码复杂度策略
- [ ] 配置登录失败锁定
- [ ] 定期检查 SUID/SGID 文件
- [ ] 清理无用的用户账户
- [ ] 使用 ACL 实现精细权限控制
- [ ] 服务以最小权限运行
- [ ] 定期审计权限配置
- [ ] 建立权限变更审批流程
