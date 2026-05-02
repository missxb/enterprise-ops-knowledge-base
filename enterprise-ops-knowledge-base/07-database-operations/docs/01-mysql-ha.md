# MySQL 高可用架构

## 方案选型

| 方案 | 原理 | RTO | RPO | 适用场景 |
|------|------|-----|-----|----------|
| **MHA** | 自动故障切换 | 30s | 最小丢失 | 中小规模 |
| **MGR** | 组复制 | <5s | 零丢失 | MySQL 5.7.17+ |
| **ProxySQL** | 读写分离中间件 | <10s | 取决于复制 | 读多写少 |
| **Orchestrator** | 拓扑管理+故障转移 | 30s | 最小丢失 | 大规模集群 |
| **Galera** | 多主复制 | <5s | 零丢失 | 多写入节点 |

## MHA 部署

### 架构

```
          ┌─────────────┐
          │  MHA Manager │
          │  (监控节点)   │
          └──────┬───────┘
                 │
    ┌────────────┼────────────┐
    ▼            ▼            ▼
┌───────┐   ┌───────┐   ┌───────┐
│Master │──▶│Slave 1│──▶│Slave 2│
│(RW)   │   │(RO)   │   │(RO)   │
└───────┘   └───────┘   └───────┘
```

### 安装配置

```bash
# 安装 MHA Manager 和 Node
yum install -y mha4mysql-manager mha4mysql-node

# /etc/mha/app1.cnf
[server default]
manager_workdir=/var/log/mha/app1
manager_log=/var/log/mha/app1/manager.log
user=mha
password=mha_password
ssh_user=root
repl_user=repl
repl_password=repl_password
ping_interval=3

[server1]
hostname=10.0.1.10
port=3306
candidate_master=1

[server2]
hostname=10.0.1.11
port=3306
candidate_master=1

[server3]
hostname=10.0.1.12
port=3306
no_master=1
```

### 故障切换

```bash
# 检查配置
masterha_check_ssh --conf=/etc/mha/app1.cnf
masterha_check_repl --conf=/etc/mha/app1.cnf

# 启动 MHA Manager
masterha_manager --conf=/etc/mha/app1.cnf --remove_dead_master_conf &

# 手动切换
masterha_master_switch --master_state=dead --conf=/etc/mha/app1.cnf
```

## MGR (MySQL Group Replication)

### 配置

```ini
# my.cnf
[mysqld]
server_id=1
gtid_mode=ON
enforce_gtid_consistency=ON
binlog_checksum=NONE
log_bin=binlog
binlog_format=ROW
master_info_repository=TABLE
relay_log_info_repository=TABLE
transaction_write_set_extraction=XXHASH64
group_replication_group_name="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
group_replication_start_on_boot=OFF
group_replication_local_address="10.0.1.10:33061"
group_replication_group_seeds="10.0.1.10:33061,10.0.1.11:33061,10.0.1.12:33061"
group_replication_single_primary_mode=ON
```

### 启动

```sql
-- 安装插件
INSTALL PLUGIN group_replication SONAME 'group_replication.so';

-- 启动组复制
SET GLOBAL group_replication_bootstrap_group=ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;
```

## ProxySQL 读写分离

```bash
# 安装
yum install -y proxysql

# 配置后端 MySQL
mysql -u admin -padmin -h 127.0.0.1 -P 6032 << 'SQL'
-- 添加后端服务器
INSERT INTO mysql_servers(hostgroup_id, hostname, port) VALUES (10, '10.0.1.10', 3306);  -- 写
INSERT INTO mysql_servers(hostgroup_id, hostname, port) VALUES (20, '10.0.1.11', 3306);  -- 读
INSERT INTO mysql_servers(hostgroup_id, hostname, port) VALUES (20, '10.0.1.12', 3306);  -- 读

-- 配置读写分离规则
INSERT INTO mysql_query_rules(rule_id, active, match_pattern, destination_hostgroup)
VALUES (1, 1, '^SELECT .* FOR UPDATE$', 10),
       (2, 1, '^SELECT', 20);

LOAD MYSQL SERVERS TO RUNTIME;
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
SAVE MYSQL QUERY RULES TO DISK;
SQL
```

## 监控指标

```sql
-- 复制状态
SHOW SLAVE STATUS\G
SHOW MASTER STATUS;

-- 关键指标
-- Seconds_Behind_Master: 主从延迟
-- Slave_IO_Running: IO 线程状态
-- Slave_SQL_Running: SQL 线程状态
```
