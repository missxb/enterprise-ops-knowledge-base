# Disk Full

## 症状
- 写入失败
- 服务异常

## 排查步骤

```bash
# 1. 确认磁盘使用
df -h
df -ih  # inode 使用

# 2. 找到大文件/目录
du -sh /* | sort -rh | head -10
du -sh /var/* | sort -rh | head -10

# 3. 检查已删除未释放的文件
lsof | grep deleted

# 4. 检查日志文件
find /var/log -size +100M
```

## 紧急处理
```bash
# 清理日志
> /var/log/messages
> /var/log/secure

# 清理已删除文件（重启进程释放句柄）
lsof | grep deleted | awk '{print $2}' | sort -u | xargs kill -HUP

# 清理临时文件
find /tmp -type f -atime +7 -delete
```
