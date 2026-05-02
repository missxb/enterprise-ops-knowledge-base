# 项目六：数据库运维规范

## 项目背景

为公司数据库体系建立完整的运维规范，覆盖 MySQL 高可用架构、Redis 集群管理、备份恢复演练。

## MySQL 高可用架构

```
                    ┌──────────────┐
                    │   应用层      │
                    └──────┬───────┘
                           │
                    ┌──────┴───────┐
                    │  ProxySQL    │
                    │  读写分离    │
                    │  连接池      │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
     ┌────────┴──┐  ┌──────┴──┐  ┌─────┴───┐
     │  Master   │  │ Slave 1 │  │ Slave 2 │
     │  (写)     │  │ (读)    │  │ (读)    │
     └────────┬──┘  └─────────┘  └─────────┘
              │
     ┌────────┴──┐
     │  MHA/Galera│
     │  自动故障转移│
     └───────────┘
```

## 目录结构

```
07-database-ops/
├── README.md
├── mysql-ha/
│   ├── proxysql-config.cnf         # ProxySQL 配置
│   ├── mha-manager.conf            # MHA 配置
│   └── mysql-init.sql              # MySQL 初始化 SQL
├── redis-cluster/
│   └── redis-cluster-init.sh       # Redis 集群初始化
├── scripts/
│   ├── mysql-backup.sh             # MySQL 备份脚本
│   ├── mysql-restore.sh            # MySQL 恢复脚本
│   ├── mysql-monitor.sh            # MySQL 监控脚本
│   ├── redis-backup.sh             # Redis 备份脚本
│   └── slow-query-analyzer.sh      # 慢查询分析
├── config/
│   ├── mysql-optimize.cnf          # MySQL 优化配置
│   └── redis-optimize.conf         # Redis 优化配置
└── docs/
    ├── backup-recovery-guide.md    # 备份恢复指南
    └── performance-tuning.md       # 性能调优指南
```
