# Dns Resolution Failed

## 症状
- 域名解析失败
- 服务无法访问

## 排查步骤

```bash
# 1. 检查 DNS 配置
cat /etc/resolv.conf

# 2. 测试 DNS 解析
nslookup domain.com
dig domain.com @8.8.8.8
dig domain.com +trace

# 3. 检查 DNS 服务
systemctl status named  # 或其他 DNS 服务

# 4. 检查网络连通性
ping dns_server_ip
traceroute dns_server_ip
```

## 常见原因及解决
1. **resolv.conf 错误** → 修正配置
2. **DNS 服务故障** → 切换 DNS
3. **网络不通** → 检查网络
4. **域名过期** → 续费域名
