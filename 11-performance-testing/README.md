# 项目十：性能测试与压测

## 项目背景

建立完整的性能测试体系，确保系统在高并发场景下的稳定性和性能。

## 压测场景设计

| 场景 | 并发数 | 持续时间 | 目标 |
|------|--------|----------|------|
| 基准测试 | 10 | 5分钟 | 建立性能基线 |
| 负载测试 | 100→1000 | 30分钟 | 验证正常负载 |
| 压力测试 | 1000→5000 | 15分钟 | 找到系统瓶颈 |
| 峰值测试 | 5000→10000 | 5分钟 | 验证峰值能力 |
| 稳定性测试 | 500 | 24小时 | 验证长期稳定性 |
| 容量测试 | 逐步增加 | 2小时 | 确定系统容量 |

## 目录结构

```
11-performance-testing/
├── README.md
├── jmeter/
│   ├── test-plans/
│   │   ├── api-benchmark.jmx       # API 基准测试
│   │   ├── load-test.jmx           # 负载测试
│   │   └── stress-test.jmx         # 压力测试
│   └── reports/
├── scripts/
│   ├── run-jmeter.sh               # JMeter 执行脚本
│   ├── analyze-results.sh          # 结果分析脚本
│   └── generate-report.sh          # 报告生成脚本
├── docs/
│   ├── performance-guide.md        # 性能测试指南
│   └── tuning-playbook.md          # 调优手册
└── reports/
    └── template.md                 # 报告模板
```
