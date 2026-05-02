# Blackbox Monitor

> 本文档正在完善中，以下是核心内容

## 概述

Blackbox Exporter 通过 HTTP、TCP、ICMP、DNS 等协议对目标进行外部探测监控。

## 架构

```
Blackbox Exporter → 目标 (HTTP/TCP/ICMP/DNS)
       ↓
  Prometheus → Grafana
```

## 快速部署

```yaml
# prometheus.yml
scrape_configs:
  - job_name: "blackbox-http"
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
```

## 最佳实践

1. 探测间隔不要太短（30-60s）
2. 多地域探测避免误报
3. 配置合理的超时时间
4. 关注 SSL 证书过期
