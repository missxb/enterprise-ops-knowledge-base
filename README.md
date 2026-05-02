# 企业级运维知识库 & 实战项目

> 基于 25+ 个语雀知识库学习整理，结合企业实际场景编写

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

### 项目一：企业级服务器跨云迁移（阿里云→腾讯云）
- 完整迁移方案设计
- 自动化迁移脚本
- 数据一致性校验
- 灰度切换与回滚
- 📁 `02-cloud-migration/`

### 项目二：Kubernetes 高可用集群部署
- 3 Master + N Worker 架构
- HAProxy + Keepalived 负载均衡
- Calico 网络插件
- 自动化部署全流程
- 📁 `03-k8s-cluster/`

### 项目三：企业级监控告警系统
- Prometheus + Grafana 全栈监控
- 自定义 Exporter 开发
- 告警规则与分级
- 运维大屏展示
- 📁 `04-monitoring/`

### 项目四：DevOps CI/CD 流水线
- GitLab CI 自动化构建
- 多环境部署策略
- 镜像安全扫描
- 📁 `05-devops-cicd/`

### 项目五：企业安全加固
- WAF + 云防火墙配置
- SSH 加固与审计
- AK 泄露防护
- 📁 `06-security/`

### 项目六：数据库运维规范
- MySQL 高可用架构
- Redis 设计规范
- 备份恢复演练
- 📁 `07-database-ops/`

## 学习路线

```
Linux基础 → 网络 → Shell脚本 → 服务管理
    ↓
Docker容器化 → K8S集群 → 云原生
    ↓
监控告警 → CI/CD → 安全加固
    ↓
企业级综合项目实战
```
