# Dockerfile 最佳实践

## 1. Dockerfile 指令详解

### 1.1 核心指令

| 指令 | 作用 | 是否创建新层 | 缓存影响 |
|------|------|-------------|----------|
| FROM | 指定基础镜像 | 是 | 基础镜像变更则失效 |
| RUN | 执行命令 | 是 | 命令变更则失效 |
| COPY | 复制文件 | 是 | 文件内容变更则失效 |
| ADD | 复制+解压 | 是 | 同 COPY |
| CMD | 默认启动命令 | 否 | - |
| ENTRYPOINT | 入口点 | 否 | - |
| ENV | 环境变量 | 是 | 变更则失效 |
| EXPOSE | 声明端口 | 否 | - |
| WORKDIR | 工作目录 | 是 | 路径变更则失效 |
| USER | 运行用户 | 否 | - |
| ARG | 构建参数 | 是 | 参数变更则失效 |
| LABEL | 元数据 | 否 | - |
| HEALTHCHECK | 健康检查 | 否 | - |
| SHELL | 指定 shell | 否 | - |

### 1.2 RUN 指令优化

```dockerfile
# ❌ 错误：多条 RUN 导致多层
RUN apt-get update
RUN apt-get install -y curl
RUN apt-get install -y wget
RUN apt-get clean

# ✅ 正确：合并为单条 RUN，减少层数
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    wget \
    ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
```

### 1.3 COPY vs ADD

```dockerfile
# COPY - 简单复制，行为可预测
COPY app.jar /app/app.jar
COPY config/ /app/config/

# ADD - 有额外功能，但行为复杂
ADD archive.tar.gz /app/     # 自动解压
ADD https://example.com/file /app/  # 远程下载（不推荐，无法利用缓存）

# 最佳实践：优先使用 COPY，仅在需要自动解压时使用 ADD
```

### 1.4 CMD vs ENTRYPOINT

```dockerfile
# ENTRYPOINT - 容器的主进程，不易被覆盖
ENTRYPOINT ["java", "-jar", "/app/app.jar"]

# CMD - 默认参数，可被 docker run 参数覆盖
CMD ["--server.port=8080"]

# 组合使用
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
CMD ["--spring.profiles.active=prod"]

# 运行时覆盖 CMD
docker run myapp --spring.profiles.active=staging
```

## 2. 多阶段构建

### 2.1 基本原理

多阶段构建将构建过程和最终镜像分离，显著减小镜像体积：

```dockerfile
# ===== 阶段1：构建 =====
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
# 先复制 pom.xml 并下载依赖（利用缓存）
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# ===== 阶段2：运行 =====
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
# 从构建阶段复制产物
COPY --from=builder /build/target/app.jar ./app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 2.2 缓存优化策略

```dockerfile
# Node.js 应用 - 利用依赖缓存
FROM node:20-alpine AS deps
WORKDIR /app
# 先复制依赖文件
COPY package.json package-lock.json ./
RUN npm ci --production

# 构建阶段
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# 运行阶段
FROM node:20-alpine
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./
EXPOSE 3000
USER node
CMD ["node", "dist/main.js"]
```

### 2.3 Go 应用的最小镜像

```dockerfile
# Go 应用可以编译为静态二进制，最终镜像可以极度精简
FROM golang:1.21-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o app .

# 最终镜像 - scratch 空镜像
FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /build/app /app
EXPOSE 8080
ENTRYPOINT ["/app"]

# 镜像大小对比：
# golang:1.21      ~800MB
# alpine + binary  ~15MB
# scratch + binary ~8MB
```

## 3. 安全最佳实践

### 3.1 非 Root 用户

```dockerfile
FROM node:20-alpine

# 创建应用用户
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app
COPY --chown=appuser:appgroup . .

# 切换到非 root 用户
USER appuser

EXPOSE 3000
CMD ["node", "server.js"]
```

### 3.2 只读文件系统

```dockerfile
FROM python:3.11-slim

