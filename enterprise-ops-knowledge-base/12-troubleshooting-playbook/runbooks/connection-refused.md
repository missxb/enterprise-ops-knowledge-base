# Connection Refused

## 症状
- 连接被拒绝
- 服务不可达

## 排查步骤

```bash
# 1. 检查服务是否运行
systemctl status <service>
ps aux | grep <service>

# 2. 检查端口监听
ss -tlnp | grep <port>
netstat -tlnp | grep <port>

# 3. 检查防火墙
iptables -L -n
firewall-cmd --list-all

# 4. 检查连接数限制
cat /proc/sys/net/core/somaxconn
ulimit -n
```

## 常见原因及解决
1. **服务未启动** → 启动服务
2. **端口未监听** → 检查配置
3. **防火墙阻止** → 添加规则
4. **连接数满** → 增大限制
