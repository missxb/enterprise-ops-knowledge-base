# Pod 生命周期管理

## 概述

Pod 是 Kubernetes 中最小的可部署单元，理解 Pod 的完整生命周期对于应用的可靠运行至关重要。本文涵盖 Init 容器、健康检查探针、终止机制、驱逐策略和 QoS 等关键概念。

---

## 1. Pod 阶段与状态

### 1.1 Pod 阶段（Phase）

| 阶段 | 说明 |
|------|------|
| Pending | Pod 已被接受，但容器尚未全部创建（调度中/拉取镜像中） |
| Running | Pod 已绑定到节点，所有容器已创建，至少一个正在运行 |
| Succeeded | 所有容器正常退出（退出码为 0） |
| Failed | 所有容器已退出，至少一个退出码非 0 |
| Unknown | 无法获取 Pod 状态，通常是与节点通信失败 |

### 1.2 容器状态（State）

| 状态 | 说明 |
|------|------|
| Waiting | 容器未开始运行（拉取镜像、应用 Secret 等） |
| Running | 容器正在执行，无问题 |
| Terminated | 容器已完成执行或失败 |
| Unknown | 无法获取容器状态 |

```bash
# 查看 Pod 详细状态
kubectl describe pod <pod-name>
kubectl get pod <pod-name> -o yaml
```

---

## 2. Init 容器

### 2.1 概述

Init 容器是在主容器启动之前运行的容器，用于执行初始化任务。特点：
- 按顺序串行执行，前一个成功后才运行下一个
- 如果 Init 容器失败，kubelet 会反复重启，直到成功
- Init 容器不支持探针（Probe）
- Pod 的 `restartPolicy` 适用于 Init 容器

### 2.2 使用场景

- 等待依赖服务就绪
- 下载配置文件或初始化数据
- 数据库 schema 迁移
- 注册服务到服务发现系统
- 环境检查和前置条件验证

### 2.3 配置示例

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp-pod
  labels:
    app: myapp
spec:
  initContainers:
  # 等待 MySQL 就绪
  - name: wait-for-mysql
    image: busybox:1.36
    command: ['sh', '-c', 'until nc -z mysql-service 3306; do echo waiting for mysql; sleep 2; done']
  # 等待 Redis 就绪
  - name: wait-for-redis
    image: busybox:1.36
    command: ['sh', '-c', 'until nc -z redis-service 6379; do echo waiting for redis; sleep 2; done']
  # 下载配置文件
  - name: download-config
    image: alpine:3.19
    command: ['wget', '-O', '/config/app.conf', 'https://config.example.com/app.conf']
    volumeMounts:
    - name: config-volume
      mountPath: /config
  containers:
  - name: myapp
    image: myapp:v1
    volumeMounts:
    - name: config-volume
      mountPath: /etc/app
  volumes:
  - name: config-volume
    emptyDir: {}
```

### 2.4 Init 容器的资源限制

```yaml
initContainers:
- name: init-db
  image: postgres:16
  command: ['sh', '-c', 'psql -c "CREATE DATABASE IF NOT EXISTS myapp"']
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
```

---

## 3. 健康检查探针

### 3.1 探针类型

#### 存活探针（Liveness Probe）
- 检测容器是否仍在运行
- 失败时 kubelet 会杀死容器并根据重启策略重启
- 用于检测死锁等应用无法自恢复的故障

#### 就绪探针（Readiness Probe）
- 检测容器是否准备好接受流量
- 失败时 Pod 会从 Service 的 Endpoints 中移除
- 用于应用启动预热、临时过载等场景

#### 启动探针（Startup Probe）
- 检测容器是否已成功启动
- 成功前，Liveness 和 Readiness 探针会被禁用
- 适用于启动时间较长的应用

### 3.2 探针配置方式

#### HTTP GET 探针

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
    httpHeaders:
    - name: X-Custom-Header
      value: liveness-check
  initialDelaySeconds: 15
  periodSeconds: 10
  timeoutSeconds: 5
  successThreshold: 1
  failureThreshold: 3
```

#### TCP Socket 探针

```yaml
readinessProbe:
  tcpSocket:
    port: 3306
  initialDelaySeconds: 5
  periodSeconds: 10
```

#### gRPC 探针

```yaml
livenessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 10
```

#### Exec 探针

```yaml
livenessProbe:
  exec:
    command:
    - cat
    - /tmp/healthy
  initialDelaySeconds: 5
  periodSeconds: 5
```

