# AWS 核心服务详解

## 1. 概述

AWS 是全球最大的公有云服务商，拥有最完善的云产品生态。本文将从运维角度介绍 AWS 核心服务的选型、配置和运维最佳实践，帮助运维工程师快速上手 AWS 平台。

## 2. 计算服务

### 2.1 EC2 (弹性计算云)

EC2 是 AWS 最核心的计算服务，提供按需弹性虚拟机。

**实例类型：**

| 类型 | 前缀 | 特点 | 适用场景 |
|------|------|------|----------|
| 通用型 | m7g, m6i | 均衡的计算/内存/网络 | Web 服务器、应用服务器 |
| 计算优化 | c7g, c6i | 高性能处理器 | 批处理、科学计算 |
| 内存优化 | r7g, r6i | 大内存 | 数据库、缓存、实时分析 |
| 存储优化 | i4i, d3 | 高 IO 带宽 | 数据仓库、分布式文件系统 |
| 加速计算 | p4d, g5 | GPU/FPGA | 机器学习、HPC |
| 突发性能 | t4g, t3 | CPU 积分制 | 开发测试、低流量 Web |

**Graviton 处理器（ARM 架构）：**
- 基于 ARM 的自研处理器，性价比比 x86 高 40%
- 支持大多数 Linux 工作负载
- 推荐用于新部署的通用型和计算优化型实例

**存储选项：**

```
EBS gp3     → 通用 SSD，3000 IOPS / 125 MB/s 基线（可配置）
EBS io2     → 高性能 SSD，最高 64000 IOPS
EBS st1     → 吞吐优化 HDD，适合大数据
Instance Store → 临时存储，最高性能但实例停止后数据丢失
```

### 2.2 EKS (弹性 Kubernetes 服务)

EKS 是 AWS 托管的 Kubernetes 服务。

**架构特点：**
- 控制平面由 AWS 管理，跨 3 个 AZ 高可用
- Worker 节点支持 EC2、Fargate（无服务器）两种模式
- 深度集成 AWS 服务（IAM、VPC、ELB、EBS）

**节点组配置：**
```yaml
# eks-node-group.yaml
apiVersion: eks.aws.com/v1
kind: NodeGroup
metadata:
  name: app-nodes
spec:
  instanceTypes:
    - m6g.xlarge
    - m6g.2xlarge
  minSize: 2
  maxSize: 20
  desiredSize: 5
  labels:
    workload: general
  taints: []
```

### 2.3 Lambda (无服务器计算)

Lambda 是 AWS 的 FaaS 服务，按实际执行次数和时长计费。

**配置要点：**
- 内存分配：128MB ~ 10240MB（CPU 与内存成正比）
- 超时时间：最长 15 分钟
- 并发限制：默认 1000 并发（可申请提升）
- 冷启动：预留并发可消除冷启动

**适用场景：**
- API Gateway 后端
- S3 事件处理（图片压缩、文件转换）
- CloudWatch Events 定时任务
- SQS/Kinesis 消息消费

## 3. 数据库服务

### 3.1 RDS (关系数据库服务)

RDS 支持 MySQL、PostgreSQL、MariaDB、Oracle、SQL Server。

**Multi-AZ 部署：**
```
┌─────────────────────────────────────┐
│         RDS Multi-AZ                │
│  ┌───────────┐    ┌───────────┐     │
│  │  主实例    │───→│  备用实例  │     │
│  │  (AZ-a)   │同步│  (AZ-b)   │     │
│  └───────────┘    └───────────┘     │
│         │                           │
│  ┌──────▼──────┐                    │
│  │ Read Replica│  ← 最多 15 个只读副本│
│  └─────────────┘                    │
└─────────────────────────────────────┘
```

**Aurora 推荐：**
- Aurora MySQL：兼容 MySQL，性能提升 5 倍
- Aurora PostgreSQL：兼容 PostgreSQL，性能提升 3 倍
- Aurora Serverless v2：按需自动扩缩容
- Aurora Global Database：跨 Region 复制，延迟 < 1 秒

### 3.2 ElastiCache

**Redis vs Memcached：**

| 特性 | Redis | Memcached |
|------|-------|-----------|
| 数据结构 | 丰富（String/Hash/List/Set/ZSet） | 仅 KV |
| 持久化 | 支持（RDB/AOF） | 不支持 |
| 集群模式 | 支持（Cluster） | 支持（多节点） |
| 发布订阅 | 支持 | 不支持 |
| Lua 脚本 | 支持 | 不支持 |
| 多线程 | 单线程（6.0+ IO 多线程） | 多线程 |

### 3.3 DynamoDB

DynamoDB 是 AWS 全托管的 NoSQL 数据库。

**核心特性：**
- 单位数毫秒级延迟
- 自动扩展，无需容量规划
- 全局表支持多 Region 多活
- 内置 DAX 缓存加速

**容量模式：**
- **按需模式**：适合不可预测的工作负载
- **预置模式**：适合稳定的工作负载，成本更低

## 4. 网络服务

### 4.1 VPC (虚拟私有云)

**CIDR 规划最佳实践：**

```
VPC CIDR: 10.0.0.0/16 (65536 IPs)

子网划分:
├── Public Subnet (每个 AZ)
│   ├── 10.0.1.0/24  → AZ-a (NAT Gateway, ALB)
│   ├── 10.0.2.0/24  → AZ-b (NAT Gateway, ALB)
│   └── 10.0.3.0/24  → AZ-c (NAT Gateway, ALB)
├── Private Subnet - App (每个 AZ)
│   ├── 10.0.11.0/24 → AZ-a (EC2, ECS Tasks)
│   ├── 10.0.12.0/24 → AZ-b (EC2, ECS Tasks)
│   └── 10.0.13.0/24 → AZ-c (EC2, ECS Tasks)
└── Private Subnet - Data (每个 AZ)
    ├── 10.0.21.0/24 → AZ-a (RDS, ElastiCache)
    ├── 10.0.22.0/24 → AZ-b (RDS, ElastiCache)
    └── 10.0.23.0/24 → AZ-c (RDS, ElastiCache)
```

