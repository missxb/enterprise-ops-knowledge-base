# 云服务器管理 (ECS/EC2)

## 1. 概述

云服务器（阿里云 ECS / AWS EC2）是云计算最基础的计算资源。本文将从实例选型、镜像管理、自动化部署、监控运维、安全加固等维度，全面介绍云服务器的生命周期管理最佳实践。

## 2. 实例选型

### 2.1 选型决策树

```
工作负载类型？
├── 通用 Web/应用 → 通用型 (g7/m6i)
├── 计算密集型 → 计算型 (c7/c6i)
├── 内存密集型 → 内存型 (r7/r6i)
├── GPU 计算 → GPU 型 (gn7/p4d)
├── 高 IO → 存储优化型 (i4i/d3)
└── 开发测试 → 突发性能型 (t7/t4g)
```

### 2.2 规格选择指南

**Web 服务器：**

| 并发用户 | 推荐规格 | 数量 | 月成本估算 |
|----------|----------|------|-----------|
| < 1000 | 2C4G | 2 | ¥300 |
| 1000-5000 | 4C8G | 2-4 | ¥800 |
| 5000-20000 | 8C16G | 4-8 | ¥2,400 |
| > 20000 | 16C32G | 8+ | ¥8,000+ |

**数据库服务器：**

| 数据量 | 推荐规格 | 存储 | 月成本估算 |
|--------|----------|------|-----------|
| < 50GB | 4C16G | 200G SSD | ¥1,200 |
| 50-200GB | 8C32G | 500G ESSD | ¥3,000 |
| 200GB-1TB | 16C64G | 1T ESSD PL1 | ¥8,000 |
| > 1TB | 32C128G | 2T+ ESSD PL2 | ¥20,000+ |

### 2.3 ARM vs x86

ARM 架构（阿里云倚天 / AWS Graviton）正在成为趋势：

**优势：**
- 性价比提升 20-40%
- 更低的功耗
- 生态日趋完善

**兼容性检查：**
```bash
# 检查应用是否支持 ARM
file /usr/bin/myapp
# 输出应包含 "aarch64" 或 "ARM"

# Docker 镜像多架构构建
docker buildx build --platform linux/amd64,linux/arm64 -t myapp:latest .
```

## 3. 镜像管理

### 3.1 自定义镜像构建

使用 Packer 自动化构建标准化镜像：

```json
{
  "variables": {
    "aliyun_access_key": "{{env `ALICLOUD_ACCESS_KEY`}}",
    "aliyun_secret_key": "{{env `ALICLOUD_SECRET_KEY`}}",
    "region": "cn-hangzhou"
  },
  "builders": [
    {
      "type": "alicloud-ecs",
      "access_key": "{{user `aliyun_access_key`}}",
      "secret_key": "{{user `aliyun_secret_key`}}",
      "region": "{{user `region`}}",
      "image_name": "web-server-{{timestamp}}",
      "source_image": "centos_7_9_x64_20G_alibase_20230816.vhd",
      "instance_type": "ecs.g7.large",
      "ssh_username": "root"
    }
  ],
  "provisioners": [
    {
      "type": "shell",
      "scripts": [
        "scripts/base-init.sh",
        "scripts/install-docker.sh",
        "scripts/install-monitoring.sh",
        "scripts/security-hardening.sh"
      ]
    }
  ]
}
```

### 3.2 基础初始化脚本

```bash
#!/bin/bash
# base-init.sh - 基础系统初始化

set -euo pipefail

# 更新系统
yum update -y

# 安装基础工具
yum install -y \
  vim wget curl net-tools \
  htop iotop sysstat \
  tree jq bash-completion

# 配置时区
timedatectl set-timezone Asia/Shanghai

# 配置系统限制
cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF

# 配置内核参数
cat >> /etc/sysctl.conf <<EOF
net.ipv4.tcp_max_syn_backlog = 65535
net.core.somaxconn = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
vm.swappiness = 10
vm.overcommit_memory = 1
EOF
sysctl -p

# 禁用 SELinux
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# 配置 NTP
yum install -y chrony
systemctl enable chronyd
systemctl start chronyd

echo "Base initialization completed."
```

## 4. 自动化部署

### 4.1 Ansible Playbook

```yaml
# deploy-web-app.yml
---
- name: Deploy Web Application
  hosts: web_servers
  become: yes
  vars:
    app_version: "{{ lookup('env', 'APP_VERSION') }}"
    app_port: 8080

  tasks:
    - name: Pull latest application image
      docker_image:
        name: "registry.example.com/web-app:{{ app_version }}"
        source: pull

    - name: Stop current container
      docker_container:
        name: web-app
        state: stopped
      ignore_errors: yes

    - name: Start new container
      docker_container:
        name: web-app
        image: "registry.example.com/web-app:{{ app_version }}"
        state: started
        restart_policy: unless-stopped
        ports:
          - "{{ app_port }}:8080"
        env:
          DB_HOST: "{{ db_host }}"
          REDIS_HOST: "{{ redis_host }}"
          LOG_LEVEL: "info"

    - name: Wait for health check
      uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: 200
      retries: 30
      delay: 5

    - name: Register with SLB
      shell: |
        aliyun slb AddBackendServers \
          --LoadBalancerId {{ slb_id }} \
          --BackendServers '[{"ServerId":"{{ inventory_hostname }}","Weight":"100"}]'
```

