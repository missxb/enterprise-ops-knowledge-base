# 07 - 数据库运维 (Database Operations)

## 概述

本模块涵盖企业级数据库的部署、运维、优化与高可用方案，覆盖 MySQL、Redis、MongoDB、Elasticsearch 四大主流数据库。从单机安装到集群高可用，从性能调优到灾备恢复，提供完整的数据库运维知识体系。

## 目录结构

```
07-database-operations/
├── README.md                          # 本文件
├── docs/                              # 文档目录
│   ├── 01-mysql-ha.md                 # MySQL 高可用架构设计
│   ├── 02-mysql-replication.md        # 主从复制与读写分离
│   ├── 03-mysql-optimization.md       # MySQL 性能优化全攻略
│   ├── 04-mysql-backup-recovery.md    # 备份恢复策略与实战
│   ├── 05-redis-cluster.md            # Redis 集群部署与管理
│   ├── 06-redis-optimization.md       # Redis 性能优化与内存管理
│   ├── 07-mongodb-replica.md          # MongoDB 副本集与分片
│   ├── 08-elasticsearch-ops.md        # Elasticsearch 集群运维
│   └── 09-database-migration.md       # 数据库迁移方案与工具
├── examples/                          # 配置示例
│   ├── mysql/
│   │   ├── my.cnf                     # 生产级 MySQL 配置文件
│   │   ├── init-slave.sh              # 从库自动化初始化脚本
│   │   └── slow-query-analysis.md     # 慢查询分析与优化指南
│   ├── redis/
│   │   ├── redis.conf                 # 生产级 Redis 配置文件
│   │   └── cluster-setup.md           # Redis 集群搭建指南
│   └── mongodb/
│       └── replica-set.conf           # MongoDB 副本集配置
├── scripts/                           # 运维脚本
│   ├── mysql-backup.sh                # MySQL 自动化备份脚本
│   ├── mysql-monitor.sh               # MySQL 监控与告警脚本
│   ├── redis-health.sh                # Redis 集群健康检查
│   └── db-migration.sh               # 数据库迁移执行脚本
└── best-practices/                    # 最佳实践
    ├── connection-pool.md             # 连接池配置与调优
    ├── index-optimization.md          # 索引设计与优化策略
    └── data-archival.md               # 数据归档与生命周期管理
```

## 技术栈覆盖

| 数据库 | 版本 | 架构模式 | 核心文档 |
|--------|------|----------|----------|
| MySQL | 5.7 / 8.0 | 主从、MGR、InnoDB Cluster | 01-04 |
| Redis | 6.x / 7.x | Sentinel、Cluster | 05-06 |
| MongoDB | 5.x / 6.x | 副本集、分片集群 | 07 |
| Elasticsearch | 7.x / 8.x | 多节点集群 | 08 |

## 快速开始

### MySQL 主从部署

```bash
# 初始化主库
mysql -u root -p < examples/mysql/my.cnf

# 初始化从库
bash examples/mysql/init-slave.sh --master-host=10.0.1.10 --slave-host=10.0.1.11

# 启动备份任务
bash scripts/mysql-backup.sh --mode full --schedule daily
```

### Redis 集群部署

```bash
# 参考集群搭建文档
cat examples/redis/cluster-setup.md

# 健康检查
bash scripts/redis-health.sh --cluster 10.0.1.20:7000
```

## 企业案例

- **电商数据库架构**：MySQL 主从 + Redis 缓存 + 读写分离 + 分库分表
- **金融级高可用**：MySQL MGR + 半同步复制 + 异地灾备 + 数据加密
- **社交平台**：MongoDB 分片 + Redis Cluster + Elasticsearch 全文检索
- **物联网时序数据**：Elasticsearch + 冷热分离 + 生命周期管理

## 运维工具链

```
监控: Prometheus + Grafana + mysqld_exporter / redis_exporter
备份: xtrabackup / mysqldump / redis-cli BGSAVE
迁移: gh-ost / pt-online-schema-change / mongodump
审计: binlog2sql / Redis Monitor / MongoDB Profiler
```

## 维护说明

- 文档基于生产环境最佳实践编写
- 配置文件已针对 16C64G 规格优化，其他规格需调整参数
- 脚本兼容 CentOS 7/8、Ubuntu 20.04/22.04
- 每季度跟随数据库版本更新修订
