# ELK 日志平台

## 概述

ELK Stack 是 Elasticsearch + Logstash + Kibana 的组合，是目前最流行的集中式日志解决方案。

## 架构

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ 应用/系统 │───▶│ Filebeat │───▶│ Logstash │───▶│Elasticsearch│───▶│ Kibana  │
│  日志     │    │ (采集)   │    │ (处理)   │    │  (存储)   │    │ (可视化) │
└──────────┘    └──────────┘    └──────────┘    └──────────┘

推荐生产架构：
App → Filebeat → Kafka → Logstash → Elasticsearch → Kibana
```

## Elasticsearch 安装配置

### docker-compose 部署

```yaml
version: '3'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
    volumes:
      - es-data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
    deploy:
      resources:
        limits:
          memory: 4G

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch

volumes:
  es-data:
```

### 生产配置

```yaml
# elasticsearch.yml
cluster.name: ops-logs
node.name: es-node-01
path.data: /data/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
transport.port: 9300

# 集群配置
discovery.seed_hosts: ["es-node-01", "es-node-02", "es-node-03"]
cluster.initial_master_nodes: ["es-node-01", "es-node-02", "es-node-03"]

# JVM 配置 (jvm.options)
-Xms16g
-Xmx16g
```

## Logstash 配置

```ruby
# logstash.conf
input {
  beats {
    port => 5044
  }
}

filter {
  # 解析 Nginx 日志
  if [fields][log_type] == "nginx" {
    grok {
      match => { "message" => "%{COMBINEDAPACHELOG}" }
    }
    date {
      match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z"]
    }
    geoip {
      source => "clientip"
    }
  }
  
  # 解析应用 JSON 日志
  if [fields][log_type] == "app" {
    json {
      source => "message"
    }
    mutate {
      add_field => { "app_name" => "%{[fields][app_name]}" }
    }
  }
  
  # 解析 MySQL 慢查询
  if [fields][log_type] == "mysql-slow" {
    multiline {
      pattern => "^# Time:"
      negate => true
      what => "previous"
    }
  }
}

output {
  elasticsearch {
    hosts => ["es-node-01:9200", "es-node-02:9200"]
    index => "%{[fields][log_type]}-%{+YYYY.MM.dd}"
  }
}
```

## Filebeat 配置

```yaml
# filebeat.yml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/nginx/access.log
    fields:
      log_type: nginx
    multiline:
      pattern: '^\d{4}-\d{2}-\d{2}'
      negate: true
      what: previous

  - type: log
    enabled: true
    paths:
      - /var/log/app/*.log
    fields:
      log_type: app
      app_name: user-service

output.logstash:
  hosts: ["logstash:5044"]
  loadbalance: true

logging.level: info
logging.to_files: true
```

## 索引管理

### ILM (Index Lifecycle Management)

```json
PUT _ilm/policy/ops-logs-policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "50GB",
            "max_age": "1d"
          }
        }
      },
      "warm": {
        "min_age": "3d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": { "delete": {} }
      }
    }
  }
}
```

## 常用查询

```json
# 查看集群健康
GET _cluster/health

# 查看索引
GET _cat/indices?v&s=store.size:desc

# 搜索错误日志
GET nginx-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "response": 500 } },
        { "range": { "@timestamp": { "gte": "now-1h" } } }
      ]
    }
  },
  "size": 100,
  "sort": [{ "@timestamp": "desc" }]
}
```

## 性能优化

1. **分片大小**：单个分片 10-50GB
2. **副本数量**：生产至少 1 个副本
3. **刷新间隔**：写入密集场景可调大 `refresh_interval`
4. **JVM 内存**：不超过物理内存的 50%，最大 32GB
5. **SSD 存储**：热数据使用 SSD