### 3.3 探针参数详解

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `initialDelaySeconds` | 容器启动后等待多久开始探测 | 0 |
| `periodSeconds` | 探测间隔 | 10 |
| `timeoutSeconds` | 探测超时时间 | 1 |
| `successThreshold` | 连续成功多少次视为健康 | 1 |
| `failureThreshold` | 连续失败多少次视为不健康 | 3 |

### 3.4 探针最佳实践

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: app
        image: web-app:v1
        # 启动探针：给应用最多 5 分钟启动时间
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          failureThreshold: 30
          periodSeconds: 10
        # 存活探针：启动探针成功后生效
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
        # 就绪探针：决定是否接收流量
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
```

---

## 4. Pod 终止机制

### 4.1 终止流程

```
1. 用户删除 Pod 或控制器管理的 Pod 被替换
2. API Server 更新 Pod 的 deletionTimestamp 字段
3. kubelet 检测到 deletionTimestamp，开始终止流程
4. Pod 状态变为 Terminating
5. 从 Service 的 Endpoints 中移除（不再接收新流量）
6. 执行 preStop 钩子（如果配置）
7. 向容器主进程发送 SIGTERM 信号
8. 等待 terminationGracePeriodSeconds
9. 如果容器仍在运行，发送 SIGKILL 强制终止
10. 清理 Pod 资源
```

### 4.2 preStop 钩子

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: graceful-shutdown
spec:
  terminationGracePeriodSeconds: 60
  containers:
  - name: app
    image: myapp:v1
    lifecycle:
      preStop:
        exec:
          command:
          - /bin/sh
          - -c
          - |
            # 优雅关闭：停止接收新请求
            curl -X POST http://localhost:8080/admin/drain
            # 等待现有请求完成
            sleep 15
            # 清理临时文件
            rm -rf /tmp/cache
```

### 4.3 SIGTERM 处理

应用必须正确处理 SIGTERM 信号：

```python
# Python 示例
import signal
import sys

def graceful_shutdown(signum, frame):
    print("收到 SIGTERM，开始优雅关闭...")
    # 停止接收新请求
    server.stop_accepting()
    # 等待现有请求完成
    server.wait_for_completion(timeout=30)
    # 关闭数据库连接
    db.close()
    # 清理资源
    cleanup()
    sys.exit(0)

signal.signal(signal.SIGTERM, graceful_shutdown)
```

```go
// Go 示例
func main() {
    ctx, cancel := context.WithCancel(context.Background())
    
    // 监听系统信号
    sigCh := make(chan os.Signal, 1)
    signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
    
    go func() {
        sig := <-sigCh
        log.Printf("收到信号 %v，开始优雅关闭", sig)
        cancel()
        // 等待现有请求完成
        srv.Shutdown(context.Background())
    }()
    
    // 启动服务
    srv.ListenAndServe()
}
```

### 4.4 terminationGracePeriodSeconds

- 默认值：30 秒
- 推荐值：根据应用关闭时间设置，通常 30-120 秒
- 最大值：理论上无限制，但建议不超过 300 秒

```yaml
spec:
  terminationGracePeriodSeconds: 60
  containers:
  - name: app
    image: myapp:v1
```

### 4.5 强制删除

```bash
# 强制删除 Pod（跳过优雅关闭）
kubectl delete pod <pod-name> --grace-period=0 --force

# 删除 Terminating 状态的 Pod
kubectl patch pod <pod-name> -p '{"metadata":{"finalizers":null}}'
```

---

## 5. Pod 驱逐

### 5.1 节点压力驱逐

当节点资源不足时，kubelet 会驱逐 Pod：

| 资源 | 硬性阈值（默认） | 说明 |
|------|-----------------|------|
| memory.available | 100Mi 或 25% | 可用内存 |
| nodefs.available | 10% | 节点文件系统可用空间 |
| nodefs.inodesFree | 5% | 节点 inode 可用数量 |
| imagefs.available | 15% | 镜像文件系统可用空间 |
| imagefs.inodesFree | 5% | 镜像 inode 可用数量 |
| pid.available | 1000 | 可用 PID 数量 |

```yaml
# kubelet 驱逐配置
evictionHard:
  memory.available: "200Mi"
  nodefs.available: "10%"
  imagefs.available: "15%"
evictionSoft:
  memory.available: "500Mi"
  nodefs.available: "15%"
evictionSoftGracePeriod:
  memory.available: "1m30s"
  nodefs.available: "1m30s"
evictionMaxPodGracePeriod: 60
evictionMinimumReclaim:
  memory.available: "100Mi"
  nodefs.available: "5%"
```

### 5.2 驱逐优先级

kubelet 按以下优先级驱逐 Pod（从高到低）：

