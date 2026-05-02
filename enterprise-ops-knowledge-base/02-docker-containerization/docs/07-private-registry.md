# 私有镜像仓库 Harbor

## 概述

Harbor 是由 VMware 开源的企业级 Docker 镜像仓库，提供了镜像存储、安全扫描、访问控制、审计日志等企业级功能。相比 Docker 官方 Registry，Harbor 增加了权限管理、镜像复制、漏洞扫描、LDAP/AD 集成等关键特性，是生产环境中最广泛使用的私有镜像仓库方案。

## 一、架构设计

### 1.1 核心组件

Harbor 由以下核心组件构成：

| 组件 | 功能 |
|------|------|
| **Core** | 核心 API 服务，处理项目管理、用户认证、配额管理等 |
| **Portal** | Web UI 前端界面 |
| **Registry** | Docker Distribution，负责镜像存储和分发 |
| **Database (PostgreSQL)** | 存储项目、用户、权限、审计等元数据 |
| **Redis** | 缓存和会话存储 |
| **Job Service** | 异步任务处理，如镜像复制、垃圾回收、漏洞扫描 |
| **Trivy Adapter** | 镜像漏洞扫描适配器 |
| **Notary**（可选） | 镜像签名和信任验证 |
| **Chartmuseum**（可选） | Helm Chart 仓库 |

### 1.2 架构图

```
                    ┌──────────────┐
                    │   Nginx/HA   │
                    │  (反向代理)   │
                    └──────┬───────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
    ┌─────┴─────┐   ┌─────┴─────┐   ┌─────┴─────┐
    │  Portal   │   │   Core    │   │ Registry  │
    │  (Web UI) │   │  (API)    │   │  (存储)   │
    └───────────┘   └─────┬─────┘   └───────────┘
                          │
            ┌─────────────┼─────────────┐
            │             │             │
      ┌─────┴─────┐ ┌────┴────┐ ┌─────┴─────┐
      │PostgreSQL │ │  Redis  │ │Job Service│
      │  (元数据) │ │ (缓存)  │ │ (异步任务)│
      └───────────┘ └─────────┘ └───────────┘
```

## 二、安装部署

### 2.1 环境要求

| 资源 | 最低要求 | 推荐配置 |
|------|---------|---------|
| CPU | 2 核 | 4 核+ |
| 内存 | 4 GB | 8 GB+ |
| 磁盘 | 40 GB | 200 GB+ (SSD) |
| 操作系统 | CentOS 7+/Ubuntu 16.04+ | CentOS 8/Ubuntu 20.04+ |
| Docker | 20.10+ | 最新稳定版 |
| Docker Compose | 2.0+ | 最新稳定版 |
| Python | 3.7+ | 3.9+ |

### 2.2 离线安装（推荐生产环境）

```bash
# 1. 下载离线安装包
HARBOR_VERSION=v2.10.0
wget https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-offline-installer-${HARBOR_VERSION}.tgz

# 2. 解压
tar xvf harbor-offline-installer-${HARBOR_VERSION}.tgz
cd harbor

# 3. 复制配置模板
cp harbor.yml.tmpl harbor.yml

# 4. 编辑配置
vim harbor.yml
```

### 2.3 核心配置文件 harbor.yml

```yaml
# 访问地址配置
hostname: harbor.example.com

# HTTPS 配置（生产必须启用）
https:
  port: 443
  certificate: /data/cert/harbor.crt
  private_key: /data/cert/harbor.key

# 管理员初始密码（首次登录后务必修改）
harbor_admin_password: Harbor12345

# 数据库配置
database:
  password: root123
  max_idle_conns: 100
  max_open_conns: 900
  conn_max_lifetime: 5m
  conn_max_idle_time: 0

# 数据存储路径
data_volume: /data/harbor

# 镜像存储配置
storage_service:
  s3:
    accesskey: <your-access-key>
    secretkey: <your-secret-key>
    region: cn-hangzhou
    bucket: harbor-registry
    regionendpoint: oss-cn-hangzhou.aliyuncs.com
  redirect:
    disabled: false

# 日志配置
log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor

# 镜像复制并发数
jobservice:
  max_job_workers: 10

# Trivy 漏洞扫描
trivy:
  ignore_unfixed: false
  skip_update: false
  insecure: false

# 镜像保留策略
# 在 Web UI 中配置项目级别的保留策略
```

### 2.4 执行安装

```bash
# 安装并启动
sudo ./install.sh --with-trivy --with-chartmuseum

# 验证安装
docker compose ps

# 查看日志
docker compose logs -f core
```

### 2.5 配置 HTTPS 证书

