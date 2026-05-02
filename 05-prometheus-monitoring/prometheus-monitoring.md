# Prometheus+Grafana监控体系完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. Prometheus Server高可用部署](#2-prometheus-server高可用部署)
- [3. Alertmanager告警配置](#3-alertmanager告警配置)
- [4. 常用Exporter](#4-常用exporter)
- [5. 自定义Exporter开发](#5-自定义exporter开发)
- [6. Grafana Dashboard设计](#6-grafana-dashboard设计)
- [7. 告警规则模板](#7-告警规则模板)
- [8. 长期存储方案](#8-长期存储方案)
- [9. 业务监控](#9-业务监控)
- [10. 最佳实践](#10-最佳实践)

---

## 1. 项目背景与架构设计

### 1.1 监控架构

```
┌─────────────────────────────────────────────────────────────────┐
│                      监控数据源                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────────────┐ │
│  │node_     │ │mysqld_   │ │redis_    │ │ 应用自定义指标    │ │
│  │exporter  │ │exporter  │ │exporter  │ │ /metrics端点      │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────────┬──────────┘ │
│       └─────────────┼───────────┼─────────────────┘            │
│                     ▼           ▼                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Prometheus Server (HA)                       │  │
│  │   ┌────────────┐  ┌────────────┐                        │  │
│  │   │ Prometheus  │  │ Prometheus │  ← 联邦/远程写入       │  │
│  │   │ Server-01   │  │ Server-02  │                        │  │
│  │   └──────┬──────┘  └──────┬─────┘                        │  │
│  └──────────┼────────────────┼──────────────────────────────┘  │
│             ▼                ▼                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────────┐ │
│  │  Alertmanager  │  │    Grafana     │  │ Thanos/Victoria  │ │
│  │   (告警路由)    │  │   (可视化)     │  │ Metrics(长期存储)│ │
│  └───────┬────────┘  └────────────────┘  └──────────────────┘ │
│          ▼                                                      │
│  ┌────────────────┐                                            │
│  │ 钉钉/飞书/邮件 │                                            │
│  │ Slack/PagerDuty│                                            │
│  └────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 指标采集模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| Pull | Prometheus主动拉取 | 默认模式，服务发现 |
| Push | Pushgateway接收推送 | 短生命周期Job |
| Federation | Prometheus联邦 | 跨集群聚合 |
| Remote Write | 远程写入 | Thanos/VM等长期存储 |

---

## 2. Prometheus Server高可用部署

### 2.1 Docker Compose部署

```yaml
# docker-compose-prometheus.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:v2.48.0
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/rules:/etc/prometheus/rules:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--storage.tsdb.retention.size=50GB'
      - '--web.enable-lifecycle'
      - '--web.enable-admin-api'
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:v0.26.0
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertmanager-data:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    restart: unless-stopped

  grafana:
    image: grafana/grafana:10.2.0
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin123
      GF_INSTALL_PLUGINS: grafana-piechart-panel
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.47.2
    container_name: cadvisor
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    restart: unless-stopped

volumes:
  prometheus-data:
  alertmanager-data:
  grafana-data:
```

### 2.2 Prometheus配置

```yaml
# prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s
  external_labels:
    cluster: 'production'
    replica: '$(HOSTNAME)'

# 告警规则文件
rule_files:
  - /etc/prometheus/rules/*.yml

# Alertmanager配置
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

# 告警抑制规则（在Alertmanager中配置更好）

# 采集目标
scrape_configs:
  # Prometheus自身
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter
  - job_name: 'node-exporter'
    static_configs:
      - targets:
          - '10.10.1.11:9100'
          - '10.10.1.12:9100'
          - '10.10.1.13:9100'
          - '10.10.1.21:9100'
          - '10.10.1.22:9100'
          - '10.10.1.23:9100'
    relabel_configs:
      - source_labels: [__address__]
        regex: '(.*):\d+'
        target_label: instance

  # MySQL Exporter
  - job_name: 'mysql'
    static_configs:
      - targets: ['10.10.1.100:9104']
        labels:
          instance: 'mysql-primary'

  # Redis Exporter
  - job_name: 'redis'
    static_configs:
      - targets: ['10.10.1.101:9121']

  # Blackbox Exporter
  - job_name: 'blackbox-http'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://www.example.com
          - https://api.example.com/health
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115

  # Kubernetes服务发现
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
```

---

## 3. Alertmanager告警配置

### 3.1 完整Alertmanager配置

```yaml
# alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.example.com:465'
  smtp_from: 'alertmanager@example.com'
  smtp_auth_username: 'alertmanager@example.com'
  smtp_auth_password: 'password'
  smtp_require_tls: false

# 模板
templates:
  - '/etc/alertmanager/templates/*.tmpl'

# 路由树
route:
  receiver: 'default-receiver'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  
  routes:
    # 紧急告警 - 钉钉/飞书
    - match:
        severity: critical
      receiver: 'dingtalk-critical'
      group_wait: 10s
      repeat_interval: 1h
      
    # 警告 - 邮件
    - match:
        severity: warning
      receiver: 'email-warning'
      repeat_interval: 4h
      
    # 数据库告警
    - match_re:
        service: (mysql|redis|postgresql)
      receiver: 'db-team'
      group_by: ['alertname', 'instance']

# 抑制规则
inhibit_rules:
  # 如果有critical告警，抑制同实例的warning告警
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']

# 接收器
receivers:
  - name: 'default-receiver'
    email_configs:
      - to: 'ops@example.com'

  - name: 'dingtalk-critical'
    webhook_configs:
      - url: 'http://dingtalk-webhook:8060/dingtalk/ops/send'
        send_resolved: true

  - name: 'email-warning'
    email_configs:
      - to: 'ops@example.com'
        send_resolved: true

  - name: 'db-team'
    webhook_configs:
      - url: 'http://dingtalk-webhook:8060/dingtalk/db-team/send'
        send_resolved: true
    email_configs:
      - to: 'dba@example.com'
        send_resolved: true
```

---

## 4. 常用Exporter

### 4.1 MySQL Exporter

```bash
# 部署mysqld_exporter
docker run -d \
    --name mysql-exporter \
    -p 9104:9104 \
    -e DATA_SOURCE_NAME="exporter:password@(mysql-host:3306)/" \
    prom/mysqld-exporter:v0.15.1

# MySQL创建监控用户
# CREATE USER 'exporter'@'%' IDENTIFIED BY 'password';
# GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
# FLUSH PRIVILEGES;
```

### 4.2 Redis Exporter

```bash
docker run -d \
    --name redis-exporter \
    -p 9121:9121 \
    oliver006/redis_exporter:v1.55.0 \
    --redis.addr redis://10.10.1.101:6379 \
    --redis.password your_password
```

### 4.3 Blackbox Exporter

```yaml
# blackbox/blackbox.yml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 301, 302]
      follow_redirects: true
      preferred_ip_protocol: "ip4"
  http_post_2xx:
    prober: http
    http:
      method: POST
      valid_status_codes: [200, 201]
  tcp_connect:
    prober: tcp
    timeout: 5s
  icmp:
    prober: icmp
    timeout: 5s
  dns:
    prober: dns
    dns:
      query_name: "example.com"
      query_type: "A"
```

---

## 5. 自定义Exporter开发

### 5.1 Python自定义Exporter

```python
#!/usr/bin/env python3
# custom_exporter.py - 自定义业务指标Exporter

from prometheus_client import start_http_server, Gauge, Counter, Histogram
import time
import psutil
import mysql.connector

# 定义指标
APP_REQUEST_TOTAL = Counter(
    'app_http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

APP_REQUEST_LATENCY = Histogram(
    'app_http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint'],
    buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 5.0]
)

APP_ACTIVE_CONNECTIONS = Gauge(
    'app_active_connections',
    'Active database connections'
)

APP_QUEUE_SIZE = Gauge(
    'app_message_queue_size',
    'Message queue size',
    ['queue_name']
)

DB_SLOW_QUERIES = Gauge(
    'app_mysql_slow_queries_total',
    'MySQL slow queries count'
)

def collect_mysql_metrics():
    """采集MySQL指标"""
    try:
        conn = mysql.connector.connect(
            host='localhost', user='monitor', password='pass'
        )
        cursor = conn.cursor()
        cursor.execute("SHOW GLOBAL STATUS LIKE 'Slow_queries'")
        result = cursor.fetchone()
        if result:
            DB_SLOW_QUERIES.set(int(result[1]))
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"MySQL metrics error: {e}")

def collect_business_metrics():
    """采集业务指标（示例：从Redis获取队列长度）"""
    import redis
    r = redis.Redis(host='localhost', port=6379, db=0)
    APP_QUEUE_SIZE.labels(queue_name='order').set(r.llen('order_queue'))
    APP_QUEUE_SIZE.labels(queue_name='notification').set(r.llen('notification_queue'))

def collect_system_metrics():
    """采集系统指标"""
    APP_ACTIVE_CONNECTIONS.set(len(psutil.net_connections()))

def main():
    # 启动HTTP服务暴露指标
    start_http_server(9150)
    print("Custom exporter started on :9150")
    
    while True:
        try:
            collect_mysql_metrics()
            collect_business_metrics()
            collect_system_metrics()
        except Exception as e:
            print(f"Collection error: {e}")
        time.sleep(15)

if __name__ == '__main__':
    main()
```

### 5.2 Go自定义Exporter

```go
// custom_exporter.go
package main

import (
    "net/http"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    httpRequests = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "app_http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "path", "status"},
    )
    
    httpDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "app_http_duration_seconds",
            Help:    "HTTP request duration",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method", "path"},
    )
)

func init() {
    prometheus.MustRegister(httpRequests)
    prometheus.MustRegister(httpDuration)
}

func main() {
    http.Handle("/metrics", promhttp.Handler())
    http.ListenAndServe(":9150", nil)
}
```

---

## 6. Grafana Dashboard设计

### 6.1 数据源配置

```yaml
# grafana/provisioning/datasources/datasource.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false

  - name: Alertmanager
    type: alertmanager
    access: proxy
    url: http://alertmanager:9093
    jsonData:
      implementation: prometheus
```

### 6.2 Linux主机Dashboard核心PromQL

```yaml
# 核心PromQL查询

# CPU使用率
# 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 内存使用率
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 磁盘使用率
(1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes) * 100

# 磁盘IO使用率
rate(node_disk_io_time_seconds_total[5m]) * 100

# 网络流量（入站）
rate(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m]) * 8

# 网络流量（出站）
rate(node_network_transmit_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m]) * 8

# TCP连接数
node_netstat_Tcp_CurrEstab

# 系统负载
node_load1 / count(node_cpu_seconds_total{mode="idle"}) by (instance)
```

### 6.3 MySQL Dashboard核心PromQL

```yaml
# MySQL核心指标

# 连接数
mysql_global_status_threads_connected

# QPS
rate(mysql_global_status_queries[5m])

# 慢查询
rate(mysql_global_status_slow_queries[5m])

# InnoDB缓冲池命中率
(mysql_global_status_innodb_buffer_pool_read_requests - mysql_global_status_innodb_buffer_pool_reads) / mysql_global_status_innodb_buffer_pool_read_requests * 100

# 表锁等待
mysql_global_status_table_locks_waited

# 复制延迟
mysql_slave_status_seconds_behind_master
```

### 6.4 Redis Dashboard核心PromQL

```yaml
# Redis核心指标

# 内存使用
redis_memory_used_bytes

# 命中率
redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total) * 100

# QPS
rate(redis_commands_processed_total[5m])

# 连接数
redis_connected_clients

# 淘汰key数
rate(redis_evicted_keys_total[5m])

# 主从复制偏移量差
redis_connected_slave_offset_diff
```

---

## 7. 告警规则模板

### 7.1 基础设施告警

```yaml
# prometheus/rules/infra-alerts.yml
groups:
  - name: node-alerts
    rules:
      # CPU使用率告警
      - alert: HighCpuUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CPU使用率过高 {{ $labels.instance }}"
          description: "CPU使用率 {{ $value | printf \"%.1f\" }}%，已持续5分钟"

      # 内存使用率告警
      - alert: HighMemoryUsage
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "内存使用率过高 {{ $labels.instance }}"
          description: "内存使用率 {{ $value | printf \"%.1f\" }}%"

      # 磁盘空间告警
      - alert: DiskSpaceLow
        expr: (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "磁盘空间不足 {{ $labels.instance }}"
          description: "挂载点 {{ $labels.mountpoint }} 使用率 {{ $value | printf \"%.1f\" }}%"

      # 磁盘空间紧急
      - alert: DiskSpaceCritical
        expr: (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes) * 100 > 95
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "磁盘空间紧急 {{ $labels.instance }}"
          description: "挂载点 {{ $labels.mountpoint }} 使用率 {{ $value | printf \"%.1f\" }}%"

      # 主机宕机
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "实例宕机 {{ $labels.instance }}"
          description: "{{ $labels.instance }} 已宕机超过1分钟"

      # 系统负载过高
      - alert: HighSystemLoad
        expr: node_load15 / count by(instance) (node_cpu_seconds_total{mode="idle"}) > 2
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "系统负载过高 {{ $labels.instance }}"
          description: "15分钟负载 {{ $value | printf \"%.2f\" }}"

      # 网络错误
      - alert: NetworkErrors
        expr: rate(node_network_receive_errs_total[5m]) > 10 or rate(node_network_transmit_errs_total[5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "网络错误 {{ $labels.instance }}"
          description: "设备 {{ $labels.device }} 存在网络错误"
```

### 7.2 数据库告警

```yaml
# prometheus/rules/db-alerts.yml
groups:
  - name: mysql-alerts
    rules:
      - alert: MysqlDown
        expr: mysql_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MySQL实例宕机"

      - alert: MysqlHighConnections
        expr: mysql_global_status_threads_connected > 500
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL连接数过高"
          description: "当前连接数 {{ $value }}"

      - alert: MysqlSlowQueries
        expr: rate(mysql_global_status_slow_queries[5m]) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL慢查询增多"

      - alert: MysqlReplicationLag
        expr: mysql_slave_status_seconds_behind_master > 30
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "MySQL复制延迟"
          description: "延迟 {{ $value }} 秒"

  - name: redis-alerts
    rules:
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis实例宕机"

      - alert: RedisHighMemory
        expr: redis_memory_used_bytes / redis_memory_max_bytes * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Redis内存使用率过高"

      - alert: RedisHighEviction
        expr: rate(redis_evicted_keys_total[5m]) > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Redis频繁淘汰key"
```

---

## 8. 长期存储方案

### 8.1 Thanos部署

```yaml
# thanos-sidecar配置（与Prometheus同节点）
# 在Prometheus启动参数中添加:
# --web.enable-lifecycle
# --storage.tsdb.min-block-duration=2h
# --storage.tsdb.max-block-duration=2h

# Thanos Sidecar
docker run -d \
    --name thanos-sidecar \
    -v /prometheus:/prometheus \
    -v /etc/prometheus:/etc/prometheus \
    quay.io/thanos/thanos:v0.32.0 \
    sidecar \
    --tsdb.path=/prometheus \
    --prometheus.url=http://prometheus:9090 \
    --objstore.config-file=/etc/prometheus/bucket.yml \
    --grpc-address=0.0.0.0:10901 \
    --http-address=0.0.0.0:10902

# Thanos Store Gateway
docker run -d \
    --name thanos-store \
    quay.io/thanos/thanos:v0.32.0 \
    store \
    --data-dir=/thanos/store \
    --objstore.config-file=/etc/thanos/bucket.yml \
    --grpc-address=0.0.0.0:10911

# Thanos Query (查询入口)
docker run -d \
    --name thanos-query \
    -p 10903:10902 \
    quay.io/thanos/thanos:v0.32.0 \
    query \
    --store=thanos-sidecar:10901 \
    --store=thanos-store:10911 \
    --http-address=0.0.0.0:10902

# S3存储配置 (bucket.yml)
# type: S3
# config:
#   bucket: thanos-metrics
#   endpoint: s3.cn-beijing.amazonaws.com
#   access_key: YOUR_KEY
#   secret_key: YOUR_SECRET
```

### 8.2 VictoriaMetrics部署

```yaml
# VictoriaMetrics（更简单的长期存储方案）
version: '3.8'
services:
  victoriametrics:
    image: victoriametrics/victoria-metrics:v1.95.1
    container_name: victoriametrics
    ports:
      - "8428:8428"
    volumes:
      - vm-data:/victoria-metrics-data
    command:
      - '-retentionPeriod=12'
      - '-storageDataPath=/victoria-metrics-data'
      - '-httpListenAddr=:8428'
    restart: unless-stopped

  vmagent:
    image: victoriametrics/vmagent:v1.95.1
    container_name: vmagent
    ports:
      - "8429:8429"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - vmagent-data:/vmagent
    command:
      - '-promscrape.config=/etc/prometheus/prometheus.yml'
      - '-remoteWrite.url=http://victoriametrics:8428/api/v1/write'
    restart: unless-stopped

volumes:
  vm-data:
  vmagent-data:
```

---

## 9. 业务监控

### 9.1 RED方法（请求级别）

```yaml
# RED: Rate, Errors, Duration
# 适用于面向用户的服务

# 请求速率
rate(http_requests_total[5m])

# 错误率
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100

# 延迟分布（P99）
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

### 9.2 USE方法（资源级别）

```yaml
# USE: Utilization, Saturation, Errors
# 适用于基础设施资源

# CPU利用率
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# CPU饱和度（负载/核心数）
node_load1 / count by(instance) (node_cpu_seconds_total{mode="idle"})

# 内存利用率
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 磁盘利用率
rate(node_disk_io_time_seconds_total[5m]) * 100

# 磁盘饱和度
rate(node_disk_io_time_weighted_seconds_total[5m])
```

### 9.3 四个黄金信号

```yaml
# 延迟 (Latency)
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))

# 流量 (Traffic)
sum(rate(http_requests_total[5m])) by (service)

# 错误 (Errors)
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service) / sum(rate(http_requests_total[5m])) by (service)

# 饱和度 (Saturation)
# CPU、内存、磁盘IO、网络带宽等资源使用率
```

---

## 10. 最佳实践

### 10.1 指标命名规范

```
# 格式: <namespace>_<subsystem>_<name>_<unit>
# 示例:
# http_requests_total          # HTTP请求总数
# http_request_duration_seconds # HTTP请求延迟
# mysql_queries_total          # MySQL查询总数
# redis_memory_used_bytes      # Redis内存使用

# 标签规范:
# instance: 实例标识 (host:port)
# job: 采集任务名
# service: 服务名
# environment: 环境 (prod/staging/dev)
```

### 10.2 告警分级策略

| 级别 | 响应时间 | 通知方式 | 示例 |
|------|---------|---------|------|
| P0 Critical | 5分钟 | 电话+短信+IM | 服务宕机、数据丢失 |
| P1 High | 15分钟 | 短信+IM | 服务降级、DB主从断开 |
| P2 Warning | 1小时 | IM+邮件 | 磁盘85%、CPU持续高 |
| P3 Info | 下个工作日 | 邮件 | 证书即将过期 |

### 10.3 监控最佳实践

1. **监控四层** - 基础设施→中间件→应用→业务
2. **告警收敛** - 分组、抑制、静默，避免告警风暴
3. **SLO驱动** - 基于SLO定义告警阈值
4. **定期Review** - 每月Review告警规则有效性
5. **Dashboard规范** - 统一配色、布局、变量
6. **容量规划** - 基于监控数据做容量预测
7. **Runbook** - 每个告警关联处理手册

---

> 📅 最后更新: 2026-05-02
