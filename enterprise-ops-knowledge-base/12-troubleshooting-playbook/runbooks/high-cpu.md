# High Cpu

## 症状
- 系统响应缓慢
- load average 持续高于 CPU 核心数

## 排查步骤

```bash
# 1. 确认 CPU 使用
top -bn1 | head -5
mpstat -P ALL 1 3

# 2. 找到占用最高的进程
pidstat -u 1 5 | sort -k3 -rn | head -10

# 3. 查看进程线程
top -Hp <pid>

# 4. 分析进程行为
strace -cp <pid> -e trace=all

# 5. 生成火焰图
perf record -F 99 -p <pid> --call-graph dwarf -- sleep 30
```

## 常见原因及解决
1. **死循环/代码bug** → 修复代码
2. **频繁GC** → 调整 JVM 参数
3. **加密计算** → 硬件加速
4. **正常业务高峰** → 扩容
