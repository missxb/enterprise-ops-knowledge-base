# 入侵检测系统

## 概述

入侵检测系统 (IDS) 监控系统活动，检测可疑行为并发出告警。

## 方案选型

| 工具 | 类型 | 特点 |
|------|------|------|
| Wazuh | HIDS | OSSEC 升级版，ELK 集成 |
| Fail2ban | 防暴力破解 | 自动封禁 IP |
| AIDE | 文件完整性 | 检测文件篡改 |
| Snort/Suricata | NIDS | 网络入侵检测 |

## Fail2ban 部署

```bash
# 安装
yum install -y fail2ban

# /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = firewallcmd-ipset

[sshd]
enabled = true
port = 22222
logpath = /var/log/secure
maxretry = 3
bantime = 86400

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 5

# 启动
systemctl enable fail2ban
systemctl start fail2ban

# 查看封禁状态
fail2ban-client status sshd
```

## AIDE 文件完整性检查

```bash
# 安装
yum install -y aide

# 初始化数据库
aide --init
mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# 检查
aide --check

# 定期检查 (crontab)
0 3 * * * /usr/sbin/aide --check | mail -s "AIDE Report" admin@example.com
```

## Wazuh 部署

```yaml
# docker-compose.yml
version: '3'
services:
  wazuh:
    image: wazuh/wazuh-manager:4.7.0
    ports:
      - "1514:1514"
      - "1515:1515"
      - "55000:55000"
    volumes:
      - wazuh-data:/var/ossec/data

  wazuh-kibana:
    image: wazuh/wazuh-dashboard:4.7.0
    ports:
      - "5601:5601"
    environment:
      - INDEXER_URL=https://wazuh-indexer:9200
```

## 日志审计

```bash
# 关键日志检查
# 登录失败
grep "Failed password" /var/log/secure | awk '{print $11}' | sort | uniq -c | sort -rn | head -10

# sudo 使用
grep "sudo:" /var/log/secure | tail -20

# 暴力破解检测
journalctl -u sshd --since "1 hour ago" | grep -c "Failed password"
```