1. **BestEffort** + 未使用的 Pod
2. **Burstable** + 超过请求量的 Pod
3. **Guaranteed** + 未使用的 Pod
4. **BestEffort** + 正在使用的 Pod
5. **Burstable** + 正在使用的 Pod

### 5.3 主动驱逐

```bash
# 节点维护前驱逐 Pod
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data --force

# 取消驱逐
kubectl uncordon node-1
```

### 5.4 PDB（Pod Disruption Budget）

PDB 限制自愿中断（如节点维护、升级）时同时不可用的 Pod 数量：

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-app-pdb
spec:
  minAvailable: 2  # 或 maxUnavailable: 1
  selector:
    matchLabels:
      app: web-app
```

---

## 6. QoS（服务质量）等级

### 6.1 QoS 类别

Kubernetes 根据资源请求和限制将 Pod 分为三个 QoS 等级：

#### Guaranteed（保证型）
- 所有容器都设置了 requests 和 limits，且 requests == limits
- 最不容易被驱逐
- 适用于关键业务应用

```yaml
containers:
- name: app
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "500m"      # requests == limits
      memory: "512Mi"   # requests == limits
```

#### Burstable（突发型）
- 至少一个容器设置了 requests 或 limits，且 requests != limits
- 可以临时使用超过 requests 的资源
- 适用于大多数应用

```yaml
containers:
- name: app
  resources:
    requests:
      cpu: "250m"
      memory: "256Mi"
    limits:
      cpu: "1000m"     # limits > requests
      memory: "512Mi"
```

#### BestEffort（尽力型）
- 没有容器设置任何 requests 或 limits
- 最容易被驱逐
- 适用于非关键的批处理任务

```yaml
containers:
- name: app
  # 无 resources 配置
```

### 6.2 QoS 与 OOM Killer

当节点内存不足时，OOM Killer 按以下顺序终止进程：
1. BestEffort Pod
2. Burstable Pod（按内存使用比例）
3. Guaranteed Pod

### 6.3 QoS 调度行为

| QoS 等级 | 调度优先级 | 驱逐优先级 | OOM 优先级 |
|----------|-----------|-----------|-----------|
| Guaranteed | 中 | 最低 | 最低 |
| Burstable | 中 | 中 | 中 |
| BestEffort | 中 | 最高 | 最高 |

---

## 7. Pod 重启策略

### 7.1 RestartPolicy

| 策略 | 说明 | 适用场景 |
|------|------|---------|
| Always（默认） | 容器退出后总是重启 | Deployment、StatefulSet |
| OnFailure | 仅在退出码非 0 时重启 | Job |
| Never | 容器退出后不重启 | 调试/一次性任务 |

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restart-policy-example
spec:
  restartPolicy: OnFailure
  containers:
  - name: app
    image: myapp:v1
```

### 7.2 重启退避策略

kubelet 使用指数退避策略重启容器：
- 第 1 次重启：立即
- 第 2 次重启：10 秒后
- 第 3 次重启：20 秒后
- 第 4 次重启：40 秒后
- ...
- 最大间隔：300 秒（5 分钟）

成功运行 10 分钟后重置退避计时器。

---

## 8. Pod 条件（Conditions）

### 8.1 常见条件

| 条件 | 说明 |
|------|------|
| PodScheduled | Pod 已被调度到节点 |
| Initialized | 所有 Init 容器已完成 |
| ContainersReady | 所有容器已就绪 |
| Ready | Pod 可以提供服务 |

### 8.2 查看 Pod 条件

```bash
kubectl get pod <pod-name> -o jsonpath='{.status.conditions}' | jq .
```

```json
[
  {
    "type": "Initialized",
    "status": "True",
    "lastTransitionTime": "2024-01-01T00:00:00Z"
  },
  {
    "type": "Ready",
    "status": "True",
    "lastTransitionTime": "2024-01-01T00:00:05Z"
  },
  {
    "type": "ContainersReady",
    "status": "True",
    "lastTransitionTime": "2024-01-01T00:00:05Z"
  },
  {
    "type": "PodScheduled",
    "status": "True",
    "lastTransitionTime": "2024-01-01T00:00:00Z"
  }
]
```

---

## 总结

Pod 生命周期管理是 Kubernetes 应用可靠性保障的核心。合理使用 Init 容器进行初始化、配置恰当的健康检查探针、实现优雅关闭、理解 QoS 等级，可以显著提高应用的可用性和稳定性。

---

## 参考资料

- [Kubernetes Pod 生命周期](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/pod-lifecycle/)
- [Init 容器](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/init-containers/)
- [配置存活、就绪和启动探针](https://kubernetes.io/zh-cn/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Pod QoS](https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/pod-qos/)
