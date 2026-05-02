# 监控理念与方法论

## 为什么需要监控

监控的核心目的是**快速发现问题、定位根因、量化影响**。没有监控的系统就像没有仪表盘的汽车——你不知道出了问题，直到抛锚。

## 三大监控方法论

### 1. 四大黄金信号 (Google SRE)

来自 Google SRE 手册，适用于**面向用户的服务**：

| 信号 | 定义 | 指标示例 | 告警阈值参考 |
|------|------|----------|-------------|
| **延迟 Latency** | 服务请求所需时间 | `http_request_duration_seconds` | P99 > 500ms |
| **流量 Traffic** | 系统上的工作量 | `http_requests_total` | QPS 突增 200% |
| **错误 Errors** | 失败请求的速率 | `http_requests_total{status=~"5.."}` | 5xx 率 > 1% |
| **饱和度 Saturation** | 资源使用程度 | `node_cpu_seconds_total` | CPU > 85% |

**实践建议**：先从延迟和错误开始，这两个对用户体验影响最直接。

### 2. USE 方法 (Brendan Gregg)

适用于**系统资源监控**（CPU、内存、磁盘、网络）：

| 资源 | Utilization (利用率) | Saturation (饱和度) | Errors (错误) |
|------|---------------------|---------------------|---------------|
| CPU | `node_cpu_seconds_total` | `node_procs_running` | `node_cpu_core_throttles_total` |
| 内存 | `node_memory_MemAvailable_bytes` | `node_vmstat_pswpin` | `node_memory_OOM_kill_total` |
| 磁盘 | `node_disk_io_time_seconds_total` | `node_disk_io_time_weighted_seconds_total` | `node_disk_io_errors_total` |
| 网络 | `node_network_receive_bytes_total` | `node_netstat_TcpExt_TCPSynDrop` | `node_network_receive_errs_total` |

### 3. RED 方法 (Tom Wilkie)

适用于**微服务监控**：

| 信号 | 定义 | 指标 |
|------|------|------|
| **Rate** | 每秒请求数 | `rate(http_requests_total[5m])` |
| **Errors** | 失败请求率 | `rate(http_requests_total{status=~"5.."}[5m])` |
| **Duration** | 请求延迟分布 | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))` |

## 监控层次

```
┌───────────────────────────────┐
│  业务监控 (Business Metrics)   │  ← 订单量、支付成功率、转化率
├───────────────────────────────┤
│  应用监控 (APM)               │  ← 响应时间、错误率、吞吐量
├───────────────────────────────┤
│  中间件监控 (Middleware)       │  ← MySQL QPS、Redis 命中率、Nginx 连接
├───────────────────────────────┤
│  基础设施监控 (Infrastructure) │  ← CPU、内存、磁盘、网络
└───────────────────────────────┘
```

## 告警设计原则

### 1. 告警分级

| 级别 | 含义 | 响应时间 | 通知方式 |
|------|------|----------|----------|
| **P0 Critical** | 服务完全不可用 | 5分钟内 | 电话 + 短信 + 钉钉 |
| **P1 Major** | 功能严重受损 | 15分钟内 | 短信 + 钉钉 |
| **P2 Warning** | 性能下降或即将出问题 | 1小时内 | 钉钉/邮件 |
| **P3 Info** | 需要关注但不紧急 | 下一工作日 | 邮件 |

### 2. 告警命名规范

```
<severity>_<component>_<metric>_<condition>

示例:
- P1_MySQL_SlaveDelay_Seconds > 30
- P2_Node_CPU_Usage > 85%
- P0_Nginx_5xxRate > 5%
```

### 3. 避免告警疲劳

- **去重**：相同告警只发一次
- **分组**：相关告警合并通知
- **抑制**：子告警被父告警抑制
- **静默**：维护期间静默已知告警
- **阈值合理**：避免频繁抖动

## 常用监控指标速查

### Linux 系统

```promql
# CPU 使用率
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 内存使用率
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 磁盘使用率
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# 磁盘 IOPS
rate(node_disk_reads_completed_total[5m]) + rate(node_disk_writes_completed_total[5m])

# 网络带宽
rate(node_network_receive_bytes_total{device="eth0"}[5m]) * 8
rate(node_network_transmit_bytes_total{device="eth0"}[5m]) * 8
```

### MySQL

```promql
# QPS
rate(mysql_global_status_queries[5m])

# 慢查询
rate(mysql_global_status_slow_queries[5m])

# 连接使用率
mysql_global_status_threads_connected / mysql_global_variables_max_connections * 100

# 主从延迟
mysql_slave_status_seconds_behind_master
```

### Redis

```promql
# 命中率
rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) * 100

# 内存使用
redis_memory_used_bytes / redis_memory_max_bytes * 100

# 连接数
redis_connected_clients
```

## 工具选型

| 需求 | 推荐方案 | 备选 |
|------|----------|------|
| 指标监控 | Prometheus + Grafana | Zabbix, Datadog |
| 日志平台 | ELK Stack | Loki + Grafana, Splunk |
| 链路追踪 | Jaeger | Zipkin, SkyWalking |
| APM | SkyWalking | Pinpoint, New Relic |
| 黑盒监控 | Blackbox Exporter | Uptime Robot, Pingdom |
| 告警通知 | Alertmanager | PagerDuty, OpsGenie |
