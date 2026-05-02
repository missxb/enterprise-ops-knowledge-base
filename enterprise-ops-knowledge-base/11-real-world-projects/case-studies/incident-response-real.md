# 真实故障处理案例

## 案例一：数据库主从延迟导致订单超时

### 现象
- 用户反馈下单后订单状态不更新
- 监控显示 MySQL 主从延迟 > 300 秒
- 部分订单超时

### 排查过程

```bash
# 1. 检查主从状态
mysql -e "SHOW SLAVE STATUS\G" | grep -E "Seconds_Behind|Slave_SQL_Running|Last_Error"

# 2. 发现 SQL 线程阻塞
# Slave_SQL_Running: Yes
# Seconds_Behind_Master: 312
# Last_Error: (无错误，只是慢)

# 3. 检查从库是否有大事务
mysql -e "SELECT * FROM information_schema.processlist WHERE COMMAND != 'Sleep' ORDER BY TIME DESC LIMIT 10"

# 4. 发现一个大表 ALTER 操作阻塞了复制
# 从库正在执行 ALTER TABLE orders ADD INDEX idx_user (user_id)
# 该表有 5000 万行
```

### 处理

```bash
# 1. 临时方案：跳过该 DDL，先恢复业务
# 在从库执行
STOP SLAVE;
SET GLOBAL sql_slave_skip_counter = 1;
START SLAVE;

# 2. 根本方案：使用 pt-online-schema-change 重新加索引
pt-online-schema-change --alter "ADD INDEX idx_user (user_id)" \
    --execute D=orders,t=orders \
    h=localhost,u=admin,p=password

# 3. 后续改进
# - 所有 DDL 操作必须使用 pt-osc 或 gh-ost
# - 大表变更需要在低峰期执行
# - 设置 slave_parallel_workers = 4
```

## 案例二：Redis 内存溢出导致服务雪崩

### 现象
- 多个微服务同时报错
- Redis 连接超时
- 监控显示 Redis 内存使用率 100%

### 排查

```bash
# 1. 检查 Redis 内存
redis-cli info memory | grep used_memory_human

# 2. 检查大 key
redis-cli --bigkeys

# 3. 发现一个巨大的 Hash key
# user:session:all -> 2GB, 包含 2000 万个 field
# 原因：开发误将所有 session 存入一个 Hash
```

### 处理

```bash
# 1. 紧急清理：删除大 key（异步删除）
redis-cli UNLINK user:session:all

# 2. 调整 Redis 内存策略
redis-cli CONFIG SET maxmemory-policy allkeys-lru

# 3. 设置内存上限
redis-cli CONFIG SET maxmemory 8gb

# 4. 根本修复
# - 修改代码，session 按用户分散存储
# - 设置 TTL 过期
# - 增加 Redis 内存告警阈值
```

## 案例三：K8s 节点 NotReady 导致 Pod 驱逐

### 现象
- 部分服务不可用
- K8s 告警节点 NotReady
- 大量 Pod 处于 Pending 状态

### 排查

```bash
# 1. 检查节点状态
kubectl get nodes
# node-03   NotReady   worker   5d

# 2. 查看节点详情
kubectl describe node node-03
# Conditions:
#   Type: DiskPressure  Status: True
# 原因：磁盘使用率 > 85%

# 3. 检查磁盘
ssh node-03 "df -h"
# /dev/sda1  85% /data

# 4. 找到大文件
ssh node-03 "du -sh /data/* | sort -rh | head"
# 50G  /data/container-logs
```

### 处理

```bash
# 1. 清理日志
ssh node-03 "find /data/container-logs -mtime +3 -delete"

# 2. 清理无用镜像
ssh node-03 "crictl rmi --prune"

# 3. 恢复节点
kubectl uncordon node-03

# 4. 预防措施
# - 配置日志轮转
# - 设置磁盘告警阈值 75%
# - 使用远程日志存储
```

## 经验总结

| 故障类型 | 根因 | 改进措施 |
|----------|------|----------|
| 主从延迟 | 大表 DDL 阻塞 | 使用 pt-osc，低峰期执行 |
| Redis OOM | 大 key + 无 TTL | 分散存储，设置过期 |
| 节点 NotReady | 磁盘满 | 日志轮转，提前告警 |
