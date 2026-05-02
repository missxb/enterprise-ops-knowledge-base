# High Memory

## 症状
- 可用内存持续下降
- swap 使用增加
- 可能触发 OOM

## 排查步骤

```bash
# 1. 查看内存使用
free -h
cat /proc/meminfo | grep -E "^(MemTotal|MemAvailable|Cached|SwapFree)"

# 2. 找到占用最高的进程
ps aux --sort=-%mem | head -10
smem -t -k -s rss | tail -10

# 3. 查看进程详细内存
pmap -x <pid> | tail -1

# 4. 检查是否内存泄漏
valgrind --leak-check=full ./program
```

## 常见原因及解决
1. **内存泄漏** → 修复代码
2. **缓存过大** → 调整缓存策略
3. **连接池泄漏** → 检查连接池配置
4. **正常增长** → 扩容内存
