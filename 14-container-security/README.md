# 项目十三：容器安全

## 项目背景

建立完整的容器安全体系，覆盖镜像安全、运行时安全、网络安全、合规审计。

## 安全架构

```
┌─────────────────────────────────────────────────────────┐
│                    容器安全体系                           │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  镜像安全    │  │  运行时安全   │  │  网络安全    │  │
│  │              │  │              │  │              │  │
│  │ - Trivy扫描  │  │ - Falco检测  │  │ - NetworkPol│  │
│  │ - 签名验证   │  │ - Seccomp    │  │ - mTLS      │  │
│  │ - 基础镜像   │  │ - AppArmor   │  │ - 服务网格   │  │
│  │ - 漏洞管理   │  │ - 镜像不可变 │  │ - 出口控制   │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  准入控制    │  │  合规审计    │  │  密钥管理    │  │
│  │              │  │              │  │              │  │
│  │ - OPA/Gatekeeper│- CIS Benchmark│- Vault       │  │
│  │ - Kyverno    │  │ - 等保合规   │  │ - Sealed Sec│  │
│  │ - 策略即代码 │  │ - 审计日志   │  │ - External S│  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## 目录结构

```
14-container-security/
├── README.md
├── trivy/
│   ├── trivy-config.yaml           # Trivy 配置
│   └── scan-policy.yaml            # 扫描策略
├── falco/
│   ├── falco.yaml                  # Falco 配置
│   └── custom-rules.yaml           # 自定义规则
├── scripts/
│   ├── image-scan.sh               # 镜像扫描脚本
│   ├── runtime-monitor.sh          # 运行时监控
│   └── compliance-check.sh         # 合规检查
├── config/
│   ├── network-policy.yaml         # 网络策略
│   ├── pod-security-policy.yaml    # Pod 安全策略
│   └── opa-constraints.yaml        # OPA 约束
└── docs/
    ├── container-security-guide.md # 容器安全指南
    └── cis-benchmark.md            # CIS Benchmark 检查
```
