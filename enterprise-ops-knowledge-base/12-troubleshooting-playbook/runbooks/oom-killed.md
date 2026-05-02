# Oom Killed

## 症状
- 进程突然消失
- dmesg 中有 OOM 记录

## 排查步骤

```bash
# 1. 确认 OOM 事件
dmesg | grep -i oom
journalctl -k | grep -i oom

# 2. 查看被杀进程
dmesg | grep "Killed process"

# 3. 检查内存限制
ulimit -a
cat /proc/<pid>/limits
```

## 预防措施
1. 合理设置内存限制
2. 优化应用内存使用
3. 配置 OOM 优先级
4. 增加物理内存或 swap
