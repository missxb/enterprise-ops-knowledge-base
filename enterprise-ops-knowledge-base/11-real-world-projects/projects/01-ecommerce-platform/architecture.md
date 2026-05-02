# 电商平台架构设计

## 业务架构

```
┌─────────────────────────────────────────────────────────────┐
│                        CDN + WAF                            │
├─────────────────────────────────────────────────────────────┤
│                    负载均衡 (SLB/NLB)                        │
├──────────┬──────────┬──────────┬──────────┬─────────────────┤
│ 用户服务 │ 商品服务 │ 订单服务 │ 支付服务 │  库存服务        │
│ user-svc │ item-svc │ order-svc│ pay-svc  │  stock-svc      │
├──────────┴──────────┴──────────┴──────────┴─────────────────┤
│                    消息队列 (RocketMQ/Kafka)                  │
├──────────┬──────────┬──────────┬────────────────────────────┤
│  MySQL   │  Redis   │   ES    │  MongoDB                   │
│ (订单库)  │ (缓存)   │ (搜索)  │ (日志/评论)                │
└──────────┴──────────┴──────────┴────────────────────────────┘
```

## 技术选型

| 层次 | 技术 | 说明 |
|------|------|------|
| 接入层 | Nginx + CDN | 静态资源加速、WAF 防护 |
| 网关层 | Spring Cloud Gateway | 路由、限流、鉴权 |
| 服务层 | Spring Cloud + K8s | 微服务部署 |
| 数据层 | MySQL + Redis + ES | 读写分离、缓存、搜索 |
| 消息层 | RocketMQ | 异步解耦、削峰填谷 |
| 监控层 | Prometheus + SkyWalking | 全链路监控 |

## 容量规划 (大促场景)

| 组件 | 日常 | 大促 | 弹性策略 |
|------|------|------|----------|
| Web 服务器 | 10台 | 50台 | HPA 自动扩容 |
| MySQL | 主1从3 | 主1从3+只读实例 | RDS 只读实例 |
| Redis | 集群 6节点 | 集群 12节点 | Redis 集群扩容 |
| RocketMQ | 4 Broker | 8 Broker | 预先扩容 |
| 带宽 | 100Mbps | 1Gbps | CDN + 弹性带宽 |

## 部署方案

```yaml
# K8s 部署示例 - 用户服务
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
      - name: user-service
        image: registry.example.com/user-service:v1.2.0
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2000m"
            memory: "2Gi"
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: user-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: user-service
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## 大促保障 Checklist

- [ ] 容量评估与压测完成
- [ ] 弹性伸缩策略配置
- [ ] 限流降级规则配置
- [ ] 数据库只读实例就绪
- [ ] Redis 预热完成
- [ ] CDN 预热完成
- [ ] 监控告警就绪
- [ ] 值班人员安排
- [ ] 应急预案演练
- [ ] 回滚方案确认
