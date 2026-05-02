# 📊 监控与可观测性平台

> 从监控到可观测性，构建企业级全栈监控体系

## 概述

监控是运维的眼睛。本模块覆盖从基础设施监控到业务监控的完整方案，基于 **Prometheus + Grafana + ELK + Jaeger** 技术栈。

## 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                    可视化层 (Grafana)                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ 基础设施  │  │ 中间件    │  │ 应用 APM │  │ 业务指标  │   │
│  │ Dashboard │  │ Dashboard │  │ Dashboard │  │ Dashboard │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    告警层 (Alertmanager)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ 邮件通知  │  │ 钉钉/企微 │  │ 短信/电话 │                  │
│  └──────────┘  └──────────┘  └──────────┘                  │
├─────────────────────────────────────────────────────────────┤
│                    存储与查询层                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │Prometheus │  │  Loki    │  │  Jaeger  │  │   ES     │   │
│  │ (指标)    │  │ (日志)   │  │ (链路)   │  │ (全文)   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    采集层                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │Node Exporter│ │ Promtail │  │ OTel Agent│ │ Filebeat │   │
│  │ (节点)    │  │ (日志)   │  │ (链路)   │  │ (日志)   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    数据源层                                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Linux   │  │ MySQL/   │  │   App    │  │  Nginx   │   │
│  │  Server  │  │ Redis    │  │  Service │  │  Proxy   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 监控四大黄金信号 (Google SRE)

| 信号 | 含义 | 示例 |
|------|------|------|
| **延迟 (Latency)** | 请求处理时间 | API P99 响应时间 < 200ms |
| **流量 (Traffic)** | 请求量 | QPS、每秒连接数 |
| **错误 (Errors)** | 错误率 | HTTP 5xx 比例 < 0.1% |
| **饱和度 (Saturation)** | 资源使用率 | CPU < 80%、内存 < 85% |

## USE 方法 (系统资源)

| 信号 | 适用对象 |
|------|----------|
| **Utilization** | CPU、内存、磁盘使用率 |
| **Saturation** | 运行队列长度、磁盘IO队列 |
| **Errors** | 硬件错误、网络丢包 |

## 学习路径

1. [监控理念](docs/01-monitoring-philosophy.md) - 四大黄金信号、USE、RED方法
2. [Prometheus 深入](docs/02-prometheus-deep.md) - 架构、存储、PromQL
3. [Grafana 仪表盘](docs/03-grafana-dashboards.md) - 设计原则、变量、面板
4. [告警管理](docs/04-alertmanager.md) - 路由、分组、抑制、静默
5. [ELK 日志平台](docs/05-elk-stack.md) - 集中式日志方案
6. [Loki 轻量日志](docs/06-loki-log.md) - 轻量级日志方案
7. [分布式追踪](docs/07-jaeger-tracing.md) - Jaeger + OpenTelemetry
8. [APM 监控](docs/08-apm-monitoring.md) - SkyWalking 应用性能监控
9. [黑盒监控](docs/09-blackbox-monitor.md) - 外部探测监控
10. [SLO/SLI/SLA](docs/10-slo-sli-sla.md) - 可靠性实践

## 快速部署

```bash
# 使用 Docker Compose 一键部署监控栈
cd examples/
docker-compose -f monitoring-stack.yml up -d

# 或使用安装脚本
bash scripts/prometheus-install.sh
bash scripts/grafana-install.sh
```

## 告警示例

```yaml
# CPU 使用率超过 85% 持续 5 分钟
- alert: HighCPUUsage
  expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "CPU 使用率过高: {{ $labels.instance }}"
    description: "CPU 使用率 {{ $value }}%，持续超过 5 分钟"
```
