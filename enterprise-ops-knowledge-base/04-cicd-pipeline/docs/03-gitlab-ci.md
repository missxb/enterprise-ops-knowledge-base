# GitLab CI/CD

## 1. 概述

GitLab CI/CD 是 GitLab 内置的持续集成/持续交付工具，与 GitLab 代码仓库深度集成。它使用 `.gitlab-ci.yml` 文件定义流水线，支持自动化的构建、测试和部署流程。

## 2. 核心概念

### 2.1 Pipeline（流水线）

Pipeline 是 GitLab CI/CD 的顶层概念，由多个 Stage 组成。每次代码推送或 Merge Request 都会触发一个 Pipeline。

### 2.2 Stage（阶段）

Stage 定义了 Pipeline 的执行顺序，同一 Stage 中的 Job 并行执行，不同 Stage 按顺序执行。

### 2.3 Job（任务）

Job 是 Pipeline 的最小执行单元，在 Runner 上执行具体的构建、测试或部署任务。

### 2.4 Runner（执行器）

Runner 是执行 Job 的代理，支持多种执行器类型：
- **Shell**：直接在 Runner 主机上执行
- **Docker**：在 Docker 容器中执行
- **Kubernetes**：在 K8s Pod 中执行
- **VirtualBox/Parallels**：在虚拟机中执行

## 3. 流水线配置详解

### 3.1 基础结构

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test
  - security
  - deploy

variables:
  DOCKER_TLS_CERTDIR: "/certs"

# 全局默认值
default:
  image: alpine:latest
  before_script:
    - echo "Pipeline started"
  retry:
    max: 2
    when:
      - runner_system_failure
      - stuck_or_timeout_failure
