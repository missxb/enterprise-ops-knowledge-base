# Alertmanager 告警管理

## 概述

Alertmanager 负责接收 Prometheus 的告警，进行**去重、分组、路由、抑制、静默**处理，然后发送到通知渠道。

## 核心功能

### 1. 路由 (Routing)

根据标签将告警路由到不同的接收器：

```yaml
route:
  receiver: 'default-receiver'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  
  routes:
    # P0 紧急告警 → 电话
    - match:
        severity: critical
      receiver: 'phone-call'
      repeat_interval: 15m
      
    # 数据库告警 → DBA 团队
    - match:
        team: dba
      receiver: 'dba-team'
      
    # 网络告警 → 网络团队
    - match:
        team: network
      receiver: 'network-team'
      
    # 测试环境 → 只发钉钉
    - match:
        env: staging
      receiver: 'staging-dingtalk'
```

### 2. 接收器 (Receivers)

```yaml
receivers:
  - name: 'default-receiver'
    webhook_configs:
      - url: 'http://dingtalk-webhook:8060/dingtalk/ops/send'
        send_resolved: true
        
  - name: 'phone-call'
    webhook_configs:
      - url: 'http://alert-gateway/api/phone-call'
    email_configs:
      - to: 'oncall@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.example.com:587'
        
  - name: 'dba-team'
    webhook_configs:
      - url: 'http://dingtalk-webhook:8060/dingtalk/dba/send'
```

### 3. 抑制 (Inhibition)

当高优先级告警触发时，抑制低优先级告警：

```yaml
inhibit_rules:
  # 如果有 P0 告警，抑制同服务的 P2 告警
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster', 'service']
```

### 4. 静默 (Silence)

维护期间临时静默告警：
```bash
# 创建静默（2小时）
amtool silence add alertname="HighCPU" instance="10.0.1.5:9090" \
  --duration=2h \
  --comment="系统维护窗口"

# 查看活跃静默
amtool silence query

# 删除静默
amtool silence expire <silence-id>
```

## 钉钉/企业微信集成

### 钉钉 Webhook

```yaml
# alertmanager.yml
receivers:
  - name: 'dingtalk-ops'
    webhook_configs:
      - url: 'http://dingtalk-webhook:8060/dingtalk/ops/send'
        send_resolved: true
```

部署 dingtalk-webhook 组件：
```bash
docker run -d --name dingtalk-webhook \
  -e PROMETHEUS_URL=http://alertmanager:9093 \
  -p 8060:8060 \
  timonwong/prometheus-webhook-dingtalk
```

### 企业微信 Webhook

```yaml
receivers:
  - name: 'wecom-ops'
    wechat_configs:
      - corp_id: 'ww1234567890'
        to_party: '2'
        agent_id: '1000002'
        api_secret: '<secret>'
```

## 告警模板

```yaml
templates:
  - '/etc/alertmanager/templates/*.tmpl'
```

自定义模板：
```
{{ define "dingtalk.title" }}
[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .CommonLabels.alertname }}
{{ end }}

{{ define "dingtalk.content" }}
{{ range .Alerts }}
**告警名称**: {{ .Labels.alertname }}
**告警级别**: {{ .Labels.severity }}
**实例**: {{ .Labels.instance }}
**描述**: {{ .Annotations.description }}
**开始时间**: {{ .StartsAt.Format "2006-01-02 15:04:05" }}
{{ if .EndsAt }}**结束时间**: {{ .EndsAt.Format "2006-01-02 15:04:05" }}{{ end }}
---
{{ end }}
{{ end }}
```

## 最佳实践

1. **合理分组**：按 `alertname + cluster + service` 分组
2. **告警收敛**：设置 `group_wait` 和 `repeat_interval` 避免风暴
3. **分级路由**：不同级别走不同通知渠道
4. **抑制规则**：避免相关告警重复通知
5. **Webhook 限流**：钉钉/企微有频率限制，需要队列缓冲
