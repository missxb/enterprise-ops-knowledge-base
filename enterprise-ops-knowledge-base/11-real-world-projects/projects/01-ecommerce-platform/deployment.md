# 电商平台部署方案

## 部署架构

```
┌─────────────────────────────────────────────────┐
│                  GitLab CI / ArgoCD              │
├─────────────────────────────────────────────────┤
│              Kubernetes Cluster                  │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  │User  │ │Item  │ │Order │ │Pay   │           │
│  │Svc   │ │Svc   │ │Svc   │ │Svc   │           │
│  │x3    │ │x3    │ │x3    │ │x3    │           │
│  └──────┘ └──────┘ └──────┘ └──────┘           │
│  ┌──────────────────────────────────┐           │
│  │    Nginx Ingress Controller      │           │
│  └──────────────────────────────────┘           │
├─────────────────────────────────────────────────┤
│  MySQL   │  Redis   │  ES    │  RocketMQ        │
│  主从     │  集群    │  集群  │  Broker          │
└─────────────────────────────────────────────────┘
```

## 灰度发布方案

### 基于 Nginx Ingress 的灰度

```yaml
# 灰度版本 Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service-canary
  annotations:
    kubernetes.io/change-cause: "灰度发布 v1.3.0"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: user-service
      version: canary
  template:
    metadata:
      labels:
        app: user-service
        version: canary
    spec:
      containers:
      - name: user-service
        image: registry.example.com/user-service:v1.3.0
---
# 灰度 Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: user-service-canary
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"
spec:
  ingressClassName: nginx
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /api/users
        pathType: Prefix
        backend:
          service:
            name: user-service-canary
            port:
              number: 80
```

## 回滚方案

```bash
# 快速回滚
kubectl rollout undo deployment/user-service -n production
kubectl rollout status deployment/user-service -n production

# 回滚到指定版本
kubectl rollout undo deployment/user-service --to-revision=3 -n production

# 查看版本历史
kubectl rollout history deployment/user-service -n production
```

## 大促扩容方案

```bash
# 提前扩容（大促前2小时）
kubectl scale deployment/user-service --replicas=10 -n production
kubectl scale deployment/order-service --replicas=10 -n production
kubectl scale deployment/item-service --replicas=8 -n production

# HPA 会在大促后自动缩容
# 也可以手动缩容
kubectl scale deployment/user-service --replicas=3 -n production
```
