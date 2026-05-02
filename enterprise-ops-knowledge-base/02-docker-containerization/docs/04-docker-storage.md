# Docker 存储 (Volume/Bind/NFS)

## 1. 存储类型概述

Docker 提供三种数据持久化方式，各有适用场景：

| 类型 | 管理方式 | 性能 | 适用场景 |
|------|----------|------|----------|
| Volume | Docker 管理 | ★★★★ | 生产数据持久化 |
| Bind Mount | 用户管理 | ★★★★★ | 开发环境、配置文件 |
| tmpfs | 内存 | ★★★★★ | 临时敏感数据 |

### 1.1 存储架构

```
┌─────────────────────────────────────────────┐
│              Docker Host                     │
│                                             │
│  /var/lib/docker/volumes/                   │
│  ├── db-data/          ← Named Volume       │
│  │   └── _data/                              │
│  │       ├── postgres/                      │
│  │       └── pg_wal/                         │
│  └── app-logs/          ← Named Volume       │
│      └── _data/                              │
│          └── *.log                           │
│                                             │
│  /opt/app/config/       ← Bind Mount        │
│  ├── application.yml                         │
│  └── logback.xml                             │
│                                             │
│  ┌─────────────────┐                        │
│  │   Container      │                        │
│  │  /var/lib/postgres/data → Volume          │
│  │  /app/config     → Bind Mount             │
│  │  /tmp/secrets     → tmpfs (RAM)           │
│  └─────────────────┘                        │
└─────────────────────────────────────────────┘
```

## 2. Volume 管理

### 2.1 基本操作

```bash
# 创建卷
docker volume create my-data

# 列出所有卷
docker volume ls

# 查看卷详情
docker volume inspect my-data
# [
#   {
#     "CreatedAt": "2024-01-15T10:30:00Z",
#     "Driver": "local",
#     "Labels": {},
#     "Mountpoint": "/var/lib/docker/volumes/my-data/_data",
#     "Name": "my-data",
#     "Options": {},
#     "Scope": "local"
#   }
# ]

# 使用卷
docker run -d --name db -v my-data:/var/lib/postgresql/data postgres:15

# 只读挂载
docker run -d -v my-data:/data:ro nginx:alpine

# 删除卷
docker volume rm my-data

# 清理未使用的卷
docker volume prune
```

### 2.2 Volume Driver

```bash
# 使用 NFS 卷驱动
docker volume create \
  --driver local \
  --opt type=nfs \
  --opt o=addr=192.168.1.100,rw,nfsvers=4 \
  --opt device=:/data/shared \
  nfs-data

# 使用 CIFS/SMB 卷驱动
docker volume create \
  --driver local \
  --opt type=cifs \
  --opt device=//192.168.1.100/share \
  --opt o=username=user,password=pass \
  smb-data

# 使用第三方驱动（如 Convoy、REX-Ray）
# docker plugin install rexray/ebs
# docker volume create --driver rexray/ebs --opt size=10 ebs-vol
```

## 3. Bind Mount

### 3.1 基本用法

```bash
# 挂载宿主机目录
docker run -d -v /opt/app/config:/app/config nginx:alpine

# 使用绝对路径（推荐）
docker run -d -v $(pwd)/html:/usr/share/nginx/html nginx:alpine

# SELinux 环境需要 :z 或 :Z 标志
docker run -d -v /opt/app/data:/data:z nginx:alpine
# :z - 共享挂载（多个容器可访问）
# :Z - 私有挂载（仅当前容器可访问）
```

### 3.2 Bind Mount vs Volume 选择

```bash
# 开发环境 - 使用 Bind Mount（实时同步代码）
docker run -d \
  -v $(pwd)/src:/app/src \
  -v $(pwd)/package.json:/app/package.json \
  node:20-alpine npm run dev

# 生产环境 - 使用 Volume（Docker 管理，更安全）
docker run -d \
  -v app-data:/app/data \
  myapp:production
```

## 4. tmpfs 挂载

```bash
# tmpfs 挂载数据存储在内存中，容器停止后数据消失
# 适用于敏感数据（密钥、Token）或临时缓存

docker run -d \
  --tmpfs /tmp:rw,size=100m,mode=1777 \
  --tmpfs /run:rw,size=50m \
  nginx:alpine

# 使用 --mount 语法（更明确）
docker run -d \
  --mount type=tmpfs,target=/tmp,tmpfs-size=100m \
  myapp:latest
```

## 5. NFS 集成

### 5.1 NFS 服务端配置

```bash
# 在 NFS 服务器上
sudo apt install nfs-kernel-server

# 创建共享目录
sudo mkdir -p /data/docker-volumes
sudo chown nobody:nogroup /data/docker-volumes

# 配置导出
echo "/data/docker-volumes 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)" | \
  sudo tee -a /etc/exports

sudo exportfs -a
sudo systemctl restart nfs-kernel-server
```

### 5.2 Docker 使用 NFS