```

### 3.2 Job 配置

```yaml
build-app:
  stage: build
  image: maven:3.9-eclipse-temurin-17
  script:
    - mvn clean package -DskipTests
  artifacts:
    paths:
      - target/*.jar
    expire_in: 1 week
  cache:
    key: ${CI_COMMIT_REF_SLUG}
    paths:
      - .m2/repository/
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'
```

### 3.3 并行与矩阵构建

```yaml
# 并行测试
test:
  stage: test
  parallel: 3
  script:
    - npm run test -- --shard=$((CI_NODE_INDEX+1))/$CI_NODE_TOTAL

# 矩阵构建
build-matrix:
  stage: build
  parallel:
    matrix:
      - PLATFORM: [linux, darwin, windows]
        ARCH: [amd64, arm64]
  script:
    - GOOS=$PLATFORM GOARCH=$ARCH go build -o myapp-$PLATFORM-$ARCH
```

### 3.4 环境与部署

```yaml
deploy-staging:
  stage: deploy
  image: bitnami/kubectl:latest
  environment:
    name: staging
    url: https://staging.company.com
    on_stop: stop-staging
  script:
    - kubectl set image deployment/myapp myapp=myapp:$CI_COMMIT_SHA -n staging
    - kubectl rollout status deployment/myapp -n staging
  rules:
    - if: '$CI_COMMIT_BRANCH == "develop"'

deploy-production:
  stage: deploy
  image: bitnami/kubectl:latest
  environment:
    name: production
    url: https://www.company.com
  script:
    - kubectl set image deployment/myapp myapp=myapp:$CI_COMMIT_SHA -n production
    - kubectl rollout status deployment/myapp -n production
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      when: manual
  allow_failure: false
```

## 4. Runner 配置

### 4.1 Docker Runner 部署

```bash
# 安装 GitLab Runner
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner

# 注册 Runner
sudo gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.company.com/" \
  --registration-token "PROJECT_TOKEN" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --description "docker-runner-1" \
  --tag-list "docker,linux" \
  --run-untagged="true" \
  --locked="false" \
  --docker-privileged="false" \
  --docker-volumes "/cache" \
  --cache-dir "/cache"
```

### 4.2 K8s Runner 部署

```yaml
# values.yaml for gitlab-runner Helm chart
gitlabUrl: https://gitlab.company.com/
runnerRegistrationToken: "PROJECT_TOKEN"
concurrent: 10
runners:
  image: ubuntu:22.04
  tags: "kubernetes,linux"
  privileged: true
  namespace: gitlab-runner
  builds:
    cpuRequests: "500m"
    memoryRequests: "1Gi"
    cpuLimits: "2"
    memoryLimits: "4Gi"
  services:
    cpuRequests: "500m"
    memoryRequests: "1Gi"
  cache:
    cacheType: s3
    cachePath: "gitlab-runner"
    cacheShared: true
    s3ServerAddress: "minio.internal:9000"
    s3BucketName: "gitlab-runner-cache"
    s3CacheInsecure: false
```

## 5. 高级特性

### 5.1 动态子流水线

```yaml
# 父流水线
generate-child-pipeline:
  stage: build
  script:
    - python generate_pipeline.py > child-pipeline.yml
  artifacts:
    paths:
      - child-pipeline.yml

run-child-pipeline:
  stage: test
  trigger:
    include:
      - artifact: child-pipeline.yml
        job: generate-child-pipeline
    strategy: depend
```

### 5.2 DAG（有向无环图）

```yaml
# 使用 needs 定义 DAG 关系
build-frontend:
  stage: build
  script: npm run build

build-backend:
  stage: build
  script: mvn package

test-frontend:
  stage: test
  needs: ["build-frontend"]
  script: npm test

test-backend:
  stage: test
  needs: ["build-backend"]
  script: mvn test

deploy:
  stage: deploy
  needs: ["test-frontend", "test-backend"]
  script: ./deploy.sh
```

### 5.3 安全扫描集成

```yaml
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Dependency-Scanning.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml
  - template: Security/Container-Scanning.gitlab-ci.yml

sast:
  stage: security

dependency_scanning:
  stage: security

secret_detection:
  stage: security

container_scanning:
  stage: security
  variables:
    CS_IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
```

## 6. 最佳实践

### 6.1 模板化

```yaml
# .gitlab-ci/templates/.deploy-template.yml
.deploy_template:
  image: bitnami/kubectl:latest
  before_script:
    - kubectl config use-context $KUBE_CONTEXT
  script:
    - kubectl set image deployment/$APP_NAME $APP_NAME=$IMAGE_TAG -n $NAMESPACE
    - kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s

# 使用模板
include:
  - local: '.gitlab-ci/templates/.deploy-template.yml'

deploy-staging:
  extends: .deploy_template
  variables:
    NAMESPACE: staging
    KUBE_CONTEXT: staging-cluster
  rules:
    - if: '$CI_COMMIT_BRANCH == "develop"'
```

### 6.2 缓存优化

```yaml
# 全局缓存配置
default:
  cache:
    key:
      files:
        - package-lock.json
        - pom.xml
    paths:
      - node_modules/
      - .m2/repository/
    policy: pull-push

# Job 级别缓存
test:
  cache:
    policy: pull  # 测试阶段只读取缓存
  script:
    - npm test
```

### 6.3 Secret 管理

```yaml
# 使用 GitLab CI/CD Variables
# 设置方式：Settings → CI/CD → Variables
# 支持 Protected（仅保护分支可用）和 Masked（日志中隐藏）

deploy:
  script:
    - echo $DEPLOY_TOKEN | docker login -u deployer --password-stdin
    - kubectl create secret generic app-secrets \
        --from-literal=db-password=$DB_PASSWORD \
        --dry-run=client -o yaml | kubectl apply -f -
```

## 7. 监控与运维

### 7.1 Runner 监控

```yaml
# Prometheus 指标采集
# /etc/gitlab-runner/config.toml
[session_server]
  session_timeout = 1800

[metrics]
  address = "0.0.0.0:9252"
```

### 7.2 Pipeline 分析

GitLab 内置 Pipeline Analytics：
- Pipeline 成功率趋势
- 平均构建时间
- 失败原因统计
- Runner 使用率

## 8. 总结

GitLab CI/CD 的核心优势：
1. **一体化体验**：代码仓库、CI/CD、制品管理无缝集成
2. **声明式配置**：`.gitlab-ci.yml` 即流水线定义
3. **灵活的 Runner**：支持多种执行环境
4. **安全内置**：SAST/DAST/依赖扫描开箱即用
5. **Auto DevOps**：零配置自动化流水线
