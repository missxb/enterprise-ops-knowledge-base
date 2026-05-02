# Jaeger Tracing

> 本文档正在完善中，以下是核心内容

## 概述

Jaeger 是 Uber 开源的分布式追踪系统，用于微服务架构下的请求链路追踪。

## 架构

```
App (OTel SDK) → OTel Collector → Jaeger → Storage (ES/Cassandra)
                                      ↓
                                   Jaeger UI
```

## 快速部署

```bash
# 一键部署 Jaeger All-in-One
docker run -d --name jaeger   -e COLLECTOR_OTLP_ENABLED=true   -p 16686:16686   -p 4317:4317   -p 4318:4318   jaegertracing/all-in-one:1.52
```

## 最佳实践

1. 采样策略：生产环境使用概率采样（1-10%）
2. 使用 OTel Collector 作为中间层
3. 长期存储使用 Elasticsearch
4. 与 Prometheus/Grafana 联动
