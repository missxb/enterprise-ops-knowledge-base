# Prometheus 深入

## 架构概述

Prometheus 是一套开源的监控和告警工具集，由 SoundCloud 于 2012 年开发，现为 CNCF 毕业项目。

### 核心组件

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Prometheus  │────▶│   TSDB       │────▶│  PromQL      │
│  Server      │     │  (时序数据库) │     │  (查询语言)   │
└──────┬───────┘     └──────────────┘     └──────────────┘
       │ Pull
       ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Service     │     │  Exporter    │     │  Alertmanager│
│  Discovery   │     │  (指标导出)   │     │  (告警管理)   │
└──────────────┘     └──────────────┘     └──────────────┘
```

### 数据模型

Prometheus 存储的是**时间序列**数据，格式为：
```
<metric_name>{<label_name>=<label_value>, ...} <value> <timestamp>
```

示例：
```
http_requests_total{method="POST", handler="/api/users", status="200"} 1027 1614556800000
node_cpu_seconds_total{instance="10.0.1.5:9100", mode="idle"} 3827430.28 1614556800000
```

### 四种指标类型

| 类型 | 说明 | 适用场景 |
|------|------|----------|
| **Counter** | 只增不减的计数器 | 请求总数、错误总数 |
| **Gauge** | 可增可减的瞬时值 | CPU使用率、内存使用量 |
| **Histogram** | 数据分布统计 | 请求延迟分布 |
| **Summary** | 分位数统计 | P99延迟 |

## PromQL 实战

### 常用函数

```promql
# rate() - 计算 Counter 的每秒增长率
rate(http_requests_total[5m])

# increase() - 计算时间窗口内的增量
increase(http_requests_total[1h])

# histogram_quantile() - 计算分位数
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# predict_linear() - 线性预测
predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0

# absent() - 检测指标是否存在
absent(up{job="mysqld"})

# changes() - 值变化次数
changes(node_boot_time_seconds[1h])
```

### 聚合操作

```promql
# 按实例聚合
sum by(instance) (rate(http_requests_total[5m]))

# 按状态码聚合
sum by(status) (rate(http_requests_total[5m]))

# Top 5
topk(5, rate(http_requests_total[5m]))

# 排序
sort_desc(node_filesystem_avail_bytes)
```

## 存储原理

### TSDB (Time Series Database)

- **Block**: 2小时的数据块
- **WAL**: 预写日志，保证数据持久性
- **Compaction**: 后台压缩，合并小块为大块
- **Retention**: 数据保留策略

### 存储容量估算

```
每条时间序列 ≈ 1-2 bytes/sample
每天数据量 = 活跃序列数 × 采集频率 × 86400 × 1.5 bytes

示例：
- 10,000 个活跃序列
- 15秒采集间隔
- 每天 = 10000 × (86400/15) × 1.5 ≈ 86.4 MB/天
- 保留 15 天 ≈ 1.3 GB
```

## 服务发现

### 文件发现

```yaml
scrape_configs:
  - job_name: 'file_sd'
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets/*.json'
        refresh_interval: 30s
```

targets.json:
```json
[{
  "targets": ["10.0.1.5:9100", "10.0.1.6:9100"],
  "labels": {
    "env": "production",
    "role": "webserver"
  }
}]
```

### Kubernetes 服务发现

```yaml
scrape_configs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: (.+)
        replacement: ${1}:${2}
```

## 最佳实践

1. **标签控制**：单个指标标签基数不超过 10,000
2. **采集间隔**：基础设施 15-30s，业务指标 10-15s
3. **高可用**：部署 2 个 Prometheus 实例，相同配置
4. **远程存储**：长期数据写入 Thanos/VictoriaMetrics
5. **联邦集群**：大规模使用 Prometheus Federation

## 生产配置示例

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s
  external_labels:
    cluster: 'production'
    replica: 'prometheus-01'

rule_files:
  - '/etc/prometheus/rules/*.yml'

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - 'alertmanager-01:9093'
          - 'alertmanager-02:9093'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    file_sd_configs:
      - files: ['/etc/prometheus/targets/nodes.json']
```