```bash
# 生成自签名证书（测试环境）
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
  -nodes -keyout harbor.key -out harbor.crt \
  -subj "/CN=harbor.example.com" \
  -addext "subjectAltName=DNS:harbor.example.com,IP:192.168.1.100"

# 创建证书目录
mkdir -p /data/cert
cp harbor.crt harbor.key /data/cert/

# 客户端信任证书
sudo mkdir -p /etc/docker/certs.d/harbor.example.com
sudo cp harbor.crt /etc/docker/certs.d/harbor.example.com/ca.crt
sudo systemctl restart docker
```

### 2.6 Let's Encrypt 自动证书（生产推荐）

```bash
# 安装 certbot
apt install certbot -y

# 申请证书
certbot certonly --standalone -d harbor.example.com

# 配置 harbor.yml 使用 Let's Encrypt 证书
# certificate: /etc/letsencrypt/live/harbor.example.com/fullchain.pem
# private_key: /etc/letsencrypt/live/harbor.example.com/privkey.pem

# 配置自动续期
echo "0 0 1 * * root certbot renew --pre-hook 'cd /opt/harbor && docker compose down' --post-hook 'cd /opt/harbor && docker compose up -d'" > /etc/cron.d/certbot-renew
```

## 三、权限管理

### 3.1 项目级别权限

Harbor 支持以下项目角色：

| 角色 | 权限说明 |
|------|---------|
| **项目管理员** | 管理项目成员、配置、标签、Webhook 等 |
| **维护人员** | 推送/拉取镜像、扫描漏洞、打标签、创建 Helm Chart |
| **开发者** | 推送/拉取镜像、创建标签 |
| **访客** | 只读访问，拉取镜像 |
| **受限访客** | 仅拉取镜像，无法查看日志和成员列表 |

### 3.2 LDAP/AD 集成

```yaml
# harbor.yml 中 LDAP 配置
auth_mode: ldap_auth

ldap:
  url: ldap://ldap.example.com:389
  search_dn: cn=admin,dc=example,dc=com
  search_password: ldap_password
  base_dn: ou=users,dc=example,dc=com
  filter: (objectClass=person)
  uid: uid
  scope: 2  # subtree
  timeout: 5
  verify_cert: true
  group_search_dn: ou=groups,dc=example,dc=com
  group_search_filter: (objectClass=groupOfNames)
  group_attribute_name: member
  group_admin_dn: cn=harbor_admins,ou=groups,dc=example,dc=com
```

### 3.3 RBAC 自定义权限

```bash
# 通过 API 创建自定义角色
curl -X POST "https://harbor.example.com/api/v2.0/roles" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{
    "role_name": "image-promoter",
    "creation_time": "2024-01-01T00:00:00Z",
    "update_time": "2024-01-01T00:00:00Z"
  }'
```

### 3.4 机器人账户

```bash
# 创建项目机器人账户（用于 CI/CD）
curl -X POST "https://harbor.example.com/api/v2.0/projects/myproject/robots" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{
    "name": "ci-bot",
    "description": "CI/CD Pipeline Robot",
    "duration": 30,
    "level": "project",
    "permissions": [{
      "namespace": "myproject",
      "kind": "project",
      "access": [
        {"resource": "repository", "action": "push"},
        {"resource": "repository", "action": "pull"},
        {"resource": "artifact", "action": "read"},
        {"resource": "scan", "action": "create"}
      ]
    }]
  }'
```

## 四、高可用部署

### 4.1 共享存储方案

最简单的高可用方案，使用共享存储（NFS/CephFS）作为后端存储：

```
┌──────────────┐    ┌──────────────┐
│ Harbor Node1 │    │ Harbor Node2 │
│   (Active)   │    │  (Standby)   │
└──────┬───────┘    └──────┬───────┘
       │                    │
       └────────┬───────────┘
                │
        ┌───────┴───────┐
        │  PostgreSQL   │
        │  (主从复制)    │
        │  Redis Cluster │
        │  共享存储(NFS) │
        └───────────────┘
```

### 4.2 基于对象存储的高可用

```yaml
# harbor.yml - 使用 S3/OSS 作为存储后端
storage_service:
  s3:
    accesskey: <ACCESS_KEY>
    secretkey: <SECRET_KEY>
    region: cn-hangzhou
    bucket: harbor-registry
    regionendpoint: oss-cn-hangzhou.aliyuncs.com
    encrypt: true
    secure: true
  redirect:
    disabled: false  # 启用重定向，减少 Harbor 中转流量
```

### 4.3 Kubernetes 部署（Operator 方式）

