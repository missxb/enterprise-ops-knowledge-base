# CI/CD 原则与实践

## 1. 概述

持续集成（Continuous Integration, CI）和持续交付/部署（Continuous Delivery/Deployment, CD）是现代软件开发的基石。本文系统性地阐述 CI/CD 的核心原则、实践方法和常见陷阱，为后续的技术选型和流水线设计提供理论基础。

## 2. 持续集成（CI）

### 2.1 定义与核心思想

持续集成是一种开发实践：团队成员频繁地（通常每天至少一次）将代码集成到共享的主干分支中。每次集成都通过自动化的构建和测试来验证，从而尽早发现集成错误。

**Martin Fowler 的 CI 三原则：**
1. 维护一个单一的代码仓库（Single Source of Truth）
2. 自动化构建（Automated Build）
3. 自动化测试（Automated Testing）

### 2.2 CI 的核心实践

#### 2.2.1 频繁提交

开发人员应每天至少提交一次代码到主干分支。频繁提交的好处：
- 减少合并冲突的规模和复杂度
- 加快反馈循环，问题更容易定位
- 促进小步快跑的开发节奏

**实际建议：**
- 每个功能点完成后立即提交
- 使用特性开关（Feature Toggle）控制未完成功能的可见性
- 提交前先拉取最新代码并本地验证

#### 2.2.2 自动化构建

构建过程应完全自动化，包括：
- 代码编译
- 依赖解析
- 资源打包
- 容器镜像构建

```bash
# 典型的 CI 构建流程
git pull origin main
mvn clean package -DskipTests    # Java 项目
docker build -t myapp:${BUILD_NUMBER} .  # 容器化
```

#### 2.2.3 自动化测试金字塔

```
        /  E2E  \          少量，慢，昂贵
       / 集成测试 \         适量，中速
      /  单元测试   \       大量，快速，便宜
```

| 测试层级 | 占比 | 执行时间 | 覆盖目标 |
|----------|------|----------|----------|
| 单元测试 | 70% | < 1 分钟 | 函数/方法级别 |
| 集成测试 | 20% | 1-5 分钟 | 模块/服务间交互 |
| E2E 测试 | 10% | 5-30 分钟 | 用户场景验证 |

#### 2.2.4 构建必须快速

**黄金法则：** CI 构建应在 10 分钟内完成。

优化策略：
1. **并行化测试**：按模块或测试类型分组并行执行
2. **增量构建**：只构建变更的模块
3. **缓存依赖**：使用本地 Maven/npm 镜像或缓存层
4. **分层构建**：快速反馈层（编译+单元测试）先行，慢速测试异步执行

```groovy
// Jenkins Pipeline - 并行测试示例
parallel(
    "Unit Tests": {
        sh 'mvn test -pl module-a'
    },
    "Integration Tests": {
        sh 'mvn verify -pl module-b -P integration'
    },
    "Security Scan": {
        sh 'trivy image myapp:latest'
    }
)
```

### 2.3 CI 反模式

| 反模式 | 表现 | 危害 |
|--------|------|------|
| 长生命周期分支 | feature 分支存在数周 | 合并地狱，代码冲突 |
| 构建红灯不管 | 红灯持续数小时甚至数天 | 团队失去对构建状态的信任 |
| 手动测试依赖 | 必须人工验证才能合并 | 反馈延迟，阻塞流程 |
| 缺少代码审查 | 直接推送到主干 | 代码质量下降 |

## 3. 持续交付（CD）

### 3.1 持续交付 vs 持续部署

| 特性 | 持续交付 | 持续部署 |
|------|----------|----------|
| 定义 | 代码随时可以部署到生产 | 每次变更自动部署到生产 |
| 人工审批 | 需要手动触发部署 | 无需人工干预 |
| 适用场景 | 合规要求严格的场景 | 成熟的自动化体系 |
| 风险等级 | 较低 | 需要强大的自动化保障 |

### 3.2 部署流水线设计

一个完整的部署流水线通常包含以下阶段：

```
提交阶段（Commit Stage）
├── 代码编译
├── 单元测试
├── 静态代码分析（SonarQube）
└── 构建制品

验收阶段（Acceptance Stage）
├── 部署到测试环境
├── 自动化验收测试
├── API 契约测试
└── 性能基准测试

预发布阶段（Pre-production Stage）
├── 部署到预发布环境
├── 集成测试
├── 安全扫描（SAST/DAST）
└── 数据库迁移验证

生产阶段（Production Stage）
├── 蓝绿/金丝雀部署
├── 冒烟测试
├── 监控指标验证
└── 自动回滚机制
```

### 3.3 不可变制品原则

**核心思想：** 一次构建，多环境部署。不同环境之间只通过配置（环境变量、配置文件）区分，而非重新构建。

