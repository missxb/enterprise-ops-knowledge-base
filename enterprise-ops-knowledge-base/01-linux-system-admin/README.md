# 01 - Linux 系统管理与安全加固

## 模块概述

本模块涵盖企业级 Linux 系统管理的核心知识体系，从内核参数优化到安全加固，从性能调优到日志管理，为运维工程师提供一套完整的生产环境管理指南。

## 适用对象

- 中高级 Linux 运维工程师
- SRE（站点可靠性工程师）
- DevOps 工程师
- 系统架构师

## 学习路径

### 第一阶段：系统性能优化（建议 2-3 周）

| 序号 | 主题 | 文档 | 核心技能 |
|------|------|------|----------|
| 1 | 内核参数优化 | [01-kernel-optimization.md](docs/01-kernel-optimization.md) | sysctl 调优、内核参数理解 |
| 2 | 内存管理与优化 | [02-memory-management.md](docs/02-memory-management.md) | OOM 调优、内存回收策略 |
| 3 | 磁盘 I/O 优化 | [03-disk-io-optimization.md](docs/03-disk-io-optimization.md) | I/O 调度器、文件系统优化 |
| 4 | 网络参数调优 | [04-network-tuning.md](docs/04-network-tuning.md) | TCP 调优、网络栈优化 |
| 5 | 进程管理与调度 | [05-process-management.md](docs/05-process-management.md) | CFS 调度、cgroup、nice/renice |

### 第二阶段：系统服务管理（建议 1-2 周）

| 序号 | 主题 | 文档 | 核心技能 |
|------|------|------|----------|
| 6 | systemd 服务管理 | [06-systemd-service.md](docs/06-systemd-service.md) | Unit 文件编写、服务编排 |
| 7 | 日志管理 | [07-log-management.md](docs/07-log-management.md) | journald、logrotate、集中式日志 |

### 第三阶段：安全加固（建议 2-3 周）

| 序号 | 主题 | 文档 | 核心技能 |
|------|------|------|----------|
| 8 | 用户权限管理 | [08-user-permission.md](docs/08-user-permission.md) | sudo、PAM、ACL |
| 9 | SSH 安全加固 | [09-ssh-hardening.md](docs/09-ssh-hardening.md) | 密钥管理、跳板机、审计 |
| 10 | 性能基准测试 | [10-performance-benchmark.md](docs/10-performance-benchmark.md) | 基准测试工具、压测方法 |

## 生产级脚本

| 脚本 | 用途 | 使用场景 |
|------|------|----------|
| [system-init.sh](scripts/system-init.sh) | 系统初始化 | 新服务器上线前 |
| [security-hardening.sh](scripts/security-hardening.sh) | 安全加固 | 合规检查前、服务器上线前 |
| [performance-tuning.sh](scripts/performance-tuning.sh) | 性能调优 | 大促前、性能瓶颈排查 |
| [log-analyzer.sh](scripts/log-analyzer.sh) | 日志分析 | 故障排查、安全事件分析 |
| [health-check.sh](scripts/health-check.sh) | 健康检查 | 日常巡检、监控告警 |

## 配置示例

| 配置文件 | 说明 |
|----------|------|
| [sysctl.conf](examples/sysctl.conf) | 生产环境内核参数配置 |
| [limits.conf](examples/limits.conf) | 资源限制配置 |
| [logrotate.d/](examples/logrotate.d/) | 日志轮转配置示例 |
| [sudoers.d/](examples/sudoers.d/) | sudo 权限配置示例 |

## 最佳实践

| 文档 | 说明 |
|------|------|
| [服务器命名规范](best-practices/server-naming-convention.md) | 统一命名标准 |
| [备份策略](best-practices/backup-strategy.md) | 3-2-1 备份原则与实施方案 |
| [补丁管理流程](best-practices/patch-management.md) | 安全补丁与内核升级管理 |

## 企业场景参考

### 电商行业
- **大促前性能调优**：内核参数优化 + 网络调优 + I/O 调度器切换
- **秒杀场景**：连接数优化 + TIME_WAIT 快速回收 + 内存预分配

### 金融行业
- **等保合规**：安全基线配置 + 审计日志 + 访问控制
- **交易系统**：低延迟网络调优 + CPU 亲和性绑定 + NUMA 优化

### 互联网行业
- **高并发 Web 服务**：文件描述符限制 + TCP 参数调优 + 进程调度优化
- **容器化部署**：cgroup 资源限制 + namespace 隔离 + overlay fs 优化

## 版本兼容性

本文档主要基于以下系统版本编写，其他发行版可参考适配：

- CentOS 7.x / 8.x / Rocky Linux 8.x / 9.x
- Ubuntu 18.04 / 20.04 / 22.04 LTS
- 内核版本：3.10+ / 4.x / 5.x / 6.x

## 快速开始

```bash
# 1. 克隆知识库
cd /root/.openclaw/workspace/enterprise-ops-knowledge-base

# 2. 执行系统初始化（需要 root 权限）
bash 01-linux-system-admin/scripts/system-init.sh

# 3. 执行安全加固
bash 01-linux-system-admin/scripts/security-hardening.sh

# 4. 执行性能调优
bash 01-linux-system-admin/scripts/performance-tuning.sh

# 5. 运行健康检查
bash 01-linux-system-admin/scripts/health-check.sh
```

> ⚠️ **重要提示**：所有脚本在生产环境执行前，务必先在测试环境验证。脚本执行前会创建备份，但请确保有完整的系统快照或备份。
