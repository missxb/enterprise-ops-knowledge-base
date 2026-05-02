# 数据库高可用架构完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. MySQL主从复制（GTID）](#2-mysql主从复制gtid)
- [3. MySQL MHA高可用](#3-mysql-mha高可用)
- [4. MySQL InnoDB Cluster](#4-mysql-innodb-cluster)
- [5. Redis哨兵模式](#5-redis哨兵模式)
- [6. Redis Cluster集群](#6-redis-cluster集群)
- [7. PostgreSQL高可用](#7-postgresql高可用)
- [8. MongoDB副本集与分片](#8-mongodb副本集与分片)
- [9. 数据库备份策略](#9-数据库备份策略)
- [10. 监控与慢查询优化](#10-监控与慢查询优化)

---

## 1. 项目背景与架构设计

### 1.1 数据库高可用架构选型

| 数据库 | 高可用方案 | RPO | RTO | 适用场景 |
|--------|-----------|-----|-----|---------|
| MySQL | GTID主从+MHA | 0 | <30s | OLTP通用 |
| MySQL | InnoDB Cluster | 0 | <10s | 高要求OLTP |
| Redis | 哨兵模式 | <1s | <10s | 缓存/会话 |
| Redis | Cluster | <1s | <10s | 大数据量缓存 |
| PG | Patroni | 0 | <30s | OLTP/OLAP |
| MongoDB | 副本集 | 0 | <30s | 文档存储 |

---

## 2. MySQL主从复制（GTID）

### 2.1 GTID主从配置

```ini
# /etc/my.cnf - MySQL GTID主从复制配置

# ===== 主库配置 (my-master.cnf) =====
[mysqld]
server-id = 1
log-bin = mysql-bin
binlog_format = ROW
gtid_mode = ON
enforce_gtid_consistency = ON
sync_binlog = 1
innodb_flush_log_at_trx_commit = 1
log_slave_updates = ON
relay_log = relay-bin
binlog_expire_logs_seconds = 604800
max_binlog_size = 512M

# 性能优化
innodb_buffer_pool_size = 8G
innodb_buffer_pool_instances = 8
innodb_log_file_size = 1G
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000
innodb_read_io_threads = 8
innodb_write_io_threads = 8
max_connections = 500
table_open_cache = 4096
sort_buffer_size = 4M
join_buffer_size = 4M
read_buffer_size = 2M
tmp_table_size = 64M
max_heap_table_size = 64M

# 慢查询
slow_query_log = ON
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 1
log_queries_not_using_indexes = ON

# 安全
skip_name_resolve = ON
local_infile = OFF

# ===== 从库配置 (my-slave.cnf) =====
[mysqld]
server-id = 2
log-bin = mysql-bin
binlog_format = ROW
gtid_mode = ON
enforce_gtid_consistency = ON
log_slave_updates = ON
relay_log = relay-bin
read_only = ON
super_read_only = ON
```

### 2.2 主从搭建步骤

```sql
-- ===== 主库操作 =====

-- 1. 创建复制用户
CREATE USER 'repl'@'%' IDENTIFIED BY 'ReplPassword123!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;

-- 2. 查看主库状态
SHOW MASTER STATUS;
-- +------------------+----------+
-- | File             | Position |
-- +------------------+----------+
-- | mysql-bin.000003 |      154 |
-- +------------------+----------+

-- ===== 从库操作 =====

-- 3. 配置主从关系
CHANGE MASTER TO
    MASTER_HOST='10.10.2.11',
    MASTER_PORT=3306,
    MASTER_USER='repl',
    MASTER_PASSWORD='ReplPassword123!',
    MASTER_AUTO_POSITION=1;

-- 4. 启动复制
START SLAVE;

-- 5. 检查状态
SHOW SLAVE STATUS\G
-- 关键指标:
-- Slave_IO_Running: Yes
-- Slave_SQL_Running: Yes
-- Seconds_Behind_Master: 0 (越小越好)
-- Retrieved_Gtid_Set: 已接收的GTID
-- Executed_Gtid_Set: 已执行的GTID
```

### 2.3 主从切换脚本

```bash
#!/bin/bash
# mysql-failover.sh - MySQL主从切换脚本

MASTER_HOST="10.10.2.11"
SLAVE_HOST="10.10.2.12"
MYSQL_USER="admin"
MYSQL_PASS="AdminPass123!"

echo "========== MySQL主从切换开始 =========="

# 1. 检查从库状态
echo "--- 检查从库同步状态 ---"
SLAVE_STATUS=$(mysql -h $SLAVE_HOST -u $MYSQL_USER -p$MYSQL_PASS -e "SHOW SLAVE STATUS\G")
IO_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_IO_Running:" | awk '{print $2}')
SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}')
LAG=$(echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master:" | awk '{print $2}')

if [ "$IO_RUNNING" != "Yes" ] || [ "$SQL_RUNNING" != "Yes" ]; then
    echo "ERROR: 从库复制异常，IO: $IO_RUNNING, SQL: $SQL_RUNNING"
    exit 1
fi

if [ "$LAG" != "0" ] && [ "$LAG" != "NULL" ]; then
    echo "WARNING: 从库延迟 $LAG 秒，等待追平..."
    sleep 10
fi

# 2. 停止主库写入（如果主库还活着）
echo "--- 停止主库写入 ---"
mysql -h $MASTER_HOST -u $MYSQL_USER -p$MYSQL_PASS -e "SET GLOBAL read_only = ON; FLUSH TABLES WITH READ LOCK;" 2>/dev/null || true

# 3. 等待从库追平
echo "--- 等待从库追平 ---"
mysql -h $SLAVE_HOST -u $MYSQL_USER -p$MYSQL_PASS -e "SELECT WAIT_FOR_EXECUTED_GTID_SET('$(mysql -h $MASTER_HOST -u $MYSQL_USER -p$MYSQL_PASS -N -e "SELECT @@gtid_executed" 2>/dev/null)', 10);" 2>/dev/null || true

# 4. 停止从库复制
echo "--- 停止从库复制 ---"
mysql -h $SLAVE_HOST -u $MYSQL_USER -p$MYSQL_PASS -e "STOP SLAVE; RESET SLAVE ALL;"

# 5. 提升从库为主库
echo "--- 提升从库为主库 ---"
mysql -h $SLAVE_HOST -u $MYSQL_USER -p$MYSQL_PASS -e "SET GLOBAL read_only = OFF; SET GLOBAL super_read_only = OFF;"

# 6. 验证新主库
echo "--- 验证新主库 ---"
mysql -h $SLAVE_HOST -u $MYSQL_USER -p$MYSQL_PASS -e "SHOW MASTER STATUS;"

echo "========== 切换完成，新主库: $SLAVE_HOST =========="
echo "请更新应用连接配置指向新主库"
```

---

## 3. MySQL MHA高可用

### 3.1 MHA部署

```bash
#!/bin/bash
# deploy-mha.sh - MHA Manager部署

# MHA架构: Manager(监控) + Node(每台MySQL)

# 1. 安装MHA Node（所有MySQL节点）
yum install -y perl-DBD-MySQL perl-Config-Tiny perl-Parallel-ForkManager
rpm -ivh mha4mysql-node-0.58-0.el7.noarch.rpm

# 2. 安装MHA Manager（管理节点）
rpm -ivh mha4mysql-manager-0.58-0.el7.noarch.rpm

# 3. 配置MHA
mkdir -p /etc/mha
cat > /etc/mha/app1.cnf << 'EOF'
[server default]
manager_workdir=/var/log/mha/app1
manager_log=/var/log/mha/app1/manager.log
user=mha
password=MhaPassword123!
ssh_user=root
repl_user=repl
repl_password=ReplPassword123!
ping_interval=3
master_ip_failover_script=/etc/mha/master_ip_failover
master_ip_online_change_script=/etc/mha/master_ip_online_change

[server1]
hostname=10.10.2.11
port=3306
candidate_master=1

[server2]
hostname=10.10.2.12
port=3306
candidate_master=1

[server3]
hostname=10.10.2.13
port=3306
no_master=1
EOF

# 4. 创建MHA管理用户（所有MySQL节点）
# mysql> CREATE USER 'mha'@'%' IDENTIFIED BY 'MhaPassword123!';
# mysql> GRANT ALL PRIVILEGES ON *.* TO 'mha'@'%';
# mysql> GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

# 5. 检查SSH连通性
masterha_check_ssh --conf=/etc/mha/app1.cnf

# 6. 检查复制状态
masterha_check_repl --conf=/etc/mha/app1.cnf

# 7. 启动MHA Manager
nohup masterha_manager --conf=/etc/mha/app1.cnf --remove_dead_master_conf --ignore_last_failover < /dev/null > /var/log/mha/app1/manager.log 2>&1 &

# 8. 检查状态
masterha_check_status --conf=/etc/mha/app1.cnf
```

### 3.2 VIP自动漂移脚本

```perl
#!/usr/bin/env perl
# /etc/mha/master_ip_failover - VIP自动漂移脚本

use strict;
use warnings FATAL => 'all';

my $vip = '10.10.2.100/24';
my $interface = 'eth0';
my $ssh_start_vip = "sudo ifconfig $interface:0 $vip up";
my $ssh_stop_vip = "sudo ifconfig $interface:0 down";

my ($command, $ssh_user, $orig_master_host, $orig_master_ip, $new_master_host, $new_master_ip) = @ARGV;

if ($command eq 'stop' || $command eq 'stopssh') {
    # 停止旧主库VIP
    system("$ssh_stop_vip");
    exit 0;
}

if ($command eq 'start') {
    # 在新主库上启动VIP
    system("ssh -o StrictHostKeyChecking=no $ssh_user\@$new_master_host '$ssh_start_vip'");
    exit 0;
}

exit 1;
```

---

## 4. MySQL InnoDB Cluster

### 4.1 InnoDB Cluster部署

```sql
-- InnoDB Cluster = Group Replication + MySQL Router + MySQL Shell

-- 1. 准备工作（每个节点执行）
-- 配置Group Replication
SET GLOBAL group_replication_group_name="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
SET GLOBAL group_replication_start_on_boot=OFF;
SET GLOBAL group_replication_local_address="10.10.2.11:33061";
SET GLOBAL group_replication_group_seeds="10.10.2.11:33061,10.10.2.12:33061,10.10.2.13:33061";

-- 2. 使用MySQL Shell创建集群
-- mysqlsh root@10.10.2.11
-- \js
-- var cluster = dba.createCluster('myCluster')
-- cluster.addInstance('root@10.10.2.12:3306')
-- cluster.addInstance('root@10.10.2.13:3306')
-- cluster.status()

-- 3. MySQL Router配置（应用连接入口）
-- mysqlrouter --bootstrap root@10.10.2.11 --user=mysqlrouter
-- 启动后会自动配置读写分离端口:
-- 6446: 读写 (Primary)
-- 6447: 只读 (Secondary)
```

---

## 5. Redis哨兵模式

### 5.1 哨兵模式配置

```bash
# Redis哨兵模式架构
# 1个Master + 2个Slave + 3个Sentinel

# ===== redis-master.conf =====
port 6379
bind 0.0.0.0
daemonize yes
pidfile /var/run/redis/redis.pid
dir /data/redis
dbfilename dump.rdb
appendonly yes
appendfilename "appendonly.aof"
requirepass "RedisPass123!"
masterauth "RedisPass123!"
maxmemory 8gb
maxmemory-policy allkeys-lru

# ===== redis-slave.conf =====
port 6379
bind 0.0.0.0
daemonize yes
replicaof 10.10.3.11 6379
masterauth "RedisPass123!"
requirepass "RedisPass123!"
replica-read-only yes
maxmemory 8gb

# ===== sentinel.conf =====
port 26379
bind 0.0.0.0
daemonize yes
sentinel monitor mymaster 10.10.3.11 6379 2
sentinel auth-pass mymaster RedisPass123!
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 60000
sentinel parallel-syncs mymaster 1

# 启动哨兵（3个节点）
redis-sentinel /etc/redis/sentinel.conf
```

### 5.2 哨兵故障切换验证

```bash
# 查看哨兵状态
redis-cli -p 26379 sentinel master mymaster
redis-cli -p 26379 sentinel slaves mymaster
redis-cli -p 26379 sentinel sentinels mymaster

# 模拟主库故障
redis-cli -h 10.10.3.11 -a RedisPass123! DEBUG sleep 30

# 观察切换
redis-cli -p 26379 sentinel get-master-addr-by-name mymaster

# 应用连接（通过哨兵发现主库）
# 连接哨兵获取当前主地址，自动切换
```

---

## 6. Redis Cluster集群

### 6.1 Cluster集群部署

```bash
#!/bin/bash
# deploy-redis-cluster.sh - Redis Cluster部署

# 6个节点: 3主3从
NODES="10.10.3.11:6379 10.10.3.12:6379 10.10.3.13:6379 10.10.3.14:6379 10.10.3.15:6379 10.10.3.16:6379"

# 1. 每个节点配置
for node in $NODES; do
    IP=$(echo $node | cut -d: -f1)
    cat > /etc/redis/redis-${IP}.conf << EOF
port 6379
bind ${IP} 127.0.0.1
daemonize yes
cluster-enabled yes
cluster-config-file nodes-${IP}.conf
cluster-node-timeout 15000
appendonly yes
appendfilename "appendonly-${IP}.aof"
dbfilename dump-${IP}.rdb
dir /data/redis/${IP}
requirepass "RedisPass123!"
masterauth "RedisPass123!"
maxmemory 8gb
maxmemory-policy allkeys-lru
EOF
    mkdir -p /data/redis/${IP}
    redis-server /etc/redis/redis-${IP}.conf
done

# 2. 创建集群
redis-cli -a RedisPass123! --cluster create \
    10.10.3.11:6379 10.10.3.12:6379 10.10.3.13:6379 \
    10.10.3.14:6379 10.10.3.15:6379 10.10.3.16:6379 \
    --cluster-replicas 1

# 3. 验证集群
redis-cli -c -h 10.10.3.11 -a RedisPass123! cluster info
redis-cli -c -h 10.10.3.11 -a RedisPass123! cluster nodes

# 4. 集群扩缩容
# 添加节点
redis-cli -a RedisPass123! --cluster add-node 10.10.3.17:6379 10.10.3.11:6379
# 迁移slot
redis-cli -a RedisPass123! --cluster reshard 10.10.3.11:6379
# 删除节点
redis-cli -a RedisPass123! --cluster del-node 10.10.3.11:6379 <node-id>
```

---

## 7. PostgreSQL高可用

### 7.1 Patroni部署

```yaml
# patroni.yml - Patroni高可用配置
scope: pg-cluster
namespace: /pg-cluster/
name: pg-node-01

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.10.4.11:8008

etcd3:
  hosts: 10.10.1.11:2379,10.10.1.12:2379,10.10.1.13:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_log_hints: "on"
        logging_collector: "on"
        log_directory: /var/log/postgresql
        log_filename: postgresql-%Y-%m-%d.log

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.10.4.11:5432
  data_dir: /data/postgresql
  bin_dir: /usr/pgsql-15/bin
  authentication:
    superuser:
      username: postgres
      password: PgPassword123!
    replication:
      username: replicator
      password: ReplPassword123!
  parameters:
    shared_buffers: 4GB
    effective_cache_size: 12GB
    work_mem: 64MB
    maintenance_work_mem: 512MB

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
```

```bash
# 启动Patroni
patroni /etc/patroni/patroni.yml

# 集群状态
patronictl -c /etc/patroni/patroni.yml list

# 手动切换
patronictl -c /etc/patroni/patroni.yml switchover
```

---

## 8. MongoDB副本集与分片

### 8.1 副本集配置

```yaml
# mongod.conf - 副本集配置
storage:
  dbPath: /data/mongodb
  journal:
    enabled: true
  wiredTiger:
    engineConfig:
      cacheSizeGB: 8

systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true

net:
  port: 27017
  bindIp: 0.0.0.0

replication:
  replSetName: "rs0"

security:
  authorization: enabled
  keyFile: /etc/mongodb/keyfile
```

```javascript
// 初始化副本集
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "10.10.5.11:27017", priority: 2 },
    { _id: 1, host: "10.10.5.12:27017", priority: 1 },
    { _id: 2, host: "10.10.5.13:27017", priority: 1 }
  ]
})

// 查看副本集状态
rs.status()
rs.isMaster()

// 添加仲裁节点（不存数据，只投票）
rs.addArb("10.10.5.14:27017")
```

---

## 9. 数据库备份策略

### 9.1 MySQL备份方案

```bash
#!/bin/bash
# mysql-backup.sh - MySQL完整备份方案

BACKUP_DIR="/backup/mysql/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# ===== 物理备份 (Percona XtraBackup) =====
# 全量备份（每周日）
xtrabackup --backup \
    --target-dir="$BACKUP_DIR/full" \
    --user=backup --password=BackupPass123! \
    --host=10.10.2.11

# 增量备份（每天）
LATEST_BACKUP=$(ls -td /backup/mysql/*/incremental-* 2>/dev/null | head -1)
if [ -z "$LATEST_BACKUP" ]; then
    BASE_DIR="$BACKUP_DIR/full"
else
    BASE_DIR="$LATEST_BACKUP"
fi
xtrabackup --backup \
    --target-dir="$BACKUP_DIR/inc-$(date +%H%M)" \
    --incremental-basedir="$BASE_DIR" \
    --user=backup --password=BackupPass123!

# ===== 逻辑备份 (mysqldump) =====
# 全量逻辑备份
mysqldump --all-databases \
    --single-transaction \
    --routines --triggers --events \
    --set-gtid-purged=ON \
    --user=backup --password=BackupPass123! \
    | gzip > "$BACKUP_DIR/all-databases.sql.gz"

# 恢复
# mysql < all-databases.sql
# 或
# zcat all-databases.sql.gz | mysql

# ===== 备份上传到OSS =====
ossutil cp -r "$BACKUP_DIR" oss://db-backup/mysql/$(date +%Y%m%d)/

# 清理本地旧备份
find /backup/mysql -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
```

### 9.2 Redis备份

```bash
#!/bin/bash
# redis-backup.sh

BACKUP_DIR="/backup/redis/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# RDB快照
redis-cli -a RedisPass123! BGSAVE
sleep 10
cp /data/redis/dump.rdb "$BACKUP_DIR/"

# AOF备份
cp /data/redis/appendonly.aof "$BACKUP_DIR/"

# 上传OSS
ossutil cp -r "$BACKUP_DIR" oss://db-backup/redis/$(date +%Y%m%d)/
```

---

## 10. 监控与慢查询优化

### 10.1 MySQL监控指标

```yaml
# 核心监控指标

连接相关:
  - Threads_connected: 当前连接数
  - Threads_running: 活跃线程数
  - Max_used_connections: 历史最大连接数
  - Connection_errors_*: 连接错误

查询相关:
  - Questions: 查询总数
  - Com_select/Com_insert/Com_update/Com_delete: 各类查询数
  - Slow_queries: 慢查询数
  - Select_full_join: 全表JOIN数

InnoDB相关:
  - Innodb_buffer_pool_read_requests: 缓冲池读请求
  - Innodb_buffer_pool_reads: 磁盘读次数
  - Innodb_buffer_pool_hit_rate: 命中率 (> 99%)
  - Innodb_row_lock_waits: 行锁等待
  - Innodb_deadlocks: 死锁数

复制相关:
  - Slave_IO_Running: IO线程状态
  - Slave_SQL_Running: SQL线程状态
  - Seconds_Behind_Master: 复制延迟
```

### 10.2 慢查询优化

```sql
-- 开启慢查询日志
SET GLOBAL slow_query_log = ON;
SET GLOBAL long_query_time = 1;
SET GLOBAL log_queries_not_using_indexes = ON;

-- 查看慢查询
-- 使用pt-query-digest分析
-- pt-query-digest /var/log/mysql/slow.log

-- 常见优化
-- 1. 添加合适索引
EXPLAIN SELECT * FROM orders WHERE user_id = 100 AND status = 'paid';
-- 如果type=ALL，需要添加索引
ALTER TABLE orders ADD INDEX idx_user_status (user_id, status);

-- 2. 避免全表扫描
-- 不好: SELECT * FROM users WHERE name LIKE '%张%'
-- 好:  SELECT * FROM users WHERE name LIKE '张%'

-- 3. 分页优化
-- 不好: SELECT * FROM orders ORDER BY id LIMIT 100000, 20
-- 好:  SELECT * FROM orders WHERE id > 100000 ORDER BY id LIMIT 20

-- 4. 避免大事务
-- 将大批量操作拆分为小批次
-- 每批1000条，分批提交
```

---

> 📅 最后更新: 2026-05-02
