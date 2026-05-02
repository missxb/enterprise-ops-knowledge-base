# Docker 日志管理

## 概述

容器日志管理是生产环境运维的核心挑战之一。与传统服务器不同，容器的生命周期短暂，日志随容器销毁而消失。有效的日志管理方案需要解决日志收集、传输、存储、检索和告警等问题。本文将深入介绍 Docker 日志驱动机制以及主流日志管理方案：EFK（Elasticsearch + Fluentd + Kibana）、Fluentd、Loki 等。

## 一、Docker 日志驱动

### 1.1 日志驱动类型

Docker 支持多种日志驱动，每种驱动有不同的特点和适用场景：

| 驱动 | 说明 | 适用场景 |
|------|------|---------|
| `json-file` | 默认驱动，以 JSON 格式写入文件 | 开发/测试环境 |
| `syslog` | 写入 syslog 守护进程 | 使用 syslog 的环境 |
| `journald` | 写入 systemd journal | CentOS 7+/Ubuntu 16.04+ |
| `gelf` | 写入 GELF 端点（Graylog） | Graylog 环境 |
| `fluentd` | 写入 Fluentd 收集器 | Fluentd/EFK 方案 |
| `awslogs` | 写入 AWS CloudWatch | AWS 环境 |
| `splunk` | 写入 Splunk | 使用 Splunk 的企业 |
| `etwlogs` | 写入 ETW（Windows） | Windows 容器 |
| `local` | 本地日志，自动压缩旋转 | 资源受限环境 |
| `none` | 不记录日志 | 不需要日志的场景 |

### 1.2 配置日志驱动

**全局配置（daemon.json）：**

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5",
    "compress": "true",
    "labels": "service,environment",
    "tag": "{{.Name}}/{{.ID}}"
  }
}
```

**单容器配置：**

```bash
# 运行时指定日志驱动
docker run -d \
  --log-driver=fluentd \
  --log-opt fluentd-address=localhost:24224 \
  --log-opt tag="docker.{{.Name}}" \
  --log-opt fluentd-async-connect=true \
  nginx:latest

# 使用 local 驱动（推荐资源受限环境）
docker run -d \
  --log-driver=local \
  --log-opt max-size=50m \
  --log-opt max-file=3 \
  nginx:latest
```

**Docker Compose 配置：**

```yaml
version: "3.8"
services:
  web:
    image: nginx:latest
    logging:
      driver: "fluentd"
      options:
        fluentd-address: "localhost:24224"
        tag: "docker.web"
        fluentd-async-connect: "true"
        fluentd-retry-wait: "1s"
        fluentd-max-retries: "30"
```

### 1.3 json-file 驱动优化

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5",
    "compress": "true",
    "env": "os,customer",
    "labels": "production_status",
    "tag": "{{.Name}}/{{.ID}}/{{.ImageName}}"
  }
}
```

**注意事项：**
- `max-size` 和 `max-file` 必须同时设置，否则日志不会轮转
- 生产环境建议 `max-size: 50m-200m`，`max-file: 3-10`
- 不设置限制会导致日志文件无限增长，最终撑满磁盘

### 1.4 日志查看与导出

```bash
# 查看容器日志
docker logs -f --tail 100 <container_id>

# 查看带时间戳的日志
docker logs --since "2024-01-01T00:00:00" --until "2024-01-02T00:00:00" <container_id>

# 导出日志文件
docker cp <container_id>:/var/lib/docker/containers/<id>/<id>-json.log ./container.log

# 查看日志文件位置
docker inspect --format='{{.LogPath}}' <container_id>

# 批量查看所有容器日志大小
for cid in $(docker ps -q); do
  name=$(docker inspect --format='{{.Name}}' $cid)
  size=$(docker inspect --format='{{.LogPath}}' $cid | xargs ls -lh 2>/dev/null | awk '{print $5}')
  echo "$name: $size"
done
```

## 二、EFK 方案（Elasticsearch + Fluentd + Kibana）

### 2.1 架构设计

```
┌────────────┐     ┌────────────┐     ┌──────────────┐     ┌─────────┐
│  容器应用   │────▶│  Fluentd   │────▶│Elasticsearch │────▶│  Kibana │
│  (日志源)   │     │  (收集器)   │     │  (存储/索引)  │     │ (可视化) │
└────────────┘     └────────────┘     └──────────────┘     └─────────┘
                         │
                         ▼
                   ┌────────────┐
                   │   Buffer   │
                   │ (缓冲/重试) │
                   └────────────┘
```

### 2.2 Fluentd 配置

**fluent.conf：**

