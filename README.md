# 企业级运维知识库 & 实战项目

> 基于 25+ 个语雀知识库学习整理，结合企业实际场景编写
> 包含 15 个完整的企业级运维实战项目

## 知识库来源

| 来源 | 主题 | 规模 |
|------|------|------|
| dataflux/nhkhqo | 技术沙龙（云运维实战） | 124篇, 27万字 |
| zerd-xinghai/cloud | 云计算运维公开知识库 | 118篇, 59万字 |
| skydeity/linux | Linux运维笔记 | 240篇, 26万字 |
| desistdaydream/learning | IT综合学习知识库 | 1222篇, 251万字 |
| bairuijun/qb6lb5 | 运维知识库(WebLogic/Oracle) | 31篇 |
| shishuifox/dev | 运维知识库 | - |
| sdliang/ops | 运维DevOps | - |
| anson-e1puz/k8s | K8S学习笔记 | - |
| yongz/docker | Docker学习记录 | - |
| 其他16个知识库 | 综合运维/云原生/安全 | - |

## 实战项目清单

### 📁 01-linux-ops — Linux 运维实战知识库
- 系统性能排查速查表（CPU/内存/磁盘/网络）
- 常见故障处理手册
- Shell 脚本实战（日志清理/健康检查/磁盘告警）
- 系统加固清单（SSH/内核参数）
- 定时任务最佳实践

### 📁 02-cloud-migration — 企业级跨云迁移（阿里云→腾讯云）
- 完整迁移方案设计（15台ECS + RDS + Redis + OSS）
- 自动化迁移脚本（环境检查/数据同步/数据库迁移）
- 数据一致性校验（MySQL + Redis）
- 灰度切换与回滚
- Ansible 自动化编排

### 📁 03-k8s-cluster — Kubernetes 高可用集群部署
- 3 Master + 5 Worker 架构
- HAProxy + Keepalived 负载均衡
- kubeadm 自动化部署全流程
- etcd 备份恢复方案（自动定时备份）
- 集群验证与故障排查手册

### 📁 04-monitoring — 企业级监控告警系统
- Prometheus + Grafana + Alertmanager 全栈监控
- 节点告警规则（CPU/内存/磁盘/网络/服务可用性）
- 告警分级路由（critical → 电话+钉钉+邮件, warning → 钉钉+邮件）
- Docker Compose 一键部署
- 支持 Node/cAdvisor/Blackbox/Redis/MySQL/Nginx Exporter

### 📁 05-devops-cicd — DevOps CI/CD 流水线 ⭐ NEW
- GitLab CI 多阶段 Pipeline（Build→Test→Scan→Deploy）
- 多环境管理（Dev/Staging/Production）
- 灰度发布与回滚
- SonarQube 代码扫描 + Trivy 镜像安全扫描
- Harbor 镜像仓库集成
- GitLab Runner 安装配置脚本
- 企业级 Dockerfile（多阶段构建/非root/健康检查）
- K8S 部署模板（Deployment+Service+Ingress+HPA+PDB）

### 📁 06-security — 企业安全加固 ⭐ NEW
- 系统安全加固脚本（一键加固，满足等保2.0三级）
- SSH 加固（端口修改/密钥认证/fail2ban/加密算法）
- 内核安全参数（ASLR/SYN防护/ICMP限制/连接跟踪）
- 审计日志配置（auditd 完整规则集）
- 防火墙配置（iptables 规则/端口扫描防护）
- 密码策略（复杂度/过期/锁定）
- 文件权限加固（SUID/SGID/权限收紧）

### 📁 07-database-ops — 数据库运维规范 ⭐ NEW
- MySQL 高可用架构（ProxySQL + MHA）
- MySQL 生产环境优化配置（8C32G 规格调优）
- Redis 生产环境优化配置（内存淘汰/持久化/安全）
- 企业级 MySQL 备份脚本（全量+增量+binlog+异地）
- 备份验证与恢复
- 慢查询分析

### 📁 08-elk-logging — ELK 日志收集与分析系统 ⭐ NEW
- 完整架构：Filebeat → Kafka → Logstash → Elasticsearch → Kibana
- Docker Compose 一键部署全套 ELK
- Filebeat 多源日志采集配置（系统/Nginx/应用/容器）
- Logstash Pipeline（Nginx日志解析/GeoIP/UserAgent/慢请求标记）
- 热温冷分层存储 + ILM 生命周期管理

### 📁 09-terraform-ansible — 基础设施即代码（IaC） ⭐ NEW
- Terraform 阿里云生产环境定义（VPC/ECS/RDS/Redis/SLB）
- 远程状态存储（OSS + TableStore 锁）
- 多环境管理（Dev/Staging/Production）
- Ansible Playbook 体系（Common/Docker/Nginx/MySQL/Redis/Security）
- Ansible Role 示例（系统初始化/安全加固/软件安装）

