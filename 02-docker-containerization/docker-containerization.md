# Docker容器化实战完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. 环境准备与依赖说明](#2-环境准备与依赖说明)
- [3. Dockerfile最佳实践](#3-dockerfile最佳实践)
- [4. Docker Compose编排](#4-docker-compose编排)
- [5. 私有镜像仓库Harbor](#5-私有镜像仓库harbor)
- [6. 容器网络模式详解](#6-容器网络模式详解)
- [7. 存储驱动与数据持久化](#7-存储驱动与数据持久化)
- [8. Docker安全](#8-docker安全)
- [9. 容器化现有应用](#9-容器化现有应用)
- [10. 生产环境运维](#10-生产环境运维)
- [11. 故障排查手册](#11-故障排查手册)
- [12. 最佳实践与注意事项](#12-最佳实践与注意事项)

---

## 1. 项目背景与架构设计

### 1.1 为什么需要容器化

传统部署模式的痛点：
- **环境不一致**：开发、测试、生产环境差异导致"在我机器上能跑"
- **资源浪费**：物理机/虚拟机利用率低，一台服务器只跑一个应用
- **部署效率低**：手动部署耗时，回滚困难
- **扩展性差**：无法快速弹性扩缩容

容器化解决方案：
- **标准化交付**：镜像即交付物，一次构建到处运行
- **资源高效**：共享内核，启动秒级，资源占用少
- **DevOps友好**：与CI/CD无缝集成
- **微服务支撑**：天然适合微服务架构

### 1.2 Docker架构

```
┌─────────────────────────────────────────────────────┐
│                    Docker Client                     │
│              docker build / pull / run               │
├─────────────────────────────────────────────────────┤
│                    Docker Daemon                     │
│                  (dockerd)                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Images   │  │Containers│  │  Network/Volume  │  │
│  │ (layers) │  │ (runtime)│  │  (drivers)       │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
│         │            │               │              │
│  ┌─────────────────────────────────────────────┐   │
│  │           containerd + runc                  │   │
│  └─────────────────────────────────────────────┘   │
│         │                                           │
│  ┌─────────────────────────────────────────────┐   │
│  │              Linux Kernel                     │   │
│  │    namespaces / cgroups / unionfs            │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### 1.3 容器 vs 虚拟机

| 特性 | 容器 | 虚拟机 |
|------|------|--------|
| 隔离级别 | 进程级 | 系统级 |
| 启动时间 | 秒级 | 分钟级 |
| 资源占用 | MB级 | GB级 |
| 性能损耗 | ~0% | 5-15% |
| 镜像大小 | 10-500MB | 1-10GB |
| 密度 | 单机100+ | 单机10-20 |
| 安全性 | 较弱（共享内核） | 较强 |

---

## 2. 环境准备与依赖说明

### 2.1 Docker安装（CentOS 7/8）

```bash
#!/bin/bash
# install-docker-centos.sh - CentOS安装Docker

set -euo pipefail

# 卸载旧版本
yum remove -y docker docker-client docker-client-latest \
    docker-common docker-latest docker-latest-logrotate \
    docker-logrotate docker-engine 2>/dev/null || true

# 安装依赖
yum install -y yum-utils device-mapper-persistent-data lvm2

# 添加Docker CE仓库（使用阿里云镜像）
yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

# 安装Docker CE
yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 配置Docker daemon
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
    "data-root": "/data/docker",
    "storage-driver": "overlay2",
    "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com",
        "https://registry.docker-cn.com"
    ],
    "insecure-registries": ["harbor.example.com"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 655360,
            "Soft": 655360
        },
        "nproc": {
            "Name": "nproc",
            "Hard": 655360,
            "Soft": 655360
        }
    },
    "exec-opts": ["native.cgroupdriver=systemd"],
    "live-restore": true,
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 5,
    "default-address-pools": [
        {"base": "172.17.0.0/12", "size": 24}
    ]
}
EOF

# 启动Docker
systemctl daemon-reload
systemctl enable docker
systemctl start docker

# 验证安装
docker version
docker run --rm hello-world

echo "Docker安装完成"
```

### 2.2 Docker安装（Ubuntu 20.04/22.04）

```bash
#!/bin/bash
# install-docker-ubuntu.sh

set -euo pipefail

# 卸载旧版本
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# 安装依赖
apt-get update
apt-get install -y ca-certificates curl gnupg

# 添加Docker GPG密钥
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# 添加仓库
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 配置同CentOS
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
    "data-root": "/data/docker",
    "storage-driver": "overlay2",
    "registry-mirrors": ["https://mirror.ccs.tencentyun.com"],
    "log-driver": "json-file",
    "log-opts": {"max-size": "100m", "max-file": "3"},
    "exec-opts": ["native.cgroupdriver=systemd"],
    "live-restore": true
}
EOF

systemctl daemon-reload
systemctl enable docker
systemctl start docker

echo "Docker安装完成"
```

---

## 3. Dockerfile最佳实践

### 3.1 通用原则

```dockerfile
# ===== Dockerfile最佳实践示例 =====

# 原则1: 使用官方基础镜像，指定精确版本
FROM python:3.11-slim-bookworm AS builder

# 原则2: 设置工作目录
WORKDIR /app

# 原则3: 先复制依赖文件（利用缓存层）
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# 原则4: 再复制源代码
COPY . .

# ===== 多阶段构建 =====
FROM python:3.11-slim-bookworm AS runtime

# 原则5: 不以root运行
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# 从builder阶段复制依赖
COPY --from=builder /root/.local /home/appuser/.local
COPY --from=builder /app .

# 原则6: 设置环境变量
ENV PATH=/home/appuser/.local/bin:$PATH
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# 原则7: 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# 原则8: 切换到非root用户
USER appuser

# 原则9: 暴露端口
EXPOSE 8000

# 原则10: 使用exec形式的CMD
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "app:app"]
```

### 3.2 Java应用Dockerfile

```dockerfile
# ===== Java应用多阶段构建 =====

# Stage 1: 构建阶段
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
# 先下载依赖（利用缓存）
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# Stage 2: 运行阶段
FROM eclipse-temurin:17-jre-jammy

RUN groupadd -r javaapp && useradd -r -g javaapp javaapp

WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar

# JVM参数
ENV JAVA_OPTS="-Xms512m -Xmx512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -Djava.security.egd=file:/dev/./urandom"

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

USER javaapp
EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

### 3.3 Go应用Dockerfile

```dockerfile
# ===== Go应用多阶段构建（静态链接，极小镜像） =====

# Stage 1: 构建
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# 静态编译
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o /app/server ./cmd/server

# Stage 2: 最小镜像（scratch或distroless）
FROM gcr.io/distroless/static-debian12

COPY --from=builder /app/server /server

EXPOSE 8080
ENTRYPOINT ["/server"]
```

### 3.4 Node.js应用Dockerfile

```dockerfile
# ===== Node.js应用多阶段构建 =====

# Stage 1: 安装依赖
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --only=production

# Stage 2: 构建
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 3: 运行
FROM node:20-alpine AS runtime

RUN apk add --no-cache dumb-init
RUN addgroup -g 1001 nodejs && adduser -S -u 1001 -G nodejs nodejs

WORKDIR /app
COPY --from=deps --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --chown=nodejs:nodejs package.json .

ENV NODE_ENV=production
HEALTHCHECK --interval=30s --timeout=3s \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

USER nodejs
EXPOSE 3000

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/server.js"]
```

### 3.5 镜像安全扫描

```bash
#!/bin/bash
# image-scan.sh - 镜像安全扫描

IMAGE=${1:-"myapp:latest"}

# 使用Trivy扫描
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    "$IMAGE"

# 使用Scout扫描（Docker官方）
docker scout cves "$IMAGE"

# 生成SBOM
docker scout sbom --format spdx-json "$IMAGE" > sbom.json

# 扫描结果解读
# CRITICAL: 必须修复
# HIGH: 应该修复
# MEDIUM: 建议修复
# LOW: 可以忽略
```

---

## 4. Docker Compose编排

### 4.1 LNMP环境

```yaml
# docker-compose-lnmp.yml
# 完整的LNMP开发/测试环境

version: '3.8'

services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./www:/var/www/html
      - nginx-logs:/var/log/nginx
    depends_on:
      - php
    networks:
      - lnmp
    restart: unless-stopped

  php:
    build:
      context: ./php
      dockerfile: Dockerfile
    container_name: php
    volumes:
      - ./www:/var/www/html
      - ./php/php.ini:/usr/local/etc/php/php.ini:ro
      - ./php/www.conf:/usr/local/etc/php-fpm.d/www.conf:ro
    depends_on:
      - mysql
      - redis
    networks:
      - lnmp
    restart: unless-stopped

  mysql:
    image: mysql:8.0
    container_name: mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    ports:
      - "3306:3306"
    volumes:
      - mysql-data:/var/lib/mysql
      - ./mysql/conf.d:/etc/mysql/conf.d:ro
      - ./mysql/initdb:/docker-entrypoint-initdb.d:ro
    command: >
      --default-authentication-plugin=mysql_native_password
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --innodb-buffer-pool-size=1G
      --max-connections=500
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - lnmp
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - lnmp
    restart: unless-stopped

volumes:
  mysql-data:
    driver: local
  redis-data:
    driver: local
  nginx-logs:
    driver: local

networks:
  lnmp:
    driver: bridge
```

### 4.2 微服务开发环境

```yaml
# docker-compose-microservices.yml
# 微服务开发环境编排

version: '3.8'

services:
  # API网关
  gateway:
    image: nginx:1.25-alpine
    ports:
      - "8080:80"
    volumes:
      - ./gateway/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - user-service
      - order-service
      - product-service
    networks:
      - microservices

  # 用户服务
  user-service:
    build: ./services/user
    environment:
      DB_HOST: postgres
      DB_NAME: user_db
      REDIS_URL: redis://redis:6379/0
      JWT_SECRET: ${JWT_SECRET}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - microservices

  # 订单服务
  order-service:
    build: ./services/order
    environment:
      DB_HOST: postgres
      DB_NAME: order_db
      RABBITMQ_URL: amqp://guest:guest@rabbitmq:5672/
    depends_on:
      postgres:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    networks:
      - microservices

  # 商品服务
  product-service:
    build: ./services/product
    environment:
      DB_HOST: postgres
      DB_NAME: product_db
      REDIS_URL: redis://redis:6379/1
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - microservices

  # 数据库
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: ${PG_USER}
      POSTGRES_PASSWORD: ${PG_PASSWORD}
    volumes:
      - pg-data:/var/lib/postgresql/data
      - ./postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - microservices

  # 消息队列
  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    ports:
      - "15672:15672"
    environment:
      RABBITMQ_DEFAULT_USER: ${MQ_USER}
      RABBITMQ_DEFAULT_PASS: ${MQ_PASS}
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "check_running"]
      interval: 15s
      timeout: 10s
      retries: 3
    networks:
      - microservices

  # 缓存
  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - microservices

  # 链路追踪
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"
      - "6831:6831/udp"
    environment:
      COLLECTOR_OTLP_ENABLED: "true"
    networks:
      - microservices

volumes:
  pg-data:

networks:
  microservices:
    driver: bridge
```

---

## 5. 私有镜像仓库Harbor

### 5.1 Harbor部署

```bash
#!/bin/bash
# deploy-harbor.sh - Harbor私有镜像仓库部署

HARBOR_VERSION="v2.10.0"
HARBOR_DIR="/opt/harbor"
DOMAIN="harbor.example.com"

# 1. 下载Harbor
cd /opt
wget https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-offline-installer-${HARBOR_VERSION}.tgz
tar xzf harbor-offline-installer-${HARBOR_VERSION}.tgz
cd harbor

# 2. 生成SSL证书（自签名或Let's Encrypt）
mkdir -p /opt/harbor/ssl
# 自签名证书
openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout /opt/harbor/ssl/$DOMAIN.key \
    -out /opt/harbor/ssl/$DOMAIN.crt \
    -subj "/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,IP:10.10.1.100"

# 3. 配置harbor.yml
cat > harbor.yml << EOF
hostname: $DOMAIN

# HTTPS配置
https:
  port: 443
  certificate: /opt/harbor/ssl/$DOMAIN.crt
  private_key: /opt/harbor/ssl/$DOMAIN.key

# 管理员密码（首次安装后修改）
harbor_admin_password: Harbor12345

# 数据库
database:
  password: root123
  max_idle_conns: 100
  max_open_conns: 900

# 数据存储路径
data_volume: /data/harbor

# 日志
log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor

# 镜像存储配置
storage_service:
  s3:
    accesskey: YOUR_ACCESS_KEY
    secretkey: YOUR_SECRET_KEY
    region: cn-beijing
    bucket: harbor-registry
  # 或使用本地文件系统
  # filesystem:
  #   maxthreads: 100

# 高可用配置（使用外部Redis和PostgreSQL）
# external_database:
#   harbor:
#     host: pg-ha.example.com
#     port: 5432
#     db_name: harbor
#     username: harbor
#     password: harbor_pass

# external_redis:
#   host: redis-ha.example.com
#   port: 6379
EOF

# 4. 安装
./install.sh --with-trivy --with-chartmuseum

echo "Harbor安装完成: https://$DOMAIN"
echo "默认账号: admin / Harbor12345"
```

### 5.2 Harbor日常运维

```bash
#!/bin/bash
# harbor-maintenance.sh - Harbor日常运维

HARBOR_DIR="/opt/harbor"

# 启停服务
cd $HARBOR_DIR
docker compose up -d      # 启动
docker compose down        # 停止
docker compose restart     # 重启

# 备份Harbor
backup_harbor() {
    BACKUP_DIR="/backup/harbor/$(date +%Y%m%d)"
    mkdir -p "$BACKUP_DIR"
    
    # 备份数据库
    docker exec harbor-db pg_dumpall -U postgres > "$BACKUP_DIR/harbor_db.sql"
    
    # 备份配置
    cp -r /opt/harbor/harbor.yml "$BACKUP_DIR/"
    cp -r /opt/harbor/docker-compose.yml "$BACKUP_DIR/"
    
    # 备份镜像数据（如果使用本地存储）
    # tar czf "$BACKUP_DIR/harbor_data.tar.gz" /data/harbor/
    
    echo "Harbor备份完成: $BACKUP_DIR"
}

# 垃圾回收（清理未使用的镜像层）
gc_harbor() {
    echo "开始垃圾回收..."
    docker exec -it harbor-core harbor gc --dry-run  # 先dry-run
    read -p "确认执行垃圾回收? (y/n): " confirm
    if [ "$confirm" == "y" ]; then
        docker exec -it harbor-core harbor gc
    fi
}

# 镜像同步（主从复制）
# 在Harbor Web UI: Administration -> Replications 配置
```

### 5.3 客户端配置

```bash
#!/bin/bash
# configure-harbor-client.sh - 配置Docker客户端使用Harbor

HARBOR_URL="harbor.example.com"

# 1. 信任自签名证书
mkdir -p /etc/docker/certs.d/$HARBOR_URL
cp ca.crt /etc/docker/certs.d/$HARBOR_URL/

# 2. 登录
docker login $HARBOR_URL -u admin -p Harbor12345

# 3. 推送镜像
docker tag myapp:latest $HARBOR_URL/library/myapp:v1.0
docker push $HARBOR_URL/library/myapp:v1.0

# 4. 拉取镜像
docker pull $HARBOR_URL/library/myapp:v1.0

# 5. K8s使用Harbor（创建Secret）
kubectl create secret docker-registry harbor-secret \
    --docker-server=$HARBOR_URL \
    --docker-username=admin \
    --docker-password=Harbor12345
```

---

## 6. 容器网络模式详解

### 6.1 网络模式对比

```
┌─────────────────────────────────────────────────────────┐
│                  Docker网络模式                          │
├──────────┬──────────┬───────────┬───────────────────────┤
│  bridge  │   host   │  overlay  │       macvlan         │
│ (默认)   │ (共享)   │ (跨主机)  │    (独立MAC)          │
├──────────┼──────────┼───────────┼───────────────────────┤
│ 独立网络栈│ 共享主机 │ 跨主机通信│ 直接接入物理网络      │
│ NAT转发  │ 无NAT    │ VXLAN封装 │ 每个容器独立IP        │
│ 适合单机 │ 高性能   │ 适合集群  │ 适合需要独立IP的场景  │
└──────────┴──────────┴───────────┴───────────────────────┘
```

### 6.2 网络操作命令

```bash
#!/bin/bash
# docker-network.sh - Docker网络操作

# 创建自定义bridge网络
docker network create \
    --driver bridge \
    --subnet 172.20.0.0/16 \
    --gateway 172.20.0.1 \
    --ip-range 172.20.1.0/24 \
    --opt com.docker.network.bridge.name=br-custom \
    my-network

# 创建macvlan网络
docker network create \
    --driver macvlan \
    --subnet 10.10.1.0/24 \
    --gateway 10.10.1.1 \
    -o parent=eth0 \
    macvlan-net

# 创建overlay网络（需要Swarm）
docker swarm init
docker network create \
    --driver overlay \
    --subnet 10.20.0.0/16 \
    --attachable \
    overlay-net

# 查看网络
docker network ls
docker network inspect my-network

# 连接容器到网络
docker network connect my-network container1
docker network disconnect my-network container1

# 容器间通信（同一网络可直接用容器名）
docker run -d --name web --network my-network nginx
docker run -d --name app --network my-network myapp
# app容器可以直接访问 web:80
```

---

## 7. 存储驱动与数据持久化

### 7.1 存储驱动选择

```bash
# 查看当前存储驱动
docker info | grep "Storage Driver"

# overlay2（推荐）
# - 性能优秀，稳定可靠
# - 生产环境首选
# 配置：/etc/docker/daemon.json
# {"storage-driver": "overlay2"}

# 各存储驱动对比
# overlay2: 推荐，性能好，稳定
# devicemapper: CentOS 7默认，已废弃
# zfs/btrfs: 特定文件系统使用
```

### 7.2 数据卷管理

```bash
#!/bin/bash
# docker-volumes.sh - 数据卷管理

# 创建数据卷
docker volume create mydata
docker volume create --driver local \
    --opt type=none \
    --opt device=/data/nfs/shared \
    --opt o=bind \
    nfs-volume

# 使用NFS卷
docker run -d \
    --name nfs-app \
    -v nfs-volume:/data \
    myapp

# 使用bind mount
docker run -d \
    --name app \
    -v /host/data:/container/data:rw \
    -v /host/config:/container/config:ro \
    myapp

# 使用tmpfs（内存卷，适合敏感数据）
docker run -d \
    --name secure-app \
    --tmpfs /tmp:rw,noexec,nosuid,size=100m \
    myapp

# 备份数据卷
docker run --rm \
    -v mydata:/source:ro \
    -v /backup:/backup \
    alpine tar czf /backup/mydata-$(date +%Y%m%d).tar.gz -C /source .

# 恢复数据卷
docker run --rm \
    -v mydata:/target \
    -v /backup:/backup:ro \
    alpine tar xzf /backup/mydata-20260502.tar.gz -C /target

# 清理未使用的卷
docker volume prune -f

# 查看卷使用情况
docker system df -v
```

### 7.3 Ceph RBD存储

```bash
# 在Docker中使用Ceph RBD
# 1. 安装rbd驱动插件
docker plugin install ceph/rbd

# 2. 创建pool
ceph osd pool create docker 128

# 3. 创建Docker volume
docker volume create -d ceph/rbd \
    --name my-rbd-volume \
    --opt size=10G \
    --opt pool=docker

# 4. 使用
docker run -d -v my-rbd-volume:/data myapp
```

---

## 8. Docker安全

### 8.1 Rootless模式

```bash
#!/bin/bash
# rootless-docker.sh - Docker Rootless模式配置

# 1. 安装依赖
yum install -y fuse-overlayfs slirp4netns uidmap

# 2. 配置用户命名空间
echo "dockremap:100000:65536" >> /etc/subuid
echo "dockremap:100000:65536" >> /etc/subgid

# 3. 安装rootless Docker
dockerd-rootless-setuptool.sh install

# 4. 设置环境变量
export PATH=/usr/bin:$PATH
export DOCKER_HOST=unix:///run/user/1000/docker.sock

# 5. 开机自启
systemctl --user enable docker
loginctl enable-linger ops
```

### 8.2 Seccomp和AppArmor

```json
// seccomp-profile.json - 自定义seccomp配置文件
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "architectures": ["SCMP_ARCH_X86_64"],
    "syscalls": [
        {
            "names": ["accept", "accept4", "access", "alarm", "bind", "brk",
                       "chdir", "chmod", "chown", "clock_gettime", "close",
                       "connect", "dup", "dup2", "epoll_create", "epoll_wait",
                       "execve", "exit", "exit_group", "fcntl", "fstat",
                       "futex", "getcwd", "getdents", "getpid", "getppid",
                       "getsockname", "getsockopt", "ioctl", "listen", "lseek",
                       "madvise", "mmap", "mprotect", "munmap", "nanosleep",
                       "newfstatat", "open", "openat", "pipe", "poll",
                       "prctl", "pread64", "read", "readlink", "recvfrom",
                       "recvmsg", "rename", "rt_sigaction", "rt_sigprocmask",
                       "sendmsg", "sendto", "set_robust_list", "set_tid_address",
                       "setsockopt", "shutdown", "sigaltstack", "socket",
                       "stat", "statfs", "tgkill", "umask", "uname",
                       "unlink", "wait4", "write", "writev"],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
```

```bash
# 使用seccomp配置
docker run --security-opt seccomp=seccomp-profile.json myapp

# 使用AppArmor
docker run --security-opt apparmor=docker-custom myapp

# 最小权限运行容器
docker run -d \
    --name secure-app \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid \
    --security-opt no-new-privileges:true \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --memory 512m \
    --cpus 1 \
    --pids-limit 100 \
    myapp
```

### 8.3 资源限制

```bash
#!/bin/bash
# docker-resource-limits.sh - Docker资源限制

# 内存限制
docker run -d \
    --memory=1g \
    --memory-swap=2g \
    --memory-reservation=512m \
    --oom-kill-disable \
    --oom-score-adj=-500 \
    myapp

# CPU限制
docker run -d \
    --cpus=2 \
    --cpu-shares=1024 \
    --cpu-period=100000 \
    --cpu-quota=200000 \
    myapp

# IO限制
docker run -d \
    --device-read-bps /dev/sda:100mb \
    --device-write-bps /dev/sda:100mb \
    --device-read-iops /dev/sda:1000 \
    myapp

# PID限制（防止fork炸弹）
docker run -d --pids-limit=100 myapp

# 文件描述符限制
docker run -d --ulimit nofile=655360:655360 myapp

# 查看容器资源使用
docker stats --no-stream
```

---

## 9. 容器化现有应用

### 9.1 容器化流程

```
┌──────────────────────────────────────────────────────┐
│               应用容器化完整流程                       │
├──────────────────────────────────────────────────────┤
│                                                      │
│  1. 应用评估                                         │
│     ├── 依赖分析（系统库、运行时、配置文件）           │
│     ├── 状态分析（有状态/无状态）                     │
│     └── 网络分析（端口、服务发现）                    │
│                                                      │
│  2. 镜像构建                                         │
│     ├── 选择基础镜像                                 │
│     ├── 编写Dockerfile                               │
│     ├── 多阶段构建优化                               │
│     └── 安全扫描                                     │
│                                                      │
│  3. 配置外置化                                       │
│     ├── 环境变量                                     │
│     ├── 配置文件挂载                                 │
│     └── Secret管理                                   │
│                                                      │
│  4. 数据持久化                                       │
│     ├── 数据卷规划                                   │
│     ├── 备份策略                                     │
│     └── 存储驱动选择                                 │
│                                                      │
│  5. 网络规划                                         │
│     ├── 端口映射                                     │
│     ├── 服务发现                                     │
│     └── 负载均衡                                     │
│                                                      │
│  6. 测试验证                                         │
│     ├── 功能测试                                     │
│     ├── 性能测试                                     │
│     └── 安全测试                                     │
│                                                      │
│  7. 部署上线                                         │
│     ├── CI/CD集成                                    │
│     ├── 监控告警                                     │
│     └── 灰度发布                                     │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### 9.2 Spring Boot应用容器化

```bash
# 项目结构
# myapp/
# ├── Dockerfile
# ├── docker-compose.yml
# ├── .dockerignore
# ├── pom.xml
# └── src/

# .dockerignore
cat > .dockerignore << 'EOF'
.git
.idea
*.iml
target/
*.md
docker-compose*.yml
.env*
EOF

# Dockerfile
cat > Dockerfile << 'DOCKERFILE'
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

FROM eclipse-temurin:17-jre-jammy
RUN groupadd -r spring && useradd -r -g spring spring
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar

ENV JAVA_OPTS="-Xms512m -Xmx512m -XX:+UseG1GC"
ENV SPRING_PROFILES_ACTIVE=prod

HEALTHCHECK --interval=30s --timeout=5s \
    CMD curl -sf http://localhost:8080/actuator/health || exit 1

USER spring
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
DOCKERFILE

# docker-compose.yml
cat > docker-compose.yml << 'COMPOSE'
version: '3.8'
services:
  app:
    build: .
    image: harbor.example.com/library/myapp:${VERSION:-latest}
    ports:
      - "8080:8080"
    environment:
      SPRING_DATASOURCE_URL: jdbc:mysql://mysql:3306/mydb
      SPRING_REDIS_HOST: redis
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASS}
      MYSQL_DATABASE: mydb
    volumes:
      - mysql-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 3

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s

volumes:
  mysql-data:
COMPOSE
```

### 9.3 Python Flask应用容器化

```dockerfile
# Dockerfile
FROM python:3.11-slim-bookworm AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim-bookworm
RUN groupadd -r flask && useradd -r -g flask flask
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .

ENV FLASK_ENV=production
ENV PYTHONUNBUFFERED=1

HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -sf http://localhost:5000/health || exit 1

USER flask
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "--timeout", "120", "app:app"]
```

---

## 10. 生产环境运维

### 10.1 日志收集

```bash
#!/bin/bash
# docker-logging.sh - Docker日志管理

# 方案1: JSON File驱动（默认）
# /etc/docker/daemon.json
# {
#     "log-driver": "json-file",
#     "log-opts": {
#         "max-size": "100m",
#         "max-file": "5",
#         "labels": "service,env",
#         "tag": "{{.ImageName}}/{{.Name}}/{{.ID}}"
#     }
# }

# 方案2: Syslog驱动（发送到集中日志系统）
# docker run --log-driver=syslog \
#     --log-opt syslog-address=tcp://logserver:514 \
#     --log-opt tag="myapp" \
#     myapp

# 方案3: Fluentd驱动
# docker run --log-driver=fluentd \
#     --log-opt fluentd-address=localhost:24224 \
#     --log-opt tag="docker.{{.Name}}" \
#     myapp

# 查看容器日志
docker logs -f --tail 100 --timestamps container_name

# 日志文件位置
ls /var/lib/docker/containers/*/
```

### 10.2 监控

```bash
#!/bin/bash
# docker-monitoring.sh - Docker监控

# cAdvisor（容器监控）
docker run -d \
    --name cadvisor \
    --volume=/:/rootfs:ro \
    --volume=/var/run:/var/run:ro \
    --volume=/sys:/sys:ro \
    --volume=/var/lib/docker/:/var/lib/docker:ro \
    --publish=8080:8080 \
    gcr.io/cadvisor/cadvisor:latest

# Docker内置监控命令
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

# 容器健康检查
docker inspect --format='{{.State.Health.Status}}' container_name

# 系统资源使用
docker system df
docker system df -v
```

### 10.3 日常运维命令

```bash
#!/bin/bash
# docker-ops.sh - Docker日常运维命令速查

# ===== 容器管理 =====
docker ps -a                           # 查看所有容器
docker stats                           # 实时资源使用
docker top container_name              # 容器内进程
docker inspect container_name          # 容器详细信息
docker exec -it container_name bash    # 进入容器
docker cp container:/path /host/path   # 复制文件
docker diff container_name             # 文件系统变更

# ===== 镜像管理 =====
docker images                          # 查看镜像
docker image prune -a                  # 清理无用镜像
docker save myapp:latest | gzip > myapp.tar.gz  # 导出镜像
docker load < myapp.tar.gz             # 导入镜像
docker tag myapp:latest harbor.example.com/library/myapp:v1.0
docker push harbor.example.com/library/myapp:v1.0

# ===== 系统清理 =====
docker system prune -af                # 清理所有未使用资源
docker system prune --volumes -f       # 包括数据卷

# ===== 批量操作 =====
# 停止所有容器
docker stop $(docker ps -aq)

# 删除所有已停止容器
docker container prune -f

# 删除所有镜像
docker rmi $(docker images -q)

# 重启所有容器
docker restart $(docker ps -aq)
```

---

## 11. 故障排查手册

### 11.1 常见问题速查

```bash
#!/bin/bash
# docker-troubleshoot.sh - Docker故障排查

echo "========== Docker故障排查 =========="

# 1. Docker服务状态
echo "--- Docker服务状态 ---"
systemctl status docker
docker version
docker info | head -30
echo ""

# 2. 磁盘空间
echo "--- Docker磁盘使用 ---"
docker system df
echo ""
echo "Docker数据目录使用:"
du -sh /var/lib/docker/* 2>/dev/null || du -sh /data/docker/* 2>/dev/null
echo ""

# 3. 网络问题
echo "--- Docker网络 ---"
docker network ls
echo ""

# 4. 容器状态
echo "--- 异常容器 ---"
docker ps -a --filter "status=exited" --filter "status=dead" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
echo ""

# 5. 容器日志
echo "--- 最近容器日志 ---"
for container in $(docker ps -a --format '{{.Names}}' | head -5); do
    echo "=== $container ==="
    docker logs --tail 10 "$container" 2>&1
    echo ""
done
```

### 11.2 常见问题和解决方案

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| `Cannot connect to the Docker daemon` | Docker服务未启动 | `systemctl start docker` |
| `no space left on device` | 磁盘满 | `docker system prune -af` |
| `port is already allocated` | 端口冲突 | 修改端口映射或停止占用进程 |
| `OOMKilled` | 内存不足 | 增加`--memory`限制 |
| `ImagePullBackOff` | 镜像拉取失败 | 检查网络和镜像仓库配置 |
| `container killed by OOM` | 容器内存超限 | 调整内存限制 |
| 容器启动后立即退出 | 应用错误 | `docker logs`查看日志 |
| DNS解析失败 | DNS配置问题 | `--dns=223.5.5.5` |
| overlay2占用空间大 | 未清理的镜像层 | `docker system prune` + 垃圾回收 |
| 容器内时间不对 | 时区问题 | `-v /etc/localtime:/etc/localtime:ro` |

---

## 12. 最佳实践与注意事项

### 12.1 镜像构建最佳实践

1. **使用多阶段构建** - 减小最终镜像体积
2. **使用官方基础镜像** - 安全、稳定、持续更新
3. **固定版本标签** - 避免使用`latest`
4. **最小化镜像层** - 合并RUN指令
5. **利用构建缓存** - 先复制依赖文件，再复制源代码
6. **使用.dockerignore** - 排除不需要的文件
7. **不安装不必要的包** - 减少攻击面
8. **安全扫描** - 使用Trivy/Snyk扫描镜像

### 12.2 运维最佳实践

1. **配置外置** - 使用环境变量、配置文件挂载，不要硬编码
2. **日志标准化** - 输出到stdout/stderr，由Docker日志驱动收集
3. **健康检查** - 必须配置HEALTHCHECK
4. **资源限制** - 必须设置memory和cpu限制
5. **非root运行** - 使用USER指令
6. **只读文件系统** - 使用`--read-only`
7. **定期清理** - 配置cron定期执行`docker system prune`
8. **备份数据卷** - 定期备份重要数据

### 12.3 安全最佳实践

1. **Rootless模式** - 生产环境使用rootless Docker
2. **最小权限** - `--cap-drop ALL --cap-add` 只添加需要的能力
3. **只读文件系统** - `--read-only`
4. **禁止特权** - `--security-opt no-new-privileges:true`
5. **网络隔离** - 不同服务使用不同网络
6. **镜像签名** - 使用Docker Content Trust
7. **定期更新** - 及时更新基础镜像修复漏洞

---

> 📅 最后更新: 2026-05-02
> 📝 本手册涵盖Docker容器化的核心内容，持续更新中