```dockerfile
# 构建阶段
FROM maven:3.9-eclipse-temurin-17 AS builder
COPY . /app
WORKDIR /app
RUN mvn clean package -DskipTests

# 运行阶段 - 制品不可变
FROM eclipse-temurin:17-jre-alpine
COPY --from=builder /app/target/app.jar /app.jar
# 配置通过环境变量注入
ENV JAVA_OPTS=""
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app.jar"]
```

**环境差异化配置：**
```yaml
# docker-compose.staging.yml
services:
  app:
    image: myapp:${BUILD_NUMBER}
    environment:
      - SPRING_PROFILES_ACTIVE=staging
      - DB_HOST=staging-db.internal

# docker-compose.production.yml
services:
  app:
    image: myapp:${BUILD_NUMBER}  # 同一个镜像
    environment:
      - SPRING_PROFILES_ACTIVE=production
      - DB_HOST=prod-db.internal
```

## 4. 流水线即代码（Pipeline as Code）

### 4.1 原则

流水线的定义应该和应用程序代码一起存放在版本控制系统中，享受同样的版本管理、代码审查和变更追踪。

**核心优势：**
- 流水线变更可追溯、可审计
- 支持代码审查流程
- 易于复制和模板化
- 环境一致性保障

### 4.2 声明式 vs 脚本式

| 特性 | 声明式（Declarative） | 脚本式（Scripted） |
|------|----------------------|-------------------|
| 可读性 | 高，结构化语法 | 低，类似编程 |
| 学习曲线 | 低 | 高 |
| 灵活性 | 中等 | 极高 |
| 错误处理 | 内置支持 | 需手动编写 |
| 推荐场景 | 标准化流水线 | 复杂定制需求 |

### 4.3 流水线设计模式

#### 4.3.1 多分支流水线

自动为每个分支/PR 创建独立的流水线运行。

```groovy
// Jenkinsfile - 多分支流水线
pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                sh 'make build'
            }
        }
        stage('Test') {
            parallel {
                stage('Unit') { steps { sh 'make test-unit' } }
                stage('Integration') { steps { sh 'make test-integration' } }
            }
        }
        stage('Deploy') {
            when { branch 'main' }
            steps {
                sh 'make deploy-prod'
            }
        }
    }
}
```

#### 4.3.2 流水线模板化

```yaml
# GitLab CI - 模板化
.deploy_template: &deploy_template
  image: alpine/helm
  script:
    - helm upgrade --install $APP_NAME ./charts/$APP_NAME
      --namespace $NAMESPACE
      --set image.tag=$CI_COMMIT_SHA
  environment:
    name: $ENV_NAME

deploy_staging:
  <<: *deploy_template
  variables:
    ENV_NAME: staging
    NAMESPACE: staging
  only:
    - develop

deploy_production:
  <<: *deploy_template
  variables:
    ENV_NAME: production
    NAMESPACE: production
  only:
    - main
  when: manual
```

## 5. 反馈与可观测性

### 5.1 快速反馈机制

1. **本地预提交检查**：在代码提交前运行 lint 和格式化
2. **CI 快速阶段**：编译和单元测试应在 2 分钟内完成
3. **增量测试**：只运行受变更影响的测试
4. **通知机制**：构建失败时立即通知相关人员

### 5.2 流水线指标

| 指标 | 定义 | 目标值 |
|------|------|--------|
| 变更前置时间 | 从提交到生产的时间 | < 1 天 |
| 部署频率 | 单位时间内部署次数 | 每天多次 |
| 变更失败率 | 导致故障的部署占比 | < 5% |
| 恢复时间 | 从故障到恢复的时间 | < 1 小时 |

### 5.3 构建状态可视化

```yaml
# 构建状态看板集成
notifications:
  slack:
    channel: "#ci-cd-status"
    on_success: change
    on_failure: always
  email:
    recipients: ["team@company.com"]
    on_failure: always
```

## 6. 文化与组织

### 6.1 DevOps 文化要素

CI/CD 不仅仅是工具链，更是文化转变：

1. **共享责任**：开发和运维共同对交付负责
2. **自动化优先**：能自动化的绝不手动
3. **持续改进**：定期回顾和优化流水线
4. **透明度**：构建状态和部署信息对全团队可见

### 6.2 团队协作模式

- **Trunk-Based Development**：基于主干的开发模式
- **Feature Flags**：特性开关控制功能发布
- **Shift-Left Testing**：测试左移，尽早发现问题
- **ChatOps**：通过聊天工具进行运维操作

## 7. 总结

CI/CD 是一个循序渐进的过程：

1. **第一步**：实现基本的自动化构建和测试
2. **第二步**：建立完整的部署流水线
3. **第三步**：引入安全扫描和质量门禁
4. **第四步**：实现自动化部署和回滚
5. **第五步**：建立度量体系，持续优化

关键不在于追求完美的工具链，而在于建立持续改进的文化和流程。