```xml
# 输入源：Docker 容器日志
<source>
  @type forward
  port 24224
  bind 0.0.0.0
  <transport tcp>
  </transport>
</source>

# 输入源：文件日志
<source>
  @type tail
  path /var/log/containers/*.log
  pos_file /var/log/fluentd-containers.log.pos
  tag kubernetes.*
  read_from_head true
  <parse>
    @type json
    time_key time
    time_format %Y-%m-%dT%H:%M:%S.%NZ
  </parse>
</source>

# 过滤：解析 JSON 日志
<filter docker.**>
  @type parser
  key_name log
  reserve_data true
  remove_key_name_field true
  <parse>
    @type json
    time_key time
    time_format %Y-%m-%dT%H:%M:%S.%NZ
  </parse>
</filter>

# 过滤：添加元数据
<filter **>
  @type record_transformer
  <record>
    hostname "#{Socket.gethostname}"
    environment "#{ENV['ENVIRONMENT'] || 'production'}"
  </record>
</filter>

# 输出：Elasticsearch
<match **>
  @type elasticsearch
  host elasticsearch
  port 9200
  logstash_format true
  logstash_prefix docker-logs
  logstash_dateformat %Y.%m.%d
  include_tag_key true
  type_name _doc
  tag_key @log_name
  flush_interval 5s
  flush_thread_count 4
  retry_max_interval 30
  retry_forever true
  num_threads 4
  request_timeout 15s
  reload_connections false
  reconnect_on_error true
  reload_on_failure true
  <buffer>
    @type file
    path /var/log/fluentd-buffers/kubernetes.system.buffer
    flush_mode interval
    flush_interval 5s
    flush_thread_count 4
    retry_type exponential_backoff
    retry_forever true
    retry_max_interval 30
    chunk_limit_size 8M
    queue_limit_length 512
    total_limit_size 2G
    overflow_action block
  </buffer>
</match>
```

### 2.3 Docker Compose 部署 EFK

```yaml
version: "3.8"
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.12.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - ELASTIC_PASSWORD=changeme
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
    volumes:
      - es_data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    deploy:
      resources:
        limits:
          memory: 4G
    networks:
      - elk

  kibana:
    image: docker.elastic.co/kibana/kibana:8.12.0
    container_name: kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=changeme
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch
    networks:
      - elk

  fluentd:
    image: fluent/fluentd:v1.16-1
    container_name: fluentd
    volumes:
      - ./fluentd/conf:/fluentd/etc
      - /var/log:/var/log:ro
    ports:
      - "24224:24224"
      - "24224:24224/udp"
    depends_on:
      - elasticsearch
    networks:
      - elk

volumes:
  es_data:

networks:
  elk:
    driver: bridge
```

### 2.4 Elasticsearch 索引生命周期管理

```json
// 创建 ILM 策略
PUT _ilm/policy/docker-logs-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50gb",
            "max_age": "1d"
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "3d",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          },
          "set_priority": {
            "priority": 50
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "searchable_snapshot": {
            "snapshot_repository": "found-snapshots"
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

## 三、Fluent Bit（轻量级替代方案）

### 3.1 Fluent Bit vs Fluentd

| 特性 | Fluent Bit | Fluentd |
|------|-----------|---------|
| 语言 | C | Ruby + C |
| 内存占用 | ~1 MB | ~40 MB |
| 插件 | 内置 | 500+ 插件 |
| 适用场景 | 边缘/IoT/资源受限 | 复杂处理/多输出 |
| 缓冲 | 内存/文件系统 | 内存/文件系统 |
| Kubernetes | DaemonSet 首选 | 集群级聚合 |

### 3.2 Fluent Bit 配置

```ini
# /fluent-bit/etc/fluent-bit.conf
[SERVICE]
    Flush         5
    Log_Level     info
    Daemon        off
    Parsers_File  parsers.conf
    HTTP_Server   On
    HTTP_Listen   0.0.0.0
    HTTP_Port     2020
    Health_Check  On
    storage.path  /var/log/flb-storage/
    storage.sync  normal
    storage.checksum off
    storage.max_chunks_up 128

