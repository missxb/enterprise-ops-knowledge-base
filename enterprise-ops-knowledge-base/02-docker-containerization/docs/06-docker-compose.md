# Docker Compose 编排

## 1. Docker Compose 核心概念

### 1.1 Compose 文件结构

Docker Compose 使用 YAML 文件定义和运行多容器应用。Compose 规范经历了 v1、v2、v3 三个版本，当前推荐使用 Compose Specification（统一规范）。

```yaml
# compose.yml - 推荐文件名（也支持 docker-compose.yml）
version: "3.8"  # 可选，Compose Specification 不需要

services:
  # 服务定义
  web:
    image: nginx:alpine
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "80:80"
    environment:
      - NODE_ENV=production
    volumes:
      - ./html:/usr/share/nginx/html:ro
    depends_on:
      - api
    networks:
      - frontend
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost"]
      interval: 30s
      timeout: 5s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M

  api:
    image: myapp/api:latest
    environment:
      DATABASE_URL: postgres://user:pass@db:5432/mydb
    depends_on:
      db:
        condition: service_healthy
    networks:
      - frontend
      - backend

  db:
    image: postgres:15
    volumes:
      - pg-data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    networks:
      - backend

volumes:
  pg-data:
    driver: local

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true  # 不允许外部访问
```

### 1.2 服务依赖管理

```yaml
services:
  # depends_on 支持条件依赖
  api:
    depends_on:
      db:
        condition: service_healthy      # 等待健康检查通过
      redis:
        condition: service_started       # 等待服务启动
      migration:
        condition: service_completed_successfully  # 等待任务完成

  db:
    image: postgres:15
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  migration:
    image: myapp/migration:latest
    command: ["python", "manage.py", "migrate"]
    depends_on:
      db:
        condition: service_healthy
```

## 2. 多环境管理

### 2.1 环境变量文件

```bash
# .env - Compose 自动读取
COMPOSE_PROJECT_NAME=myapp
APP_PORT=8080
DB_PASSWORD=dev-password
LOG_LEVEL=debug

# .env.production - 手动指定
APP_PORT=80
DB_PASSWORD=<from-vault>
LOG_LEVEL=warn
```

```yaml
# compose.yml
services:
  app:
    image: myapp:${TAG:-latest}
    ports:
      - "${APP_PORT}:8080"
    environment:
      LOG_LEVEL: ${LOG_LEVEL}
```

```bash
# 使用不同环境文件
docker compose --env-file .env.production up -d
docker compose --env-file .env.staging up -d
```

### 2.2 Compose 覆盖文件

```yaml
# compose.yml - 基础配置
services:
  app:
    image: myapp:latest
    environment:
      DATABASE_URL: postgres://localhost/mydb
    ports:
      - "8080:8080"

# compose.override.yml - 开发环境覆盖（自动加载）
services:
  app:
    build: .
    volumes:
      - ./src:/app/src
    environment:
      DEBUG: "true"

# compose.prod.yml - 生产环境覆盖
services:
  app:
    image: myregistry.com/myapp:v1.0
    deploy:
      replicas: 3
      resources:
        limits:
          memory: 1G
```

```bash
# 开发环境（自动加载 compose.yml + compose.override.yml）
docker compose up -d

# 生产环境
docker compose -f compose.yml -f compose.prod.yml up -d

# 测试环境
docker compose -f compose.yml -f compose.test.yml up -d
```

## 3. 网络配置

### 3.1 自定义网络

```yaml
services:
  web:
    networks:
      frontend:
        aliases:
          - web.local
      backend:

  api:
    networks:
      - backend

  db:
    networks:
      backend:
        ipv4_address: 172.20.0.100

networks:
  frontend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.1.0/24
          gateway: 172.20.1.1

  backend:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.20.2.0/24
```

## 4. 存储配置

### 4.1 卷和挂载

```yaml
services:
  db:
    volumes:
      # 命名卷
      - pg-data:/var/lib/postgresql/data
      # Bind Mount
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
      # tmpfs
      - type: tmpfs
        target: /tmp
        tmpfs:
          size: 100000000

  app:
    volumes:
      - app-config:/app/config
      - type: bind
        source: ./logs
        target: /var/log/app

volumes:
  pg-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/postgres
  app-config:
    external: true  # 使用已存在的卷
```

## 5. 密钥和配置管理

### 5.1 Secrets（Compose Swarm 模式）

```yaml
services:
  db:
    image: postgres:15
    secrets:
      - db_password
      - db_user
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
      POSTGRES_USER_FILE: /run/secrets/db_user

secrets:
  db_password:
    file: ./secrets/db_password.txt
  db_user:
    file: ./secrets/db_user.txt
```

### 5.2 Configs

```yaml
services:
  nginx:
    image: nginx:alpine
    configs:
      - source: nginx_conf
        target: /etc/nginx/nginx.conf
        mode: 0444

configs:
  nginx_conf:
    file: ./config/nginx.conf
```

## 6. 部署与扩展

### 6.1 副本与资源限制

```yaml
services:
  api:
    image: myapp/api:latest
    deploy:
      replicas: 3
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
      resources:
        limits:
          cpus: "2.0"
          memory: 1G
        reservations:
          cpus: "0.5"
          memory: 256M
      update_config:
        parallelism: 1
        delay: 30s
        failure_action: rollback
        order: start-first
      rollback_config:
        parallelism: 1
        delay: 10s
```

### 6.2 健康检查与自动重启

```yaml
services:
  app:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    restart: unless-stopped
```

## 7. 生产案例

### 案例1：LAMP 环境

```yaml
# compose.yml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./html:/var/www/html
      - ssl-certs:/etc/nginx/ssl
    depends_on:
      - php
    restart: unless-stopped

  php:
    image: php:8.2-fpm-alpine
    volumes:
      - ./html:/var/www/html
      - ./php.ini:/usr/local/etc/php/php.ini:ro
    depends_on:
      - mysql
    restart: unless-stopped

  mysql:
    image: mysql:8.0
    volumes:
      - mysql-data:/var/lib/mysql
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/mysql_root_password
      MYSQL_DATABASE: app
    secrets:
      - mysql_root_password
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis-data:/data
    restart: unless-stopped

volumes:
  mysql-data:
  redis-data:
  ssl-certs:

secrets:
  mysql_root_password:
    file: ./secrets/mysql_root_password.txt
```

### 案例2：监控栈

```yaml
# compose.yml - Prometheus + Grafana + Alertmanager
services:
  prometheus:
    image: prom/prometheus:v2.48.0
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'
    ports:
      - "9090:9090"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:10.2.0
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    environment:
      GF_SECURITY_ADMIN_PASSWORD_FILE: /run/secrets/grafana_password
    secrets:
      - grafana_password
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:v0.26.0
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    ports:
      - "9093:9093"
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.7.0
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
    network_mode: host
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:

secrets:
  grafana_password:
    file: ./secrets/grafana_password.txt
```

## 8. 常用命令

```bash
# 启动所有服务
docker compose up -d

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f api

# 扩缩容
docker compose up -d --scale api=3

# 重建镜像
docker compose build --no-cache

# 停止并删除所有资源
docker compose down

# 停止并删除包括卷
docker compose down -v

# 查看服务配置（验证 YAML）
docker compose config

# 执行一次性命令
docker compose exec api python manage.py migrate
docker compose run --rm api npm test
```