### 4.2 ALB (应用负载均衡)

**高级路由配置：**
```yaml
# 基于路径的路由
Rules:
  - Priority: 1
    Conditions:
      - Field: path-pattern
        Values: ["/api/*"]
    Actions:
      - Type: forward
        TargetGroup: api-servers
  - Priority: 2
    Conditions:
      - Field: path-pattern
        Values: ["/static/*"]
    Actions:
      - Type: forward
        TargetGroup: static-servers
  - Priority: 3
    Conditions:
      - Field: host-header
        Values: ["admin.example.com"]
    Actions:
      - Type: forward
        TargetGroup: admin-servers
```

### 4.3 CloudFront (CDN)

**缓存策略：**
```
静态资源（CSS/JS/图片）:
  TTL: 1 年
  策略: CachingOptimized

API 响应:
  TTL: 0（不缓存）
  策略: CachingDisabled

动态内容:
  TTL: 根据 Cache-Control 头
  策略: CachingOptimizedForUncompressedObjects
```

## 5. 存储服务

### 5.1 S3 (简单存储服务)

**存储类：**

| 存储类 | 适用场景 | 最小存储时间 | 检索费用 |
|--------|----------|-------------|----------|
| S3 Standard | 频繁访问 | 无 | 无 |
| S3 Intelligent-Tiering | 访问模式不确定 | 无 | 无 |
| S3 Standard-IA | 低频访问 | 30 天 | 按 GB |
| S3 One Zone-IA | 低频访问，可重建 | 30 天 | 按 GB |
| S3 Glacier Instant Retrieval | 归档，毫秒检索 | 90 天 | 按 GB |
| S3 Glacier Flexible Retrieval | 归档，分钟~小时检索 | 90 天 | 按 GB |
| S3 Glacier Deep Archive | 长期归档 | 180 天 | 按 GB |

**生命周期配置：**
```json
{
  "Rules": [
    {
      "ID": "ArchiveOldData",
      "Status": "Enabled",
      "Filter": { "Prefix": "logs/" },
      "Transitions": [
        { "Days": 30, "StorageClass": "STANDARD_IA" },
        { "Days": 90, "StorageClass": "GLACIER" },
        { "Days": 365, "StorageClass": "DEEP_ARCHIVE" }
      ],
      "Expiration": { "Days": 2555 }
    }
  ]
}
```

## 6. 安全服务

### 6.1 IAM (身份与访问管理)

**最佳实践：**
- 不使用 Root 账号，创建 IAM 用户
- 启用 MFA 多因素认证
- 使用 IAM Role 而非长期凭证
- 遵循最小权限原则
- 使用 IAM Access Analyzer 检测过度权限

**策略模板：**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-bucket/*"
    }
  ]
}
```

### 6.2 Security Group (安全组)

**规则设计原则：**
- 入站规则：最小化开放端口
- 出站规则：默认允许所有出站
- 引用安全组而非 IP 地址（更灵活）
- 分层设计：Web SG → App SG → DB SG

## 7. 监控服务

### 7.1 CloudWatch

**关键指标：**

```
EC2: CPUUtilization, NetworkIn/Out, DiskRead/Write
RDS: CPUUtilization, DatabaseConnections, ReadLatency
ALB: ActiveConnectionCount, TargetResponseTime, HTTPCode_Target_5XX
Lambda: Invocations, Duration, Errors, Throttles
```

**告警配置：**
```json
{
  "AlarmName": "HighCPU-Critical",
  "MetricName": "CPUUtilization",
  "Namespace": "AWS/EC2",
  "Statistic": "Average",
  "Period": 300,
  "EvaluationPeriods": 2,
  "Threshold": 90,
  "ComparisonOperator": "GreaterThanThreshold",
  "AlarmActions": ["arn:aws:sns:us-east-1:123456789:ops-alerts"]
}
```

## 8. 成本管理

### 8.1 Cost Explorer

**成本优化策略：**
1. **Reserved Instances**：1 年或 3 年预留，节省 30-60%
2. **Savings Plans**：灵活的承诺使用折扣
3. **Spot Instances**：竞价实例，节省 60-90%（适合无状态工作负载）
4. **Right Sizing**：根据实际使用调整实例规格

## 9. 阿里云 vs AWS 对照表

| 功能 | 阿里云 | AWS |
|------|--------|-----|
| 计算 | ECS | EC2 |
| 容器 | ACK | EKS |
| 函数 | FC | Lambda |
| 关系数据库 | RDS | RDS/Aurora |
| 缓存 | Redis | ElastiCache |
| 对象存储 | OSS | S3 |
| CDN | CDN | CloudFront |
| 负载均衡 | SLB/ALB | ALB/NLB |
| VPC | VPC | VPC |
| IAM | RAM | IAM |
| 监控 | CloudMonitor | CloudWatch |
| 日志 | SLS | CloudWatch Logs |

## 10. 总结

AWS 的服务生态非常丰富，选型时需要根据业务需求、团队技术栈和成本预算综合考虑。对于国内企业，如果业务主要面向国内用户，建议优先考虑阿里云；如果有全球化需求，AWS 的全球基础设施更具优势。多云架构也是当前的趋势，可以根据不同业务场景选择最合适的云平台。
