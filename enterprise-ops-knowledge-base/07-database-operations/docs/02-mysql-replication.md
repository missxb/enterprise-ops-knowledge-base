# MySQL 主从复制与读写分离

## GTID 复制配置

### 主库配置

```ini
# my.cnf
[mysqld]
server_id=1
gtid_mode=ON
enforce_gtid_consistency=ON
log_bin=mysql-bin
binlog_format=ROW
sync_binlog=1
innodb_flush_log_at_trx_commit=1
```

### 从库配置

```ini
[mysqld]
server_id=2
gtid_mode=ON
enforce_gtid_consistency=ON
log_bin=mysql-bin
binlog_format=ROW
read_only=ON
super_read_only=ON
relay_log=relay-bin
```

### 建立复制

```sql
-- 主库创建复制用户
CREATE USER 'repl'@'%' IDENTIFIED BY 'strong_password';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

-- 从库配置复制
CHANGE MASTER TO
    MASTER_HOST='10.0.1.10',
    MASTER_USER='repl',
    MASTER_PASSWORD='strong_password',
    MASTER_AUTO_POSITION=1;

START SLAVE;
SHOW SLAVE STATUS\G
```

## 半同步复制

```sql
-- 主库
INSTALL PLUGIN rpl_semi_sync_master SONAME 'semisync_master.so';
SET GLOBAL rpl_semi_sync_master_enabled = 1;
SET GLOBAL rpl_semi_sync_master_timeout = 3000;  -- 3秒超时降级为异步

-- 从库
INSTALL PLUGIN rpl_semi_sync_slave SONAME 'semisync_slave.so';
SET GLOBAL rpl_semi_sync_slave_enabled = 1;
STOP SLAVE IO_THREAD; START SLAVE IO_THREAD;
```

## 延迟从库

```sql
-- 设置延迟 1 小时的从库（用于误操作恢复）
CHANGE MASTER TO MASTER_DELAY = 3600;
```

## 读写分离最佳实践

```yaml
# 应用层读写分离示例 (Spring Boot)
spring:
  datasource:
    master:
      url: jdbc:mysql://master:3306/db
      username: write_user
    slave:
      url: jdbc:mysql://slave:3306/db
      username: read_user
```
