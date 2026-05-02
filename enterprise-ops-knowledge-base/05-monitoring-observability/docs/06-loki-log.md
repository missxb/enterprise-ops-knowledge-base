# Loki Log

> 本文档正在完善中，以下是核心内容

## 概述

Loki 是 Grafana Labs 开发的日志聚合系统，设计灵感来自 Prometheus。与 ELK 相比，Loki 更轻量，只索引标签而非全文。

## 架构

```
App → Promtail → Loki → Grafana
                 ↓
              对象存储 (S3/GCS/MinIO)
```

## 快速部署

```yaml
# docker-compose.yml
version: "3"
services:
  loki:
    image: grafana/loki:2.9.0
    ports:
      - "3100:3100"
    volumes:
      - loki-data:/loki
    command: -config.file=/etc/loki/local-config.yaml

  promtail:
    image: grafana/promtail:2.9.0
    volumes:
      - /var/log:/var/log
      - ./promtail.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml

volumes:
  loki-data:
```

## 最佳实践

1. 使用标签而非全文索引，降低成本
2. 配置合理的保留期（热数据7天，冷数据30天）
3. 使用 LogQL 进行高效查询
4. 与 Prometheus 告警集成