### 4.2 蓝绿部署

```
当前环境 (蓝色):                新环境 (绿色):
┌──────────────┐              ┌──────────────┐
│  ECS-1 (v1)  │              │  ECS-1 (v2)  │
│  ECS-2 (v1)  │              │  ECS-2 (v2)  │
│  ECS-3 (v1)  │              │  ECS-3 (v2)  │
└──────┬───────┘              └──────┬───────┘
       │                             │
       └──────────┬──────────────────┘
                  │
            ┌─────▼─────┐
            │    SLB     │
            └───────────┘

切换过程:
1. 部署新版本到绿色环境
2. 健康检查通过
3. SLB 流量切换到绿色环境
4. 蓝色环境保留用于回滚
```

## 5. 监控与告警

### 5.1 系统监控指标

```bash
#!/bin/bash
# collect-metrics.sh - 采集系统指标

# CPU 使用率
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')

# 内存使用率
MEM_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100}')

# 磁盘使用率
DISK_USAGE=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')

# 网络连接数
CONN_COUNT=$(ss -s | grep "estab" | awk '{print $4}')

# 负载
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1}')

echo "CPU: ${CPU_USAGE}%, MEM: ${MEM_USAGE}%, DISK: ${DISK_USAGE}%, CONN: ${CONN_COUNT}, LOAD: ${LOAD_AVG}"
```

### 5.2 关键告警规则

| 指标 | 警告阈值 | 严重阈值 | 持续时间 |
|------|----------|----------|----------|
| CPU 使用率 | > 70% | > 90% | 5 分钟 |
| 内存使用率 | > 80% | > 95% | 5 分钟 |
| 磁盘使用率 | > 75% | > 90% | 10 分钟 |
| 磁盘 IO 等待 | > 20% | > 50% | 5 分钟 |
| 网络丢包率 | > 1% | > 5% | 3 分钟 |
| 系统负载 | > CPU 核数 | > CPU 核数 × 2 | 5 分钟 |

## 6. 安全加固

### 6.1 安全基线检查

```bash
#!/bin/bash
# security-check.sh - 安全基线检查

echo "=== 安全基线检查报告 ==="
echo "检查时间: $(date)"

# 1. SSH 配置检查
echo "--- SSH 配置 ---"
grep -E "^(PermitRootLogin|PasswordAuthentication|Port)" /etc/ssh/sshd_config

# 2. 防火墙状态
echo "--- 防火墙状态 ---"
systemctl status firewalld 2>/dev/null || iptables -L -n | head -20

# 3. 开放端口
echo "--- 开放端口 ---"
ss -tlnp | grep LISTEN

# 4. 用户检查
echo "--- 可登录用户 ---"
grep -E "bash$|sh$" /etc/passwd

# 5. 定时任务检查
echo "--- Root 定时任务 ---"
crontab -l 2>/dev/null || echo "无定时任务"

# 6. 最近登录
echo "--- 最近登录 ---"
last -10

# 7. 文件权限检查
echo "--- 关键文件权限 ---"
ls -la /etc/passwd /etc/shadow /etc/sudoers
```

### 6.2 安全加固清单

- [ ] 禁止 root 直接 SSH 登录
- [ ] 使用密钥认证，禁用密码登录
- [ ] 修改默认 SSH 端口
- [ ] 安装并配置 fail2ban
- [ ] 定期更新系统补丁
- [ ] 最小化安装（不安装不必要的软件）
- [ ] 配置审计日志（auditd）
- [ ] 关闭不必要的服务
- [ ] 配置文件完整性检查（AIDE）

## 7. 成本管理

### 7.1 实例购买策略

```
稳定负载 (7×24):  包年包月 / 预留实例 (节省 30-50%)
工作日负载:       节省计划 / Savings Plans (节省 20-30%)
突发负载:         按量付费 + 自动伸缩
临时任务:         竞价实例 / Spot Instance (节省 60-90%)
```

### 7.2 资源回收

定期清理闲置资源：

```bash
#!/bin/bash
# cleanup-unused-resources.sh

# 查找闲置 ECS 实例（CPU < 5% 持续 7 天）
# 查找未挂载的云盘
# 查找未使用的弹性 IP
# 查找过期的快照

echo "=== 闲置资源清单 ==="

# 未挂载的云盘
aliyun ecs DescribeDisks --Status Available --RegionId cn-hangzhou \
  | jq '.Disks.Disk[] | {DiskId, Size, CreateTime}'

# 未绑定的 EIP
aliyun ecs DescribeEipAddresses --Status Available --RegionId cn-hangzhou \
  | jq '.EipAddresses.EipAddress[] | {AllocationId, IpAddress}'
```

## 8. 总结

云服务器管理的核心要点：

1. **标准化**：使用自定义镜像实现配置一致性
2. **自动化**：部署、监控、告警全部自动化
3. **安全优先**：安全基线必须在上线前完成
4. **成本优化**：合理选择计费方式，定期清理闲置资源
5. **可观测性**：全链路监控，问题早发现早处理
