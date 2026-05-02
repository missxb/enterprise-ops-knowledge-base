# 双十一大促准备

## 背景

某电商平台，日活用户 500 万，预计大促峰值 QPS 为日常的 10 倍。

## 准备工作

### T-30天：容量规划

```bash
# 压测目标
# 日常 QPS: 5,000
# 大促目标 QPS: 50,000
# 冗余系数: 1.5x → 需要支撑 75,000 QPS

# 压测工具选择：JMeter / Locust / wrk
# 压测场景：
# 1. 商品详情页（读多写少）
# 2. 下单流程（核心链路）
# 3. 支付流程（高可用要求）
# 4. 库存扣减（高并发写）
```

### T-14天：架构优化

1. **缓存预热**
```bash
# Redis 预热热门商品数据
python warmup_cache.py --top=10000 --batch=100
```

2. **CDN 预热**
```bash
# 预热静态资源
aliyun cdn RefreshObjectCaches --ObjectPath="https://cdn.example.com/static/" --ObjectType=Directory
```

3. **数据库优化**
```sql
-- 添加只读实例
-- 优化慢查询
-- 添加缺失索引
EXPLAIN SELECT * FROM orders WHERE user_id = ? AND status = ?;
CREATE INDEX idx_user_status ON orders(user_id, status);
```

### T-7天：限流降级配置

```yaml
# Sentinel 限流规则
flow:
  - resource: /api/orders/create
    count: 1000        # QPS 限制
    strategy: 0        # 直接拒绝
    controlBehavior: 0 # 快速失败
  - resource: /api/items/detail
    count: 10000
    strategy: 0

# 降级规则
degrade:
  - resource: /api/recommendations
    count: 0.5         # 错误率 50%
    timeWindow: 30     # 熔断 30 秒
    minRequestAmount: 100
```

### T-1天：最终检查

- [ ] 所有服务副本数已扩容
- [ ] 限流降级规则已配置
- [ ] Redis 预热完成
- [ ] CDN 预热完成
- [ ] 数据库只读实例就绪
- [ ] 监控告警阈值已调整
- [ ] 值班人员已安排
- [ ] 应急预案已演练
- [ ] 回滚方案已确认

### D-Day：值班要点

```
值班人员分工：
- 总指挥：技术总监（决策）
- 应用运维：2人（服务监控）
- 数据库运维：1人（DBA）
- 网络运维：1人（网络/CDN）
- 客服对接：1人（用户反馈）

监控重点：
- QPS / 响应时间 / 错误率
- CPU / 内存 / 磁盘
- 数据库连接数 / 慢查询
- Redis 内存 / 命中率
- 消息队列积压量

应急预案：
- 服务雪崩 → 熔断降级
- 数据库压力大 → 开只读实例
- 缓存击穿 → 本地缓存兜底
- 流量突增 → 动态扩容
```

## 结果

- 峰值 QPS: 62,000
- 平均响应时间: 45ms
- 错误率: 0.02%
- 系统零宕机