RUN useradd -r -s /bin/false appuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

USER appuser
# 使用 tmpfs 挂载临时目录
VOLUME ["/tmp"]

CMD ["python", "app.py"]
```

```bash
# 运行时启用只读文件系统
docker run --read-only --tmpfs /tmp -d myapp
```

### 3.3 镜像签名验证

```dockerfile
# 使用 Content Trust 验证镜像
FROM docker.io/library/nginx:1.25-alpine@sha256:abc123...

# 或使用 Docker Content Trust
# export DOCKER_CONTENT_TRUST=1
# docker pull nginx:alpine
```

## 4. .dockerignore 文件

```dockerignore
# 版本控制
.git
.gitignore
.svn

# 依赖目录
node_modules
vendor
__pycache__
*.pyc

# 构建产物
dist
build
target
*.jar

# IDE 配置
.idea
.vscode
*.swp
*.swo

# 操作系统文件
.DS_Store
Thumbs.db

# Docker 相关
Dockerfile*
docker-compose*.yml
.dockerignore

# 文档
README.md
docs/
*.md

# 敏感文件
.env
.env.*
*.key
*.pem
*.crt
secrets/
```

## 5. 生产案例

### 案例1：Java Spring Boot 微服务

```dockerfile
# 构建阶段
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# 运行阶段
FROM eclipse-temurin:17-jre-alpine

# 安全加固
RUN apk add --no-cache tini && \
    addgroup -g 1001 -S app && \
    adduser -u 1001 -S app -G app

WORKDIR /app
COPY --from=builder --chown=app:app /build/target/*.jar app.jar

# JVM 调优参数
ENV JAVA_OPTS="-XX:+UseG1GC \
    -XX:MaxGCPauseMillis=200 \
    -XX:+UseContainerSupport \
    -XX:MaxRAMPercentage=75.0 \
    -Djava.security.egd=file:/dev/./urandom"

USER app
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health || exit 1

# 使用 tini 作为 PID 1
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

### 案例2：Python Flask + Gunicorn

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim
RUN useradd -r -s /bin/false appuser

WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .

USER appuser
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "--timeout", "120", "app:app"]
```

### 案例3：Nginx + 静态资源

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.25-alpine
# 自定义 nginx 配置
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /app/dist /usr/share/nginx/html

# 非 root 运行 nginx
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

## 6. 镜像体积优化对比

| 优化策略 | 效果 | 说明 |
|----------|------|------|
| 使用 alpine 基础镜像 | 减少 50-80% | musl libc 兼容性问题 |
| 多阶段构建 | 减少 60-90% | 分离构建工具和运行时 |
| 清理缓存和临时文件 | 减少 10-30% | apt clean, rm lists |
| 合并 RUN 指令 | 减少层数 | 减少元数据开销 |
| 使用 scratch 空镜像 | 极致精简 | 仅限静态二进制 |
| 使用 distroless 镜像 | 比 alpine 更小 | 无 shell、无包管理器 |

## 7. 常见错误

### 错误1：缓存失效

```dockerfile
# ❌ 错误：任何文件变更都会导致依赖重新安装
COPY . .
RUN npm install

# ✅ 正确：先复制依赖声明，再复制代码
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
```

### 错误2：以 root 运行

```dockerfile
# ❌ 危险：容器内以 root 运行
FROM nginx:alpine
COPY . /usr/share/nginx/html

# ✅ 安全：使用非 root 用户
FROM nginx:alpine
RUN chown -R nginx:nginx /usr/share/nginx/html
USER nginx
COPY . /usr/share/nginx/html
```

### 错误3：暴露敏感信息

```dockerfile
# ❌ 危险：在镜像中包含密钥
COPY private.key /app/
ENV DB_PASSWORD=secret123

# ✅ 安全：运行时注入
# docker run -v /path/to/key:/app/private.key:ro myapp
# docker run -e DB_PASSWORD=$(cat /run/secrets/db_password) myapp
```