```yaml
# harbor-cluster.yaml
apiVersion: goharbor.io/v1beta1
kind: HarborCluster
metadata:
  name: harbor-cluster
  namespace: harbor
spec:
  version: 2.10.0
  publicURL: https://harbor.example.com
  tls:
    enabled: true
    certificateRef: harbor-tls
  database:
    kind: ZlandoPostgreSQL
    spec:
      replicas: 3
      storage: 10Gi
  redis:
    kind: Redis
    spec:
      replicas: 3
  storage:
    kind: S3
    spec:
      bucket: harbor-registry
      region: cn-hangzhou
  trivy:
    skipUpdate: false
  chartMuseum:
    enabled: true
```

### 4.4 数据库高可用

```bash
# PostgreSQL 主从配置
# 主库 postgresql.conf
wal_level = replica
max_wal_senders = 10
wal_keep_size = 1GB

# 主库 pg_hba.conf
host replication replicator 192.168.1.0/24 md5

# 从库配置 standby.signal
standby_mode = 'on'
primary_conninfo = 'host=192.168.1.10 port=5432 user=replicator password=xxx'
```

## 五、镜像复制

### 5.1 跨数据中心复制

在 Harbor 管理界面中配置复制规则：

1. **目标管理**：添加目标 Harbor 实例
2. **复制规则**：配置源项目到目标项目的映射
3. **触发方式**：支持事件触发、定时触发、手动触发

```bash
# 通过 API 创建复制规则
curl -X POST "https://harbor.example.com/api/v2.0/replication/policies" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{
    "name": "replicate-to-dr",
    "src_registry": {"id": 0},
    "dest_registry": {"id": 1},
    "trigger": {
      "type": "event_based",
      "trigger_settings": {}
    },
    "filters": [{
      "type": "name",
      "value": "myproject/**"
    }, {
      "type": "tag",
      "value": "v*"
    }],
    "enabled": true,
    "override": true,
    "speed": -1,
    "copy_by_chunk": true
  }'
```

### 5.2 从 Docker Hub 同步

```bash
# 添加 Docker Hub 为外部仓库
# 在 Web UI: 仓库管理 -> 新建目标
# 类型: Docker Hub
# URL: https://hub.docker.com
# 填写 Docker Hub 凭据

# 创建同步规则，拉取公共镜像到私有仓库
curl -X POST "https://harbor.example.com/api/v2.0/replication/policies" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{
    "name": "sync-from-dockerhub",
    "src_registry": {"id": 1},
    "dest_registry": {"id": 0},
    "trigger": {
      "type": "scheduled",
      "trigger_settings": {
        "cron": "0 0 2 * * *"
      }
    },
    "filters": [{
      "type": "name",
      "value": "library/nginx"
    }],
    "enabled": true
  }'
```

## 六、垃圾回收

### 6.1 垃圾回收原理

当镜像被删除后，实际的存储层数据并不会立即释放。Harbor 使用标记-清除（Mark-Sweep）算法进行垃圾回收：

1. **标记阶段**：扫描所有项目，标记仍在使用的 Blob
2. **清除阶段**：删除未被标记的 Blob，释放存储空间

### 6.2 执行垃圾回收

```bash
# 通过 Web UI：系统管理 -> 垃圾回收 -> 立即运行

# 通过 API 执行
curl -X POST "https://harbor.example.com/api/v2.0/system/gc/schedule" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{
    "parameters": {
      "delete_untagged": true,
      "dry_run": false,
      "redis_url": "redis://redis:6379/1",
      "time_window": "2:00-4:00"
    },
    "schedule": {
      "type": "Weekly",
      "cron": "0 0 2 * * 0"
    }
  }'
```

### 6.3 垃圾回收优化

```bash
# 生产环境建议在低峰期执行
# 配置定时任务，每周日凌晨 2 点执行
# 勾选"删除未打标签的镜像"选项

# 监控 GC 日志
docker compose logs -f jobservice | grep "gc"

# 查看存储使用情况
du -sh /data/harbor/registry/docker/registry/v2/
```

### 6.4 存储配额管理

```bash
# 设置项目存储配额
curl -X PUT "https://harbor.example.com/api/v2.0/projects/1/metadatas" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{
    "storage_per_project": "-1"  # 不限制（KB），设置正整数限制
  }'

# 通过 API 查询项目配额使用情况
curl -X GET "https://harbor.example.com/api/v2.0/projects/1/quotas" \
  -u "admin:Harbor12345"
```

## 七、安全配置

### 7.1 镜像签名（Notary）

```bash
# 启用内容信任
export DOCKER_CONTENT_TRUST=1
export DOCKER_CONTENT_TRUST_SERVER=https://harbor.example.com:4443

# 推送签名镜像
docker push harbor.example.com/myproject/myapp:v1.0
```

### 7.2 安全策略配置

