# ELK/EFK日志管理平台完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. Elasticsearch集群部署](#2-elasticsearch集群部署)
- [3. Logstash/Filebeat配置](#3-logstashfilebeat配置)
- [4. Kibana可视化](#4-kibana可视化)
- [5. 日志采集方案](#5-日志采集方案)
- [6. 日志解析规则](#6-日志解析规则)
- [7. 日志告警](#7-日志告警)
- [8. 日志生命周期管理](#8-日志生命周期管理)
- [9. 性能优化](#9-性能优化)
- [10. 故障排查与最佳实践](#10-故障排查与最佳实践)

---

## 1. 项目背景与架构设计

### 1.1 日志平台架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        日志采集层                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │ Filebeat │ │Filebeat  │ │Fluentd   │ │ 应用直接写入     │  │
│  │ (系统日志)│ │(容器日志)│ │(K8s日志) │ │ (TCP/HTTP)      │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────────┬─────────┘  │
│       └─────────────┼───────────┼─────────────────┘            │
│                     ▼           ▼                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Kafka (日志缓冲，可选)                       │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Logstash (日志解析与转换)                    │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Elasticsearch Cluster (热温冷架构)                │  │
│  │  ┌────────┐  ┌────────┐  ┌────────┐                     │  │
│  │  │ Hot    │  │ Warm   │  │ Cold   │                     │  │
│  │  │ (SSD)  │  │ (HDD)  │  │ (对象) │                     │  │
│  │  └────────┘  └────────┘  └────────┘                     │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         ▼                                       │
│  ┌──────────────┐  ┌──────────────┐                            │
│  │   Kibana     │  │  ElastAlert2 │                            │
│  │   (可视化)    │  │   (告警)     │                            │
│  └──────────────┘  └──────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 组件版本规划

| 组件 | 版本 | 说明 |
|------|------|------|
| Elasticsearch | 8.11.x | 搜索和存储引擎 |
| Logstash | 8.11.x | 日志处理管道 |
| Kibana | 8.11.x | 可视化 |
| Filebeat | 8.11.x | 轻量级日志采集 |
| Kafka | 3.6.x | 日志缓冲（可选） |

---

## 2. Elasticsearch集群部署

### 2.1 热温冷架构部署

```yaml
# docker-compose-es-cluster.yml
version: '3.8'

services:
  # ===== Hot节点 (SSD, 最近数据) =====
  es-hot-01:
    image: elasticsearch:8.11.3
    container_name: es-hot-01
    environment:
      - node.name=es-hot-01
      - node.roles=ingest,data_hot,data_content
      - cluster.name=elk-cluster
      - discovery.seed_hosts=es-hot-01,es-hot-02,es-warm-01
      - cluster.initial_master_nodes=es-hot-01,es-hot-02,es-warm-01
      - "ES_JAVA_OPTS=-Xms4g -Xmx4g"
      - xpack.security.enabled=false
      - bootstrap.memory_lock=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - es-hot-01-data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
    networks:
      - elk

  es-hot-02:
    image: elasticsearch:8.11.3
    container_name: es-hot-02
    environment:
      - node.name=es-hot-02
      - node.roles=ingest,data_hot,data_content
      - cluster.name=elk-cluster
      - discovery.seed_hosts=es-hot-01,es-hot-02,es-warm-01
      - cluster.initial_master_nodes=es-hot-01,es-hot-02,es-warm-01
      - "ES_JAVA_OPTS=-Xms4g -Xmx4g"
      - xpack.security.enabled=false
      - bootstrap.memory_lock=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - es-hot-02-data:/usr/share/elasticsearch/data
    networks:
      - elk

  # ===== Warm节点 (HDD, 历史数据) =====
  es-warm-01:
    image: elasticsearch:8.11.3
    container_name: es-warm-01
    environment:
      - node.name=es-warm-01
      - node.roles=master,data_warm
      - cluster.name=elk-cluster
      - discovery.seed_hosts=es-hot-01,es-hot-02,es-warm-01
      - cluster.initial_master_nodes=es-hot-01,es-hot-02,es-warm-01
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
      - xpack.security.enabled=false
      - bootstrap.memory_lock=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - es-warm-01-data:/usr/share/elasticsearch/data
    networks:
      - elk

  # ===== Logstash =====
  logstash:
    image: logstash:8.11.3
    container_name: logstash
    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline:ro
      - ./logstash/config/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
    ports:
      - "5044:5044"    # Beats input
      - "5000:5000/tcp" # TCP input
      - "5000:5000/udp" # UDP input
    environment:
      - "LS_JAVA_OPTS=-Xms1g -Xmx1g"
    depends_on:
      - es-hot-01
    networks:
      - elk

  # ===== Kibana =====
  kibana:
    image: kibana:8.11.3
    container_name: kibana
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://es-hot-01:9200
    depends_on:
      - es-hot-01
    networks:
      - elk

  # ===== Filebeat =====
  filebeat:
    image: elastic/filebeat:8.11.3
    container_name: filebeat
    user: root
    volumes:
      - ./filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      - logstash
    networks:
      - elk

volumes:
  es-hot-01-data:
  es-hot-02-data:
  es-warm-01-data:

networks:
  elk:
    driver: bridge
```

### 2.2 Elasticsearch配置优化

```yaml
# elasticsearch.yml 关键配置
cluster.name: elk-cluster
node.name: es-hot-01
node.roles: [ingest, data_hot, data_content]

# 路径
path.data: /usr/share/elasticsearch/data
path.logs: /usr/share/elasticsearch/logs

# 网络
network.host: 0.0.0.0
http.port: 9200
transport.port: 9300

# JVM堆内存设置（不超过物理内存的50%，不超过32GB）
# 在jvm.options中设置:
# -Xms16g
# -Xmx16g

# 跨集群复制（可选）
# cluster.remote.remote_cluster.seeds: ["10.10.1.100:9300"]
```

---

## 3. Logstash/Filebeat配置

### 3.1 Logstash管道配置

```ruby
# logstash/pipeline/logstash.conf

# ===== 输入 =====
input {
  # Beats输入
  beats {
    port => 5044
    ssl => false
  }
  
  # TCP输入（应用直接发送JSON日志）
  tcp {
    port => 5000
    codec => json_lines
    tags => ["tcp"]
  }

  # Kafka输入（可选）
  # kafka {
  #   bootstrap_servers => "kafka:9092"
  #   topics => ["app-logs", "nginx-logs"]
  #   group_id => "logstash-consumer"
  # }
}

# ===== 过滤 =====
filter {
  # Nginx访问日志解析
  if [fields][log_type] == "nginx-access" {
    grok {
      match => {
        "message" => '%{IPORHOST:remote_addr} - %{DATA:remote_user} \[%{HTTPDATE:timestamp}\] "%{WORD:method} %{URIPATHPARAM:request} HTTP/%{NUMBER:http_version}" %{NUMBER:status} %{NUMBER:body_bytes_sent} "%{DATA:http_referer}" "%{DATA:http_user_agent}" "%{DATA:x_forwarded_for}" %{NUMBER:request_time}'
      }
    }
    mutate {
      convert => {
        "status" => "integer"
        "body_bytes_sent" => "integer"
        "request_time" => "float"
      }
    }
    date {
      match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z"]
      target => "@timestamp"
    }
    geoip {
      source => "remote_addr"
    }
    useragent {
      source => "http_user_agent"
      target => "user_agent"
    }
  }

  # Java应用日志解析
  if [fields][log_type] == "java-app" {
    grok {
      match => {
        "message" => '%{TIMESTAMP_ISO8601:log_timestamp} \[%{LOGLEVEL:level}\] \[%{DATA:thread}\] %{DATA:logger} - %{GREEDYDATA:log_message}'
      }
    }
    # 多行合并（Java异常堆栈）
    # 已在Filebeat中配置multiline
    
    # 解析Java异常
    if "Exception" in [log_message] {
      mutate {
        add_tag => ["exception"]
      }
    }
  }

  # Python应用日志
  if [fields][log_type] == "python-app" {
    grok {
      match => {
        "message" => '%{TIMESTAMP_ISO8601:log_timestamp} - %{DATA:module} - %{LOGLEVEL:level} - %{GREEDYDATA:log_message}'
      }
    }
  }

  # 通用处理
  mutate {
    add_field => {
      "environment" => "%{[fields][environment]}"
      "service" => "%{[fields][service]}"
    }
  }

  # 删除不需要的字段
  mutate {
    remove_field => ["beat", "input", "offset", "prospector"]
  }
}

# ===== 输出 =====
output {
  # 按环境和类型输出到不同索引
  if [fields][environment] == "production" {
    elasticsearch {
      hosts => ["es-hot-01:9200"]
      index => "%{[fields][service]}-%{+YYYY.MM.dd}"
      template_overwrite => true
    }
  } else {
    elasticsearch {
      hosts => ["es-hot-01:9200"]
      index => "dev-%{[fields][service]}-%{+YYYY.MM.dd}"
    }
  }

  # 调试输出
  # stdout { codec => rubydebug }
}
```

### 3.2 Filebeat配置

```yaml
# filebeat/filebeat.yml
filebeat.inputs:
  # 系统日志
  - type: log
    enabled: true
    paths:
      - /var/log/messages
      - /var/log/syslog
    fields:
      log_type: syslog
      environment: production
    fields_under_root: true

  # Nginx访问日志
  - type: log
    enabled: true
    paths:
      - /var/log/nginx/access.log
    fields:
      log_type: nginx-access
      service: nginx
      environment: production
    fields_under_root: true

  # Nginx错误日志
  - type: log
    enabled: true
    paths:
      - /var/log/nginx/error.log
    fields:
      log_type: nginx-error
      service: nginx
      environment: production
    fields_under_root: true

  # Java应用日志（支持多行）
  - type: log
    enabled: true
    paths:
      - /var/log/myapp/*.log
    fields:
      log_type: java-app
      service: myapp
      environment: production
    fields_under_root: true
    multiline.pattern: '^\d{4}-\d{2}-\d{2}'
    multiline.negate: true
    multiline.match: after
    multiline.max_lines: 100

  # Docker容器日志
  - type: container
    enabled: true
    paths:
      - /var/lib/docker/containers/*/*.log
    fields:
      log_type: docker
      environment: production
    fields_under_root: true
    processors:
      - add_docker_metadata:
          host: "unix:///var/run/docker.sock"

# 处理器
processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
  - drop_fields:
      fields: ["agent.ephemeral_id", "agent.id", "agent.name"]

# 输出到Logstash
output.logstash:
  hosts: ["logstash:5044"]
  loadbalance: true
  bulk_max_size: 2048

# 或直接输出到Elasticsearch
# output.elasticsearch:
#   hosts: ["es-hot-01:9200"]
#   index: "filebeat-%{+yyyy.MM.dd}"

# 日志
logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644
```

---

## 4. Kibana可视化

### 4.1 索引模式配置

```
# 在Kibana中创建索引模式:
# 1. 进入 Management → Stack Management → Index Patterns
# 2. 创建索引模式: nginx-*
# 3. 选择时间字段: @timestamp
# 4. 创建索引模式: myapp-*
# 5. 创建索引模式: filebeat-*
```

### 4.2 常用查询语法

```
# KQL (Kibana Query Language)
# 精确匹配
status: 500
# 模糊匹配
message: "connection refused"
# 范围查询
status >= 400 and status < 500
# 存在字段
error: *
# 组合查询
service: "myapp" and level: "ERROR" and not message: "timeout"
# 通配符
host: web-*
# 正则
message: /timeout|refused/
```

---

## 5. 日志采集方案

### 5.1 K8s容器日志采集

```yaml
# DaemonSet方式部署Filebeat到K8s
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: filebeat
  namespace: logging
spec:
  selector:
    matchLabels:
      app: filebeat
  template:
    metadata:
      labels:
        app: filebeat
    spec:
      serviceAccountName: filebeat
      terminationGracePeriodSeconds: 30
      containers:
      - name: filebeat
        image: elastic/filebeat:8.11.3
        args: ["-c", "/etc/filebeat.yml", "-e"]
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        volumeMounts:
        - name: config
          mountPath: /etc/filebeat.yml
          subPath: filebeat.yml
        - name: data
          mountPath: /usr/share/filebeat/data
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: varlog
          mountPath: /var/log
          readOnly: true
      volumes:
      - name: config
        configMap:
          name: filebeat-config
      - name: data
        hostPath:
          path: /var/lib/filebeat-data
          type: DirectoryOrCreate
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: varlog
        hostPath:
          path: /var/log
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
  namespace: logging
data:
  filebeat.yml: |
    filebeat.autodiscover:
      providers:
        - type: kubernetes
          node: ${NODE_NAME}
          hints.enabled: true
          hints.default_config:
            type: container
            paths:
              - /var/log/containers/*${data.kubernetes.container.id}.log
    
    processors:
      - add_kubernetes_metadata:
          host: ${NODE_NAME}
      - add_cloud_metadata: ~
    
    output.elasticsearch:
      hosts: ["elasticsearch:9200"]
      index: "k8s-logs-%{+yyyy.MM.dd}"
```

---

## 6. 日志解析规则

### 6.1 Grok模式速查

```ruby
# 常用Grok模式
# IP地址: %{IPORHOST:client_ip}
# 时间戳: %{TIMESTAMP_ISO8601:timestamp}
# HTTP方法: %{WORD:method}
# HTTP状态码: %{NUMBER:status}
# URL: %{URIPATHPARAM:request}
# 用户代理: %{DATA:user_agent}
# 日志级别: %{LOGLEVEL:level}
# 任意文本: %{GREEDYDATA:message}

# Nginx combined日志
'%{IPORHOST:remote_addr} - %{DATA:remote_user} \[%{HTTPDATE:timestamp}\] "%{WORD:method} %{URIPATHPARAM:request} HTTP/%{NUMBER:http_version}" %{NUMBER:status} %{NUMBER:body_bytes_sent} "%{DATA:http_referer}" "%{DATA:http_user_agent}"'

# Apache combined日志
'%{IPORHOST:client_ip} %{DATA:user_name} \[%{HTTPDATE:timestamp}\] "%{WORD:method} %{DATA:request} HTTP/%{NUMBER:http_version}" %{NUMBER:response_code} %{NUMBER:bytes} "%{DATA:referrer}" "%{DATA:user_agent}"'

# Java日志
'%{TIMESTAMP_ISO8601:timestamp} \[%{LOGLEVEL:level}\] \[%{DATA:thread}\] %{DATA:logger} - %{GREEDYDATA:message}'

# Python日志
'%{TIMESTAMP_ISO8601:timestamp} - %{DATA:module} - %{LOGLEVEL:level} - %{GREEDYDATA:message}'

# Spring Boot日志
'%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{NUMBER:pid} --- \[%{DATA:thread}\] %{DATA:logger} : %{GREEDYDATA:message}'
```

---

## 7. 日志告警

### 7.1 ElastAlert2部署

```yaml
# docker-compose-elastalert.yml
version: '3.8'
services:
  elastalert:
    image: jertel/elastalert2:latest
    container_name: elastalert
    volumes:
      - ./elastalert/config.yaml:/opt/elastalert/config.yaml
      - ./elastalert/rules:/opt/elastalert/rules
    environment:
      - ELASTICSEARCH_HOST=es-hot-01
      - ELASTICSEARCH_PORT=9200
    depends_on:
      - es-hot-01
```

### 7.2 告警规则示例

```yaml
# elastalert/rules/error-spike.yaml
name: "应用错误日志突增"
type: spike
index: myapp-*

query_key: service
timeframe:
  minutes: 5
spike_height: 5
spike_type: "up"
threshold_cur: 10

filter:
- query:
    query_string:
      query: "level: ERROR"

alert:
- "email"
- "slack"

email:
- "ops@example.com"

slack_webhook_url: "https://hooks.slack.com/services/xxx"
slack_channel_override: "#alerts"

alert_text: |
  应用错误日志突增告警
  服务: {0}
  当前错误数: {1}
  之前错误数: {2}
alert_text_args:
  - service
  - num_hits
  - num_hits_before

# elastalert/rules/login-failure.yaml
name: "登录失败告警"
type: frequency
index: auth-logs-*

num_events: 5
timeframe:
  minutes: 10

filter:
- query:
    query_string:
      query: "event: login_failure"

alert:
- "email"

email:
- "security@example.com"

alert_text: |
  登录失败告警
  用户: {0}
  IP: {1}
  失败次数: {2}
alert_text_args:
- user
- client_ip
- num_hits
```

---

## 8. 日志生命周期管理

### 8.1 ILM策略

```json
// 创建ILM策略
PUT _ilm/policy/log-lifecycle
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
        "min_age": "7d",
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
          "set_priority": {
            "priority": 0
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

// 创建索引模板关联ILM
PUT _index_template/log-template
{
  "index_patterns": ["myapp-*", "nginx-*"],
  "template": {
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1,
      "index.lifecycle.name": "log-lifecycle",
      "index.lifecycle.rollover_alias": "myapp-logs"
    }
  }
}
```

---

## 9. 性能优化

### 9.1 分片策略

```
# 分片大小建议: 10-50GB
# 分片数量 = 数据量 / 单分片大小

# 计算公式:
# 日志量: 100GB/天
# 保留30天: 3TB
# 单分片30GB: 3000GB / 30GB = 100个分片
# 3个数据节点: 每节点约33个分片

# 创建索引时指定分片
PUT myapp-2026.05.02
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  }
}
```

### 9.2 查询优化

```
# 1. 使用时间范围过滤（利用索引时间分区）
GET myapp-*/_search
{
  "query": {
    "bool": {
      "must": [
        {"match": {"level": "ERROR"}},
        {"range": {"@timestamp": {"gte": "now-1h"}}}
      ]
    }
  }
}

# 2. 使用_filter context（不计算评分，更快）
GET myapp-*/_search
{
  "query": {
    "bool": {
      "filter": [
        {"term": {"level": "ERROR"}},
        {"range": {"@timestamp": {"gte": "now-1h"}}}
      ]
    }
  }
}

# 3. 避免深分页，使用search_after
GET myapp-*/_search
{
  "size": 100,
  "sort": [{"@timestamp": "desc"}, {"_id": "asc"}],
  "search_after": ["2026-05-02T10:00:00Z", "abc123"]
}

# 4. 只返回需要的字段
GET myapp-*/_search
{
  "_source": ["timestamp", "level", "message"],
  "query": {"match_all": {}}
}
```

### 9.3 索引优化

```
# 1. 合理设置副本数（非关键日志可设为0）
PUT myapp-*/_settings
{
  "number_of_replicas": 0
}

# 2. 定期force merge（warm阶段）
POST myapp-2026.04.*/_forcemerge?max_num_segments=1

# 3. 使用索引别名
POST _aliases
{
  "actions": [
    {"add": {"index": "myapp-2026.05.02", "alias": "myapp-current"}},
    {"remove": {"index": "myapp-2026.05.01", "alias": "myapp-current"}}
  ]
}
```

---

## 10. 故障排查与最佳实践

### 10.1 ES集群健康检查

```bash
# 集群状态
curl -s localhost:9200/_cluster/health?pretty

# 节点状态
curl -s localhost:9200/_cat/nodes?v

# 索引状态
curl -s localhost:9200/_cat/indices?v&s=store.size:desc

# 分片分配
curl -s localhost:9200/_cat/shards?v&s=store:desc

# 待处理任务
curl -s localhost:9200/_cluster/pending_tasks

# 热点线程
curl -s localhost:9200/_nodes/hot_threads

# 磁盘使用
curl -s localhost:9200/_cat/allocation?v
```

### 10.2 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 集群RED | 分片未分配 | 检查节点状态、磁盘空间 |
| 查询慢 | 分片过多、数据量大 | 优化分片策略、使用filter |
| 磁盘满 | 日志量过大、保留期过长 | 配置ILM策略、清理旧索引 |
| 写入拒绝 | 队列满、节点过载 | 增加节点、优化写入 |
| OOM | JVM堆太小 | 增加ES_JAVA_OPTS |
| 写入延迟高 | refresh_interval太短 | 调大refresh_interval |

### 10.3 最佳实践

1. **索引命名** - 使用`{service}-{YYYY.MM.dd}`格式
2. **分片大小** - 保持在10-50GB之间
3. **副本数** - 生产至少1，开发可为0
4. **ILM策略** - 必须配置，自动管理生命周期
5. **热温冷架构** - SSD放热数据，HDD放冷数据
6. **日志采样** - 高流量日志考虑采样
7. **字段映射** - 明确指定mapping，避免自动映射
8. **定期维护** - 每周检查集群健康、清理无用索引

---

> 📅 最后更新: 2026-05-02
