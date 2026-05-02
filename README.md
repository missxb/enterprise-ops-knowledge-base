# 企业级运维知识库 (Enterprise Ops Knowledge Base)

> 一套完整的、可落地的企业级运维知识体系，涵盖从系统管理到安全合规的全部12个核心领域。

## 📚 知识库目录

| # | 项目 | 说明 | 核心技术栈 |
|---|------|------|-----------|
| 01 | [Linux系统管理与优化](01-linux-system-admin/) | 系统初始化、内核优化、性能分析、安全加固 | CentOS 7/8, Ubuntu 20.04/22.04, systemd |
| 02 | [Docker容器化实战](02-docker-containerization/) | Dockerfile最佳实践、编排、私有仓库、安全 | Docker, Compose, Harbor |
| 03 | [Kubernetes集群管理](03-kubernetes-cluster/) | 集群部署、网络、存储、调度、安全管理 | K8s, Calico, Cilium, Helm |
| 04 | [CI/CD流水线建设](04-cicd-pipeline/) | Jenkins/GitLab CI、制品管理、发布策略 | Jenkins, GitLab CI, ArgoCD |
| 05 | [Prometheus监控体系](05-prometheus-monitoring/) | 监控部署、告警、Grafana仪表盘、长期存储 | Prometheus, Grafana, Thanos |
| 06 | [ELK日志管理平台](06-elk-log-platform/) | ES集群、日志采集解析、告警、生命周期管理 | Elasticsearch, Logstash, Kibana |
| 07 | [Ansible自动化运维](07-ansible-automation/) | Inventory、Role、Playbook、AWX、批量管理 | Ansible, AWX |
| 08 | [Terraform基础设施即代码](08-terraform-iac/) | 阿里云/AWS资源编排、模块化、多环境管理 | Terraform, 阿里云, AWS |
| 09 | [企业上云实战](09-cloud-migration/) | 上云评估、架构设计、数据迁移、混合云 | 阿里云, AWS, DTS |
| 10 | [数据库高可用架构](10-database-ha/) | MySQL/Redis/PG/MongoDB HA、备份、监控 | MySQL, Redis, PostgreSQL, MongoDB |
| 11 | [Nginx/OpenResty网关](11-nginx-gateway/) | 高性能配置、WAF、限流、灰度发布、动态路由 | Nginx, OpenResty, Lua |
| 12 | [安全加固与等保合规](12-security-hardening/) | CIS加固、漏洞扫描、等保2.0、密钥管理 | Vault, Trivy, auditd |

## 🏗️ 知识库架构

```
企业级运维知识库/
├── README.md                          # 本文件 - 总目录
├── 01-linux-system-admin/             # Linux系统管理
│   └── linux-system-admin.md          # 完整手册
├── 02-docker-containerization/        # Docker容器化
│   └── docker-containerization.md     # 完整手册
├── 03-kubernetes-cluster/             # K8s集群管理
│   └── kubernetes-cluster.md          # 完整手册
├── 04-cicd-pipeline/                  # CI/CD流水线
│   └── cicd-pipeline.md              # 完整手册
├── 05-prometheus-monitoring/          # Prometheus监控
│   └── prometheus-monitoring.md       # 完整手册
├── 06-elk-log-platform/              # ELK日志平台
│   └── elk-log-platform.md           # 完整手册
├── 07-ansible-automation/            # Ansible自动化
│   └── ansible-automation.md         # 完整手册
├── 08-terraform-iac/                 # Terraform IaC
│   └── terraform-iac.md             # 完整手册
├── 09-cloud-migration/               # 企业上云
│   └── cloud-migration.md           # 完整手册
├── 10-database-ha/                   # 数据库高可用
│   └── database-ha.md              # 完整手册
├── 11-nginx-gateway/                # Nginx网关
│   └── nginx-gateway.md            # 完整手册
└── 12-security-hardening/           # 安全加固
    └── security-hardening.md        # 完整手册
```

## 📖 每个文档的结构

每个项目的主文档都遵循统一结构：

1. **项目背景与架构设计** - 为什么需要、整体架构图
2. **环境准备与依赖说明** - 硬件要求、软件依赖、网络规划
3. **完整部署步骤** - 可直接执行的脚本和配置文件
4. **运维手册** - 日常操作、扩缩容、升级、备份恢复
5. **故障排查手册** - 常见问题及解决方案
6. **最佳实践与注意事项** - 生产环境经验总结

## 🎯 使用建议

### 新手路径
```
01-Linux基础 → 02-Docker → 03-K8s → 05-监控 → 06-日志
```

### 运维工程师路径
```
01-Linux → 07-Ansible → 08-Terraform → 10-数据库 → 12-安全
```

### DevOps工程师路径
```
02-Docker → 03-K8s → 04-CI/CD → 05-监控 → 06-日志 → 09-上云
```

### 架构师路径
```
全部通读 → 重点关注03/08/09/10的架构设计部分
```

## ⚠️ 声明

- 本知识库中的配置和脚本已在生产环境验证，但请在测试环境先行验证后再应用到生产
- 密码、密钥等敏感信息均为示例，请务必替换为实际的安全值
- 技术版本以文档编写时的最新稳定版为准，请根据实际情况调整

---

> 📅 创建时间：2026-05-02 | 📝 维护：持续更新中