```bash
# 禁止拉取未扫描的镜像
# 项目配置 -> 漏洞策略 -> 阻止镜像漏洞等级大于"中危"

# 配置镜像保留策略
# 项目配置 -> 标签保留 -> 保留最近 10 个标签

# 配置 Webhook 通知
curl -X POST "https://harbor.example.com/api/v2.0/projects/1/webhooks" \
  -H "Content-Type: application/json" \
  -u "admin:Harbor12345" \
  -d '{
    "name": "slack-notify",
    "targets": [{
      "type": "http",
      "address": "https://hooks.slack.com/services/xxx/yyy/zzz",
      "auth_header": ""
    }],
    "event_types": [
      "PUSH_ARTIFACT",
      "PULL_ARTIFACT",
      "DELETE_ARTIFACT",
      "SCANNING_FAILED",
      "SCANNING_COMPLETED"
    ],
    "enabled": true
  }'
```

## 八、日常运维

### 8.1 备份策略

```bash
#!/bin/bash
# harbor-backup.sh - Harbor 备份脚本

BACKUP_DIR="/backup/harbor/$(date +%Y%m%d_%H%M%S)"
HARBOR_DIR="/opt/harbor"
mkdir -p "$BACKUP_DIR"

# 备份数据库
docker exec -t harbor-db pg_dumpall -U postgres > "$BACKUP_DIR/harbor_db.sql"

# 备份配置文件
cp -r "$HARBOR_DIR/harbor.yml" "$BACKUP_DIR/"
cp -r "$HARBOR_DIR/docker-compose.yml" "$BACKUP_DIR/"

# 备份证书
cp -r /data/cert "$BACKUP_DIR/certs/"

# 备份镜像数据（如果有 NFS/共享存储可跳过）
# tar czf "$BACKUP_DIR/registry_data.tar.gz" /data/harbor/registry/

echo "Harbor backup completed: $BACKUP_DIR"
```

### 8.2 升级流程

```bash
# 1. 备份
./harbor-backup.sh

# 2. 停止服务
cd /opt/harbor
docker compose down

# 3. 下载新版本
HARBOR_VERSION=v2.11.0
wget https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-offline-installer-${HARBOR_VERSION}.tgz
tar xvf harbor-offline-installer-${HARBOR_VERSION}.tgz
cd harbor

# 4. 迁移配置
cp /opt/harbor/harbor.yml ./harbor.yml

# 5. 执行升级
./install.sh --with-trivy

# 6. 验证
docker compose ps
curl -s https://harbor.example.com/api/v2.0/health | jq .
```

### 8.3 监控告警

```bash
# Harbor 暴露 Prometheus 指标
# 默认地址: http://harbor.example.com:9090/metrics

# 关键监控指标
# harbor_project_total - 项目总数
# harbor_artifact_pulled - 镜像拉取次数
# harbor_project_quota_usage_byte - 项目配额使用量
# harbor_health - 系统健康状态

# Prometheus 配置
cat >> prometheus.yml << 'EOF'
  - job_name: 'harbor'
    metrics_path: /metrics
    static_configs:
      - targets: ['harbor.example.com:9090']
EOF
```

## 九、故障排查

### 9.1 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 推送镜像 403 | 权限不足或 Token 过期 | 检查用户角色，重新 docker login |
| 推送镜像 timeout | Nginx 超时配置 | 增大 proxy_read_timeout |
| GC 后空间未释放 | 底层存储延迟 | 等待或重启 Registry |
| 扫描失败 | Trivy 数据库更新失败 | 检查网络，手动更新 Trivy DB |
| 登录 502 | Core 服务异常 | 检查 Core 日志，重启服务 |

```bash
# 查看各组件日志
docker compose logs -f core
docker compose logs -f registry
docker compose logs -f jobservice
docker compose logs -f trivy-adapter

# 检查服务健康状态
curl -s https://harbor.example.com/api/v2.0/health | python3 -m json.tool

# 检查数据库连接
docker exec -it harbor-db psql -U postgres -d registry -c "SELECT count(*) FROM harbor_user;"
```

## 十、最佳实践

1. **生产环境必须启用 HTTPS**，使用受信任的 CA 证书
2. **定期执行垃圾回收**，建议每周一次，在业务低峰期执行
3. **配置镜像保留策略**，避免镜像无限增长
4. **启用漏洞扫描**，阻断高危镜像部署
5. **配置 Webhook**，及时获取镜像推送/拉取通知
6. **定期备份数据库和配置**，至少每天一次
7. **使用机器人账户**进行 CI/CD 集成，避免使用管理员账户
8. **配置存储配额**，防止个别项目占用过多存储
9. **启用审计日志**，满足合规要求
10. **多数据中心使用镜像复制**，确保镜像高可用