[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    Parser            docker
    Tag               kube.*
    Refresh_Interval  5
    Mem_Buf_Limit     50MB
    Skip_Long_Lines   On
    DB                /var/log/flb-kube.db
    DB.locking        true
    storage.type      filesystem

[FILTER]
    Name                kubernetes
    Match               kube.*
    Kube_URL            https://kubernetes.default.svc:443
    Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
    Kube_Tag_Prefix     kube.var.log.containers.
    Merge_Log           On
    Merge_Log_Key       log_processed
    K8S-Logging.Parser  On
    K8S-Logging.Exclude Off

[OUTPUT]
    Name            es
    Match           kube.*
    Host            elasticsearch
    Port            9200
    Index           kube-logs
    Type            _doc
    Logstash_Format On
    Logstash_Prefix kube-logs
    Retry_Limit     5
    Replace_Dots    On
    Trace_Error     On
    Buffer_Size     5MB
    Workers         4
```

## 四、Loki 方案

### 4.1 Loki 架构

Loki 是 Grafana Labs 开源的日志聚合系统，设计理念是"like Prometheus, but for logs"：

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ Promtail │───▶│   Loki   │───▶│  Object  │    │ Grafana  │
│ (采集)   │    │ (索引)   │    │ Storage  │    │ (查询)   │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
```

**核心特点：**
- 只索引标签（label），不索引日志内容，存储成本极低
- 与 Prometheus 标签体系一致
- 使用 LogQL 查询语言
- 原生集成 Grafana

### 4.2 Docker Compose 部署 Loki

```yaml
version: "3.8"
services:
  loki:
    image: grafana/loki:2.9.4
    container_name: loki
    command: -config.file=/etc/loki/local-config.yaml
    ports:
      - "3100:3100"
    volumes:
      - loki_data:/loki
    networks:
      - logging

  promtail:
    image: grafana/promtail:2.9.4
    container_name: promtail
    command: -config.file=/etc/promtail/config.yml
    volumes:
      - ./promtail-config.yml:/etc/promtail/config.yml
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    depends_on:
      - loki
    networks:
      - logging

  grafana:
    image: grafana/grafana:10.3.1
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      - loki
    networks:
      - logging

volumes:
  loki_data:
  grafana_data:

networks:
  logging:
    driver: bridge
```

### 4.3 Promtail 配置

```yaml
# promtail-config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # Docker 容器日志
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          __path__: /var/lib/docker/containers/*/*.log
    pipeline_stages:
      - docker: {}
      - regex:
          expression: '.*level=(?P<level>\w+).*'
      - labels:
          level:

  # 系统日志
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          __path__: /var/log/syslog

  # 应用日志
  - job_name: app-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: app
          environment: production
          __path__: /var/log/app/*.log
    pipeline_stages:
      - json:
          expressions:
            level: level
            msg: message
            trace_id: trace_id
      - labels:
          level:
      - timestamp:
          source: time
          format: RFC3339Nano
```

### 4.4 LogQL 查询示例

```logql
# 查询特定容器的日志
{job="docker"} |= "error"

# 使用正则过滤
{job="docker", container="nginx"} |~ "HTTP/1.1\" [5]\\d{2}"

# JSON 日志解析
{job="app"} | json | level="error"

# 统计每分钟错误数
count_over_time({job="docker"} |= "error" [1m])

# 统计 Top 10 错误信息
topk(10,
  sum by (msg) (
    count_over_time(
      {job="app"} | json | level="error" [1h]
    )
  )
)
```

## 五、生产环境最佳实践

### 5.1 日志格式标准化

```json
{
  "timestamp": "2024-01-15T10:30:00.123Z",
  "level": "INFO",
  "service": "order-service",
  "trace_id": "abc123",
  "span_id": "def456",
  "message": "Order created successfully",
  "context": {
    "order_id": "ORD-2024-001",
    "user_id": "U1001",
    "amount": 99.99
  }
}
```

### 5.2 日志分级策略

```yaml
# 不同环境的日志级别
environments:
  development:
    level: DEBUG
    retention: 7d
    storage: local
  staging:
    level: INFO
    retention: 30d
    storage: elasticsearch
  production:
    level: WARN
    retention: 90d
    storage: elasticsearch + s3
```

### 5.3 磁盘空间管理

```bash
# 定期清理 Docker 日志
find /var/lib/docker/containers/ -name "*-json.log" -size +100M -exec truncate -s 50M {} \;

# 配置日志轮转（logrotate）
cat > /etc/logrotate.d/docker-containers << 'EOF'
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    missingok
    delaycompress
    copytruncate
}
EOF
```

### 5.4 安全与合规

1. **敏感数据脱敏**：在 Fluentd 中配置 filter 脱敏信用卡号、身份证号等
2. **日志加密传输**：使用 TLS 加密 Fluentd/Fluent Bit 到 Elasticsearch 的传输
3. **访问控制**：Kibana 配置 RBAC，限制日志查询权限
4. **审计日志**：保留操作审计日志至少 180 天
5. **合规存储**：金融行业日志需存储在境内，保留 3-5 年

### 5.5 监控日志系统自身

```yaml
# Prometheus 监控 Fluentd
# fluentd.conf 添加 prometheus 插件
<filter **>
  @type prometheus
  <metric>
    name fluentd_input_status_num_records_total
    type counter
    desc The total number of incoming records
    <labels>
      tag ${tag}
    </labels>
  </metric>
</filter>

<match **>
  @type prometheus
  <metric>
    name fluentd_output_status_num_records_total
    type counter
    desc The total number of outgoing records
    <labels>
      tag ${tag}
    </labels>
  </metric>
</match>
```

## 六、方案选型建议

| 场景 | 推荐方案 | 理由 |
|------|---------|------|
| 小规模（<50 容器） | Loki + Promtail | 轻量、低成本、Grafana 集成 |
| 中等规模（50-500 容器） | EFK | 功能完善、社区活跃 |
| 大规模（>500 容器） | Loki + Fluent Bit | 高性能、低资源消耗 |
| 已有 ELK 基础设施 | EFK | 复用现有投资 |
| 边缘/IoT 场景 | Fluent Bit → Loki | 极低资源消耗 |
| 多云环境 | Fluent Bit → 多输出 | 灵活路由 |
