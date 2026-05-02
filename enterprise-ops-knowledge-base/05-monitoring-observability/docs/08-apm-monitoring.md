# Apm Monitoring

> 本文档正在完善中，以下是核心内容

## 概述

SkyWalking 是 Apache 基金会下的 APM 系统，支持 Java、Go、Node.js 等多语言探针。

## 架构

```
App (Agent) → SkyWalking OAP → Storage (ES/MySQL)
                              ↓
                         SkyWalking UI
```

## 快速部署

```bash
# Docker 部署 SkyWalking
docker run -d --name skywalking-oap   -e SW_STORAGE=elasticsearch   -e SW_STORAGE_ES_CLUSTER_NODES=es:9200   -p 11800:11800 -p 12800:12800   apache/skywalking-oap-server:9.7.0

docker run -d --name skywalking-ui   -e SW_OAP_ADDRESS=http://skywalking-oap:12800   -p 8080:8080   apache/skywalking-ui:9.7.0
```

## 最佳实践

1. 选择合适的探针（Java Agent 最成熟）
2. 配置合理的采样率
3. 使用拓扑图分析服务依赖
4. 设置告警规则