### 📁 10-disaster-recovery — 灾难恢复与业务连续性 ⭐ NEW
- RTO/RPO 分级目标（核心系统 RTO<15min, RPO=0）
- 故障场景矩阵（单点/机房/区域灾难）
- 自动故障切换脚本（MySQL/Redis/应用层）
- 备份恢复演练手册
- Keepalived 主备配置

### 📁 11-performance-testing — 性能测试与压测 ⭐ NEW
- 压测场景设计（基准/负载/压力/峰值/稳定性/容量）
- JMeter 测试计划
- 结果分析与报告生成
- 性能调优手册

### 📁 12-service-mesh — Service Mesh（Istio） ⭐ NEW
- Istio 控制面 + Envoy Sidecar 架构
- 流量管理（金丝雀/A/B测试/流量镜像）
- 服务安全（mTLS/认证授权/RBAC）
- 可观测性（分布式追踪/指标/访问日志）
- 故障注入与熔断

### 📁 13-gitops — GitOps 持续部署（ArgoCD） ⭐ NEW
- GitOps 工作流设计
- ArgoCD 安装与配置
- Kustomize 多环境管理
- 自动同步与回滚

### 📁 14-container-security — 容器安全 ⭐ NEW
- Trivy 镜像扫描
- Falco 运行时威胁检测
- OPA/Gatekeeper 准入控制
- NetworkPolicy 网络策略
- CIS Benchmark 合规检查

### 📁 15-platform-engineering — 平台工程（IDP） ⭐ NEW
- 内部开发者平台设计
- Backstage 服务目录
- 自助式环境供给
- 黄金路径模板

## 学习路线

```
第一阶段：基础运维（1-2个月）
├── Linux 基础 → 网络 → Shell 脚本 → 服务管理
├── 项目：01-linux-ops
└── 掌握：系统排查、故障处理、脚本编写

第二阶段：容器化（1-2个月）
├── Docker → Docker Compose → K8S 集群
├── 项目：03-k8s-cluster, 04-monitoring
└── 掌握：容器编排、集群管理、监控告警

第三阶段：DevOps（1-2个月）
├── CI/CD → GitLab CI → Harbor → 安全扫描
├── 项目：05-devops-cicd, 13-gitops
└── 掌握：自动化构建、多环境部署、GitOps

第四阶段：云原生进阶（2-3个月）
├── Service Mesh → 容器安全 → 平台工程
├── 项目：12-service-mesh, 14-container-security, 15-platform-engineering
└── 掌握：服务治理、安全体系、平台建设

第五阶段：企业级综合（2-3个月）
├── 云迁移 → IaC → 灾难恢复 → 日志系统
├── 项目：02-cloud-migration, 06-security, 07-database-ops, 08-elk-logging, 09-terraform-ansible, 10-disaster-recovery
└── 掌握：企业级运维全流程
```

## 快速开始

```bash
# 克隆仓库
git clone https://github.com/missxb/enterprise-ops-knowledge-base.git
cd enterprise-ops-knowledge-base

# 部署监控系统
cd 04-monitoring
chmod +x scripts/deploy.sh
./scripts/deploy.sh install
./scripts/deploy.sh start

# 系统安全加固
cd 06-security/scripts
chmod +x system-hardening.sh
./system-hardening.sh full

# MySQL 全量备份
cd 07-database-ops/scripts
chmod +x mysql-backup.sh
./mysql-backup.sh full

# 部署 ELK 日志系统
cd 08-elk-logging
docker-compose up -d
```

## 目录总览

```
enterprise-ops-knowledge-base/
├── 01-linux-ops/           # Linux 运维知识库
├── 02-cloud-migration/     # 跨云迁移项目
├── 03-k8s-cluster/         # K8S 高可用集群
├── 04-monitoring/          # 监控告警系统
├── 05-devops-cicd/         # CI/CD 流水线      ⭐
├── 06-security/            # 安全加固           ⭐
├── 07-database-ops/        # 数据库运维         ⭐
├── 08-elk-logging/         # ELK 日志系统       ⭐
├── 09-terraform-ansible/   # IaC 自动化         ⭐
├── 10-disaster-recovery/   # 灾难恢复           ⭐
├── 11-performance-testing/ # 性能测试           ⭐
├── 12-service-mesh/        # Istio 服务网格     ⭐
├── 13-gitops/              # ArgoCD GitOps      ⭐
├── 14-container-security/  # 容器安全           ⭐
├── 15-platform-engineering/# 平台工程           ⭐
└── README.md
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可

MIT License
