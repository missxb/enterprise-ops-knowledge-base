# Grafana 仪表盘设计

## 概述

Grafana 是最流行的开源可视化平台，支持多种数据源（Prometheus、Elasticsearch、Loki、InfluxDB 等）。

## 仪表盘设计原则

### 1. 分层设计

```
Layer 1: Overview (总览)
├── 服务健康状态概览
├── 关键 SLI 指标
└── 告警状态汇总

Layer 2: Service (服务层)
├── 单个服务的 RED 指标
├── 依赖服务状态
└── 资源使用情况

Layer 3: Detail (详情层)
├── 单实例详细指标
├── JVM/Runtime 指标
└── 排查用详细指标
```

### 2. 面板类型选择

| 数据类型 | 推荐面板 | 场景 |
|----------|----------|------|
| 趋势 | Time Series | CPU/内存/请求量变化 |
| 单值 | Stat/Gauge | 当前连接数、健康状态 |
| 分布 | Heatmap | 延迟分布、直方图 |
| 表格 | Table | 实例列表、TOP N |
| 日志 | Logs | 实时日志流 |

### 3. 变量 (Variables)

```yaml
# 集群变量
- name: cluster
  type: query
  query: label_values(up, cluster)
  refresh: on_time_range_change

# 实例变量（依赖集群选择）
- name: instance
  type: query
  query: label_values(up{cluster="$cluster"}, instance)
  multi: true
```

## 常用面板 JSON

### 节点 CPU 面板

```json
{
  "title": "CPU 使用率",
  "type": "timeseries",
  "datasource": "Prometheus",
  "targets": [{
    "expr": "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\", instance=~\"$instance\"}[5m])) * 100)",
    "legendFormat": "{{instance}}"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "min": 0,
      "max": 100,
      "thresholds": {
        "steps": [
          {"value": null, "color": "green"},
          {"value": 70, "color": "yellow"},
          {"value": 85, "color": "red"}
        ]
      }
    }
  }
}
```

### HTTP 请求面板

```json
{
  "title": "HTTP 请求速率",
  "type": "timeseries",
  "targets": [{
    "expr": "sum by(status) (rate(http_requests_total{job=\"$service\"}[5m]))",
    "legendFormat": "{{status}}"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "reqps"
    }
  }
}
```

## 告警规则配置

Grafana 支持在面板上直接配置告警：

```json
{
  "alert": {
    "name": "CPU 使用率过高",
    "conditions": [{
      "evaluator": { "params": [85], "type": "gt" },
      "operator": { "type": "and" },
      "query": { "params": ["A", "5m", "now"] },
      "reducer": { "params": [], "type": "avg" }
    }],
    "frequency": "1m",
    "handler": 1,
    "notifications": [{"uid": "team-ops"}]
  }
}
```

## Provisioning (自动化配置)

### datasource 自动配置

```yaml
# grafana/provisioning/datasources/datasources.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false
```

### dashboard 自动配置

```yaml
# grafana/provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: 'Infrastructure'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

## 最佳实践

1. **使用变量**：让仪表盘可复用于不同环境/实例
2. **颜色编码**：绿色→正常、黄色→警告、红色→危险
3. **单位设置**：正确设置面板单位（bytes, seconds, percent）
4. **链接关联**：面板间建立 drill-down 链接
5. **版本控制**：仪表盘 JSON 纳入 Git 管理
6. **性能优化**：避免单个面板查询过多时间序列
