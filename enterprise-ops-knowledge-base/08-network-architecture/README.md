# 08 - 网络架构与安全

## 概述

本模块涵盖企业级网络架构设计、负载均衡、代理服务、DNS 管理、VPN 搭建、防火墙配置及服务网格等核心网络技术。从传统数据中心网络到云原生网络架构，提供完整的网络基础设施建设方案。

## 目录结构

```
08-network-architecture/
├── README.md                        # 本文件
├── docs/                            # 技术文档
│   ├── 01-network-design.md         # 企业网络架构设计
│   ├── 02-nginx-enterprise.md       # Nginx 企业级部署
│   ├── 03-ha-proxy.md              # HAProxy 高可用
│   ├── 04-traefik-proxy.md         # Traefik 云原生代理
│   ├── 05-dns-management.md        # DNS 管理
│   ├── 06-vpn-setup.md             # VPN 搭建
│   ├── 07-firewall-iptables.md     # 防火墙管理
│   └── 08-service-mesh.md          # 服务网格
├── examples/                        # 配置示例
│   ├── nginx/                       # Nginx 配置
│   ├── haproxy/                     # HAProxy 配置
│   └── traefik/                     # Traefik 配置
├── scripts/                         # 部署与管理脚本
│   ├── nginx-deploy.sh
│   ├── ssl-cert-manager.sh
│   └── network-diagnostic.sh
└── best-practices/                  # 最佳实践
    ├── ssl-tls-best-practices.md
    └── rate-limiting.md
```

## 学习路径

1. **基础网络** → `01-network-design.md` 理解企业网络全貌
2. **负载均衡** → Nginx → HAProxy → Traefik 逐步深入
3. **网络安全** → 防火墙 → VPN → SSL/TLS
4. **云原生** → 服务网格（Istio）
5. **最佳实践** → 限流策略、SSL 最佳实践

## 适用场景

- 企业数据中心网络规划
- 高并发 Web 架构设计
- 多机房容灾与负载均衡
- 零信任网络安全架构
- Kubernetes Ingress 与服务网格
