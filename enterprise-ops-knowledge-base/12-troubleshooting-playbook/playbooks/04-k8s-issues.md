# Kubernetes 问题排查

## Pod 常见问题

### Pod Pending

```bash
# 查看原因
kubectl describe pod <pod-name> -n <namespace>

# 常见原因及解决：
# 1. 资源不足
#    解决: 扩容节点或调整 request
kubectl top nodes
kubectl describe nodes | grep -A5 "Allocated resources"

# 2. 节点选择器不匹配
#    解决: 检查 nodeSelector/nodeAffinity
kubectl get pod <pod-name> -o yaml | grep -A5 nodeSelector

# 3. PVC 未绑定
#    解决: 检查 PV/PVC 状态
kubectl get pv,pvc

# 4. 污点不容忍
#    解决: 添加容忍或移除污点
kubectl describe nodes | grep Taints
kubectl taint nodes <node> key:NoSchedule-
```

### Pod CrashLoopBackOff

```bash
# 查看日志
kubectl logs <pod-name> -n <namespace> --previous
kubectl logs <pod-name> -n <namespace> -c <container>

# 常见原因：
# 1. 应用启动失败 → 检查日志
# 2. 配置错误 → 检查 ConfigMap/Secret
# 3. 依赖服务不可用 → 检查 Service/Endpoint
# 4. 资源限制过低 → 调整 limits
```

### Pod OOMKilled

```bash
# 查看 OOM 事件
kubectl describe pod <pod-name> | grep -A3 "Last State"

# 解决方案：
# 1. 增加内存 limits
# 2. 优化应用内存使用
# 3. 检查内存泄漏
```

### Pod ImagePullBackOff

```bash
# 检查镜像是否存在
kubectl describe pod <pod-name> | grep -A5 Events

# 常见原因：
# 1. 镜像名/tag 错误
# 2. 私有仓库认证失败 → 检查 imagePullSecrets
# 3. 网络问题 → 检查节点能否访问 registry
```

## Node 常见问题

### Node NotReady

```bash
# 查看节点状态
kubectl describe node <node-name>

# 检查 kubelet
systemctl status kubelet
journalctl -u kubelet -f

# 常见原因：
# 1. kubelet 挂了 → 重启 kubelet
# 2. 容器运行时故障 → 检查 containerd/docker
# 3. 磁盘/内存压力 → 清理资源
# 4. 网络不通 → 检查网络插件
```

## 网络问题排查

```bash
# DNS 排查
kubectl run debug --image=busybox --rm -it -- nslookup kubernetes.default
kubectl run debug --image=busybox --rm -it -- nslookup <service-name>.<namespace>.svc.cluster.local

# Service 排查
kubectl get endpoints <service-name>
kubectl describe svc <service-name>

# 网络策略排查
kubectl get networkpolicy -A
```

## 存储问题排查

```bash
# PVC 状态
kubectl get pvc -A
kubectl describe pvc <pvc-name>

# PV 状态
kubectl get pv

# 检查 StorageClass
kubectl get storageclass
```

## 常用调试命令

```bash
# 进入 Pod 调试
kubectl exec -it <pod-name> -- /bin/sh

# 临时调试容器
kubectl debug -it <pod-name> --image=busybox --target=<container>

# 查看事件
kubectl get events --sort-by=.metadata.creationTimestamp -A

# 资源使用
kubectl top pods -A --sort-by=memory
kubectl top nodes
```
