# 02-docker-containerization - Docker 容器化实战

## 模块概述

本模块系统性地覆盖 Docker 容器化技术栈，从架构原理到生产实践，面向企业级运维工程师。内容涵盖容器构建、网络、存储、安全、编排、日志、镜像仓库及运行时等核心领域。

## 目录结构

```
02-docker-containerization/
├── README.md                           # 本文件
├── docs/                               # 核心文档
│   ├── 01-docker-architecture.md       # Docker 架构深入
│   ├── 02-dockerfile-best-practices.md # Dockerfile 最佳实践
│   ├── 03-docker-networking.md         # Docker 网络模型
│   ├── 04-docker-storage.md            # Docker 存储 (Volume/Bind/NFS)
│   ├── 05-docker-security.md           # Docker 安全加固
│   ├── 06-docker-compose.md            # Docker Compose 编排
│   ├── 07-private-registry.md          # 私有镜像仓库 (Harbor)
│   ├── 08-docker-logging.md            # Docker 日志管理
│   └── 09-container-runtime.md         # 容器运行时 (containerd/CRI-O)
├── examples/                           # 生产级示例
│   ├── dockerfiles/                    # 多语言 Dockerfile
│   ├── compose/                        # Compose 编排模板
│   └── harbor/                         # Harbor 部署指南
├── scripts/                            # 运维脚本
│   ├── docker-install.sh              # Docker 安装脚本
│   ├── docker-cleanup.sh              # 镜像/容器清理脚本
│   ├── image-scan.sh                  # 镜像安全扫描
│   └── container-monitor.sh           # 容器监控脚本
└── best-practices/                     # 最佳实践
    ├── image-optimization.md           # 镜像优化策略
    ├── resource-limits.md             # 资源限制配置
    └── graceful-shutdown.md           # 优雅停机方案
```

## 学习路径

### 入门阶段
1. **Docker 架构** → 理解 Docker 引擎、镜像分层、容器生命周期
2. **Dockerfile 最佳实践** → 掌握多阶段构建、缓存优化、安全基础镜像选择

### 进阶阶段
3. **网络模型** → bridge/host/overlay/macvlan 四种网络模式深度理解
4. **存储管理** → Volume/Bind Mount/NFS 适用场景与性能对比
5. **Docker Compose** → 多容器编排、服务依赖、环境隔离

### 生产阶段
6. **安全加固** → Rootless Docker、Seccomp、AppArmor、镜像签名
7. **私有仓库** → Harbor 高可用部署、镜像复制、漏洞扫描
8. **日志管理** → 日志驱动选型、EFK/Loki 集成
9. **容器运行时** → containerd/CRI-O 对比、Kata/gVisor 安全容器

## 适用场景

| 场景 | 推荐方案 | 参考文档 |
|------|----------|----------|
| 开发环境标准化 | Docker Compose | 06-docker-compose.md |
| CI/CD 流水线 | 多阶段构建 + 镜像扫描 | 02, scripts/image-scan.sh |
| 微服务部署 | Compose/Swarm + 私有仓库 | 06, 07-private-registry.md |
| 生产安全加固 | Rootless + Seccomp + 只读 FS | 05-docker-security.md |
| 日志集中采集 | Docker 日志驱动 + EFK | 08-docker-logging.md |

## 快速开始

```bash
# 1. 安装 Docker
sudo bash scripts/docker-install.sh

# 2. 运行第一个容器
docker run -d --name nginx -p 80:80 nginx:alpine

# 3. 查看容器日志
docker logs -f nginx

# 4. 清理无用资源
sudo bash scripts/docker-cleanup.sh
```

## 生产检查清单

- [ ] Docker 版本是否为 LTS 稳定版
- [ ] 是否配置了镜像加速器 / 私有仓库
- [ ] 容器是否以非 root 用户运行
- [ ] 是否设置了 CPU/内存资源限制
- [ ] 是否配置了日志轮转 (max-size/max-file)
- [ ] 是否启用了镜像签名验证
- [ ] 是否定期执行镜像安全扫描
- [ ] 是否配置了容器健康检查 (HEALTHCHECK)
- [ ] 是否有优雅停机方案 (STOPSIGNAL + pre-stop hook)
- [ ] 是否有镜像和容器清理策略

## 相关工具

| 工具 | 用途 | 官方地址 |
|------|------|----------|
| Docker CE | 容器引擎 | https://docs.docker.com |
| Docker Compose | 多容器编排 | https://docs.docker.com/compose |
| Harbor | 私有镜像仓库 | https://goharbor.io |
| Trivy | 镜像安全扫描 | https://aquasecurity.github.io/trivy |
| Dive | 镜像层分析 | https://github.com/wagoodman/dive |
| ctop | 容器监控 | https://github.com/bcicen/ctop |
| Lazydocker | Docker TUI | https://github.com/jesseduffield/lazydocker |
