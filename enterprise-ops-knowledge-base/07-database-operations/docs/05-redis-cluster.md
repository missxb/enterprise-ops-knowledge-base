# Redis 集群部署

## 部署方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **主从复制** | 简单、读写分离 | 不能自动故障转移 | 小规模 |
| **Sentinel** | 自动故障转移 | 单主写入 | 中等规模 |
| **Cluster** | 分片、高可用 | 客户端支持 | 大规模 |

## Redis Cluster 部署

### 架构

```
6 节点 (3主3从):
Master1 ←→ Slave1 (16384 slots: 0-5460)
Master2 ←→ Slave2 (16384 slots: 5461-10922)
Master3 ←→ Slave3 (16384 slots: 10923-16383)
```

### 部署步骤

```bash
# 1. 安装 Redis
yum install -y redis

# 2. 配置每个节点 (redis.conf)
port 6379
cluster-enabled yes
cluster-config-file nodes-6379.conf
cluster-node-timeout 5000
appendonly yes
maxmemory 8gb
maxmemory-policy allkeys-lru

# 3. 启动所有节点
for port in 6379 6380 6381 6382 6383 6384; do
    redis-server /etc/redis/redis-${port}.conf --daemonize yes
done

# 4. 创建集群
redis-cli --cluster create \
    10.0.1.10:6379 10.0.1.10:6380 \
    10.0.1.11:6379 10.0.1.11:6380 \
    10.0.1.12:6379 10.0.1.12:6380 \
    --cluster-replicas 1

# 5. 验证集群
redis-cli -c -h 10.0.1.10 -p 6379 cluster info
redis-cli -c -h 10.0.1.10 -p 6379 cluster nodes
```

### 常用操作

```bash
# 集群扩容
redis-cli --cluster add-node new_host:6379 existing_host:6379
redis-cli --cluster reshard existing_host:6379

# 集群缩容
redis-cli --cluster del-node host:6379 node_id

# 集群修复
redis-cli --cluster fix host:6379

# 集群检查
redis-cli --cluster check host:6379
```

## Redis Sentinel

```bash
# sentinel.conf
port 26379
sentinel monitor mymaster 10.0.1.10 6379 2
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 60000
sentinel parallel-syncs mymaster 1

# 启动
redis-sentinel /etc/redis/sentinel.conf
```