```bash
# 方式1：创建 NFS 卷
docker volume create \
  --driver local \
  --opt type=nfs \
  --opt o=addr=10.0.0.100,rw,hard,nfsvers=4.1,timeo=600,retrans=2 \
  --opt device=:/data/docker-volumes \
  shared-data

# 方式2：直接挂载
docker run -d \
  --mount type=volume,source=shared-data,target=/data \
  myapp:latest

# 方式3：在 compose 中使用
# volumes:
#   shared-data:
#     driver: local
#     driver_opts:
#       type: nfs
#       o: addr=10.0.0.100,rw,hard,nfsvers=4.1
#       device: ":/data/docker-volumes"
```

## 6. 数据备份与恢复

### 6.1 Volume 备份

```bash
# 使用临时容器备份卷数据
docker run --rm \
  -v my-data:/source:ro \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/my-data-$(date +%Y%m%d).tar.gz -C /source .

# 恢复卷数据
docker run --rm \
  -v my-data:/target \
  -v $(pwd)/backups:/backup:ro \
  alpine sh -c "cd /target && tar xzf /backup/my-data-20240115.tar.gz"

# 使用 rsync 增量备份
docker run --rm \
  -v my-data:/source:ro \
  -v /backup/volumes:/backup \
  alpine rsync -av --delete /source/ /backup/my-data/
```

### 6.2 数据库备份案例

```bash
# PostgreSQL 备份
docker exec -t postgres-container pg_dumpall -U postgres > backup_$(date +%Y%m%d).sql

# MySQL 备份
docker exec mysql-container mysqldump -u root -p --all-databases > backup_$(date +%Y%m%d).sql

# 使用卷备份
docker run --rm \
  -v pg-data:/var/lib/postgresql/data:ro \
  -v $(pwd)/backups:/backup \
  postgres:15 bash -c "cd /var/lib/postgresql/data && tar czf /backup/pg-data.tar.gz ."
```

## 7. 存储性能优化

### 7.1 存储驱动选择

```bash
# overlay2 性能对比测试
docker run --rm -it alpine sh -c "
  echo '=== Sequential Write ==='
  dd if=/dev/zero of=/tmp/test bs=1M count=1024 oflag=direct 2>&1
  echo '=== Sequential Read ==='
  dd if=/tmp/test of=/dev/null bs=1M iflag=direct 2>&1
  rm /tmp/test
"

# Volume vs Bind Mount 性能测试
# Volume 通常比 Bind Mount 在 macOS/Windows 上性能更好
# Linux 上两者性能接近
```

### 7.2 I/O 调度优化

```bash
# 限制容器 I/O
docker run -d \
  --device-read-bps /dev/sda:100mb \
  --device-write-bps /dev/sda:50mb \
  --device-read-iops /dev/sda:1000 \
  --device-write-iops /dev/sda:500 \
  myapp:latest

# 使用 blkio cgroup
docker run -d --blkio-weight 500 myapp:latest
# 权重范围 10-1000，默认 500
```

## 8. 生产案例

### 案例1：数据库持久化

```bash
# PostgreSQL 生产配置
docker volume create pg-data
docker volume create pg-wal
docker volume create pg-backup

docker run -d \
  --name postgres \
  --restart unless-stopped \
  -v pg-data:/var/lib/postgresql/data \
  -v pg-wal:/var/lib/postgresql/pg_wal \
  -v pg-backup:/backup \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/db_password \
  -p 5432:5432 \
  --memory 4g \
  --cpus 2 \
  postgres:15 \
  postgres \
    -c shared_buffers=1GB \
    -c effective_cache_size=3GB \
    -c wal_buffers=16MB \
    -c max_connections=200
```

### 案例2：多环境配置管理

```bash
# 使用 Bind Mount 管理不同环境的配置
# 开发环境
docker run -d \
  -v $(pwd)/config/dev:/app/config \
  -v $(pwd)/src:/app/src \
  myapp:dev

# 测试环境
docker run -d \
  -v /opt/app/config/test:/app/config \
  myapp:test

# 生产环境
docker run -d \
  -v /opt/app/config/prod:/app/config:ro \
  myapp:production
```

### 案例3：日志收集

```bash
# 使用命名卷存储日志，配合日志收集器
docker volume create app-logs

# 应用容器写日志到卷
docker run -d \
  -v app-logs:/var/log/app \
  myapp:latest

# Filebeat 容器收集日志
docker run -d \
  -v app-logs:/var/log/app:ro \
  -v $(pwd)/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro \
  docker.elastic.co/beats/filebeat:8.11.0
```

## 9. 常见问题

### 问题1：权限问题

```bash
# 容器内用户 UID 与宿主机文件 UID 不匹配
# 解决方案1：在 Dockerfile 中创建匹配的用户
RUN useradd -u 1000 -m appuser

# 解决方案2：使用 --user 指定 UID
docker run --user 1000:1000 -v /data:/app/data myapp

# 解决方案3：修改宿主机文件权限
sudo chown -R 1000:1000 /opt/app/data
```

### 问题2：磁盘空间不足

```bash
# 查看 Docker 磁盘使用
docker system df
docker system df -v

# 清理策略
docker container prune -f    # 清理停止的容器
docker image prune -a -f     # 清理未使用的镜像
docker volume prune -f       # 清理未使用的卷
docker system prune -a -f    # 清理所有未使用资源

# 设置日志轮转
# /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
```
