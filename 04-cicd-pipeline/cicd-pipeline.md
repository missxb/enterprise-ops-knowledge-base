# CI/CD流水线建设完整手册

## 目录

- [1. 项目背景与架构设计](#1-项目背景与架构设计)
- [2. Jenkins Pipeline](#2-jenkins-pipeline)
- [3. GitLab CI/CD](#3-gitlab-cicd)
- [4. 制品管理](#4-制品管理)
- [5. 代码质量检测](#5-代码质量检测)
- [6. 自动化测试集成](#6-自动化测试集成)
- [7. 发布策略](#7-发布策略)
- [8. ArgoCD GitOps](#8-argocd-gitops)
- [9. 完整CI/CD示例](#9-完整cicd示例)
- [10. 故障排查与最佳实践](#10-故障排查与最佳实践)

---

## 1. 项目背景与架构设计

### 1.1 CI/CD流水线架构

```
┌──────────────────────────────────────────────────────────────────┐
│                        CI/CD 全流程                               │
│                                                                  │
│  代码提交    构建    测试    扫描    制品    部署    验证          │
│  ─────→ ────→ ────→ ────→ ────→ ────→ ────→                   │
│   Git   Build  Test  Scan  Push  Deploy Verify                  │
│                                                                  │
│  ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌───────────────────┐   │
│  │  Git    │ │ Jenkins │ │ SonarQube│ │ Harbor/Nexus      │   │
│  │  Server │ │ /GitLab │ │ /Trivy   │ │ (制品仓库)        │   │
│  └────┬────┘ └────┬────┘ └────┬─────┘ └────────┬──────────┘   │
│       │           │           │                 │               │
│  ┌────┴───────────┴───────────┴─────────────────┴───────────┐  │
│  │                    ArgoCD / Flux                          │  │
│  │                    (GitOps 部署)                          │  │
│  └──────────────────────────┬───────────────────────────────┘  │
│                             │                                   │
│  ┌──────────────────────────┴───────────────────────────────┐  │
│  │              Kubernetes Cluster                           │  │
│  │    dev → staging → production (渐进式发布)                │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### 1.2 流水线阶段说明

| 阶段 | 工具 | 目的 |
|------|------|------|
| 代码提交 | Git + Git Hooks | 代码规范检查 |
| 构建 | Maven/Gradle/npm/go build | 编译打包 |
| 单元测试 | JUnit/pytest/go test | 代码质量 |
| 代码扫描 | SonarQube | 静态分析 |
| 镜像构建 | Docker Build | 容器化 |
| 镜像扫描 | Trivy/Snyk | 安全漏洞 |
| 制品推送 | Harbor/Nexus | 版本管理 |
| 部署 | ArgoCD/Helm | 环境部署 |
| 集成测试 | Postman/k6/E2E | 验证功能 |

---

## 2. Jenkins Pipeline

### 2.1 Jenkins部署

```bash
#!/bin/bash
# deploy-jenkins.sh - Jenkins部署

# Docker方式部署
docker run -d \
    --name jenkins \
    --restart=unless-stopped \
    -p 8080:8080 \
    -p 50000:50000 \
    -v jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v $(which docker):/usr/bin/docker \
    --group-add $(stat -c '%g' /var/run/docker.sock) \
    jenkins/jenkins:lts-jdk17

# 初始化密码
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# 安装推荐插件后，安装以下额外插件:
# - Pipeline
# - Blue Ocean
# - Docker Pipeline
# - Git
# - SonarQube Scanner
# - Credentials Binding
# - Kubernetes
```

### 2.2 声明式Pipeline（Java项目）

```groovy
// Jenkinsfile - Java项目完整流水线
pipeline {
    agent {
        kubernetes {
            yaml '''
                apiVersion: v1
                kind: Pod
                spec:
                  containers:
                  - name: maven
                    image: maven:3.9-eclipse-temurin-17
                    command: ['sleep']
                    args: ['infinity']
                    volumeMounts:
                    - name: m2-cache
                      mountPath: /root/.m2
                  - name: docker
                    image: docker:24-dind
                    securityContext:
                      privileged: true
                    volumeMounts:
                    - name: docker-sock
                      mountPath: /var/run/docker.sock
                  volumes:
                  - name: m2-cache
                    persistentVolumeClaim:
                      claimName: maven-cache
                  - name: docker-sock
                    hostPath:
                      path: /var/run/docker.sock
            '''
        }
    }

    environment {
        HARBOR_URL = 'harbor.example.com'
        IMAGE_NAME = "${HARBOR_URL}/library/${JOB_NAME}"
        IMAGE_TAG = "${BUILD_NUMBER}-${GIT_COMMIT[0..7]}"
        SONAR_URL = 'http://sonarqube.example.com'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                container('maven') {
                    sh '''
                        mvn clean package -DskipTests -B \
                            -Dmaven.repo.local=/root/.m2/repository
                    '''
                }
            }
        }

        stage('Unit Test') {
            steps {
                container('maven') {
                    sh '''
                        mvn test -B \
                            -Dmaven.repo.local=/root/.m2/repository
                    '''
                }
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                    jacoco execPattern: 'target/jacoco.exec'
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                container('maven') {
                    withSonarQubeEnv('sonarqube') {
                        sh '''
                            mvn sonar:sonar \
                                -Dsonar.projectKey=${JOB_NAME} \
                                -Dsonar.projectName=${JOB_NAME} \
                                -Dsonar.java.binaries=target/classes \
                                -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
                        '''
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build Image') {
            steps {
                container('docker') {
                    sh """
                        docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('Image Scan') {
            steps {
                container('docker') {
                    sh """
                        docker run --rm \
                            -v /var/run/docker.sock:/var/run/docker.sock \
                            aquasec/trivy image \
                            --severity HIGH,CRITICAL \
                            --exit-code 0 \
                            ${IMAGE_NAME}:${IMAGE_TAG}
                    """
                }
            }
        }

        stage('Push Image') {
            steps {
                container('docker') {
                    withCredentials([usernamePassword(
                        credentialsId: 'harbor-creds',
                        usernameVariable: 'HARBOR_USER',
                        passwordVariable: 'HARBOR_PASS'
                    )]) {
                        sh """
                            docker login ${HARBOR_URL} -u ${HARBOR_USER} -p ${HARBOR_PASS}
                            docker push ${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${IMAGE_NAME}:latest
                        """
                    }
                }
            }
        }

        stage('Deploy Staging') {
            when { branch 'develop' }
            steps {
                sh """
                    helm upgrade --install ${JOB_NAME} ./helm/${JOB_NAME} \
                        --namespace staging \
                        --set image.repository=${IMAGE_NAME} \
                        --set image.tag=${IMAGE_TAG} \
                        --wait --timeout 5m
                """
            }
        }

        stage('Deploy Production') {
            when { branch 'main' }
            input {
                message "确认部署到生产环境?"
                ok "部署"
                submitter "admin,ops-team"
            }
            steps {
                sh """
                    helm upgrade --install ${JOB_NAME} ./helm/${JOB_NAME} \
                        --namespace production \
                        --set image.repository=${IMAGE_NAME} \
                        --set image.tag=${IMAGE_TAG} \
                        --wait --timeout 10m
                """
            }
        }
    }

    post {
        success {
            slackSend(
                channel: '#ci-cd',
                color: 'good',
                message: "✅ ${JOB_NAME} #${BUILD_NUMBER} 构建成功 - ${IMAGE_TAG}"
            )
        }
        failure {
            slackSend(
                channel: '#ci-cd',
                color: 'danger',
                message: "❌ ${JOB_NAME} #${BUILD_NUMBER} 构建失败"
            )
        }
        always {
            cleanWs()
        }
    }
}
```

### 2.3 共享库

```groovy
// vars/javaPipeline.groovy - 共享库
def call(Map config = [:]) {
    pipeline {
        agent { label 'kubernetes' }
        
        environment {
            APP_NAME = config.appName ?: env.JOB_NAME
            JAVA_VERSION = config.javaVersion ?: '17'
        }

        stages {
            stage('Build & Test') {
                steps {
                    script {
                        buildApp(config)
                    }
                }
            }
            stage('Quality') {
                steps {
                    script {
                        qualityCheck(config)
                    }
                }
            }
            stage('Docker') {
                steps {
                    script {
                        buildAndPushImage(config)
                    }
                }
            }
            stage('Deploy') {
                steps {
                    script {
                        deployToK8s(config)
                    }
                }
            }
        }
    }
}

def buildApp(config) {
    container('maven') {
        sh "mvn clean package -DskipTests -B"
    }
}

def qualityCheck(config) {
    container('maven') {
        withSonarQubeEnv('sonarqube') {
            sh "mvn sonar:sonar"
        }
    }
}

def buildAndPushImage(config) {
    def imageTag = "${config.registry}/${config.project ?: 'library'}/${env.APP_NAME}:${env.BUILD_NUMBER}"
    container('docker') {
        sh "docker build -t ${imageTag} ."
        withCredentials([usernamePassword(credentialsId: 'harbor', usernameVariable: 'U', passwordVariable: 'P')]) {
            sh "docker login ${config.registry} -u \$U -p \$P && docker push ${imageTag}"
        }
    }
    return imageTag
}

def deployToK8s(config) {
    def ns = env.BRANCH_NAME == 'main' ? 'production' : 'staging'
    sh """
        helm upgrade --install ${env.APP_NAME} ./helm \
            --namespace ${ns} \
            --set image.tag=${env.BUILD_NUMBER} \
            --wait
    """
}
```

---

## 3. GitLab CI/CD

### 3.1 完整.gitlab-ci.yml

```yaml
# .gitlab-ci.yml - 完整的Java项目CI/CD配置

variables:
  MAVEN_OPTS: "-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository"
  DOCKER_TLS_CERTDIR: ""
  IMAGE_TAG: "$CI_REGISTRY_IMAGE:$CI_PIPELINE_IID-$CI_COMMIT_SHORT_SHA"

stages:
  - build
  - test
  - scan
  - docker
  - deploy-staging
  - deploy-production

# 缓存Maven依赖
cache:
  key: ${CI_COMMIT_REF_SLUG}
  paths:
    - .m2/repository/

# ===== 构建 =====
build:
  stage: build
  image: maven:3.9-eclipse-temurin-17
  script:
    - mvn clean package -DskipTests -B
  artifacts:
    paths:
      - target/*.jar
    expire_in: 1 hour

# ===== 单元测试 =====
unit-test:
  stage: test
  image: maven:3.9-eclipse-temurin-17
  script:
    - mvn test -B
  artifacts:
    when: always
    reports:
      junit: target/surefire-reports/*.xml
    paths:
      - target/site/jacoco/
  coverage: '/Total.*?(\d+%)/'

# ===== SonarQube扫描 =====
sonarqube:
  stage: scan
  image: maven:3.9-eclipse-temurin-17
  script:
    - mvn sonar:sonar
        -Dsonar.host.url=$SONAR_URL
        -Dsonar.projectKey=$CI_PROJECT_PATH_SLUG
        -Dsonar.login=$SONAR_TOKEN
  allow_failure: true
  only:
    - develop
    - main

# ===== 镜像构建 =====
docker-build:
  stage: docker
  image: docker:24
  services:
    - docker:24-dind
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker build -t $IMAGE_TAG .
    - docker tag $IMAGE_TAG $CI_REGISTRY_IMAGE:latest
    - docker push $IMAGE_TAG
    - docker push $CI_REGISTRY_IMAGE:latest
  only:
    - develop
    - main

# ===== 镜像扫描 =====
trivy-scan:
  stage: scan
  image: aquasec/trivy:latest
  script:
    - trivy image --severity HIGH,CRITICAL --exit-code 0 $IMAGE_TAG
  needs:
    - docker-build

# ===== 部署Staging =====
deploy-staging:
  stage: deploy-staging
  image: bitnami/kubectl:latest
  script:
    - kubectl config use-context staging
    - |
      kubectl set image deployment/$CI_PROJECT_NAME \
        $CI_PROJECT_NAME=$IMAGE_TAG \
        -n staging
    - kubectl rollout status deployment/$CI_PROJECT_NAME -n staging --timeout=300s
  environment:
    name: staging
    url: https://staging.example.com
  only:
    - develop

# ===== 部署Production =====
deploy-production:
  stage: deploy-production
  image: bitnami/kubectl:latest
  script:
    - kubectl config use-context production
    - |
      kubectl set image deployment/$CI_PROJECT_NAME \
        $CI_PROJECT_NAME=$IMAGE_TAG \
        -n production
    - kubectl rollout status deployment/$CI_PROJECT_NAME -n production --timeout=600s
  environment:
    name: production
    url: https://app.example.com
  when: manual
  only:
    - main
```

---

## 4. 制品管理

### 4.1 Nexus配置

```bash
# Nexus Docker Compose
cat > docker-compose-nexus.yml << 'EOF'
version: '3.8'
services:
  nexus:
    image: sonatype/nexus3:latest
    container_name: nexus
    ports:
      - "8081:8081"
      - "8082:8082"  # Docker hosted repo
      - "8083:8083"  # Docker proxy repo
    volumes:
      - nexus-data:/nexus-data
    environment:
      INSTALL4J_ADD_VM_PARAMS: "-Xms2g -Xmx2g -XX:MaxDirectMemorySize=2g"
    restart: unless-stopped

volumes:
  nexus-data:
EOF

# Nexus仓库类型:
# - maven-central: 代理Maven中央仓库
# - maven-releases: 本地Release仓库
# - maven-snapshots: 本地Snapshot仓库
# - docker-hosted: Docker私有仓库
# - docker-proxy: Docker Hub代理
# - npm-proxy: npm代理
# - pypi-proxy: PyPI代理
```

### 4.2 制品版本策略

```bash
# 版本命名规范
# 语义化版本: MAJOR.MINOR.PATCH
# 示例: 1.0.0, 1.0.1, 1.1.0, 2.0.0

# CI构建版本: {semver}-{build_number}-{git_hash}
# 示例: 1.0.0-123-abc1234

# Docker镜像标签策略
# harbor.example.com/library/myapp:1.0.0          # Release
# harbor.example.com/library/myapp:1.0.0-123       # CI构建
# harbor.example.com/library/myapp:latest           # 最新稳定版
# harbor.example.com/library/myapp:develop          # 开发分支
# harbor.example.com/library/myapp:sha-abc1234      # Git Commit
```

---

## 5. 代码质量检测

### 5.1 SonarQube部署与集成

```bash
# SonarQube Docker Compose
cat > docker-compose-sonarqube.yml << 'EOF'
version: '3.8'
services:
  sonarqube:
    image: sonarqube:10-community
    container_name: sonarqube
    ports:
      - "9000:9000"
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://sonar-db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: sonar_pass
    volumes:
      - sonar-data:/opt/sonarqube/data
      - sonar-logs:/opt/sonarqube/logs
    depends_on:
      - sonar-db
    ulimits:
      nofile:
        soft: 131072
        hard: 131072
    sysctl:
      - vm.max_map_count=524288

  sonar-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: sonar
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: sonar_pass
    volumes:
      - sonar-db:/var/lib/postgresql/data

volumes:
  sonar-data:
  sonar-logs:
  sonar-db:
EOF

# Maven项目集成
# pom.xml添加插件:
# <plugin>
#   <groupId>org.sonarsource.scanner.maven</groupId>
#   <artifactId>sonar-maven-plugin</artifactId>
#   <version>3.10.0.2594</version>
# </plugin>

# 执行扫描
# mvn sonar:sonar -Dsonar.host.url=http://sonarqube:9000 -Dsonar.login=token
```

---

## 6. 自动化测试集成

### 6.1 测试分层策略

```yaml
# 测试分层
# L1: 单元测试 (Unit Tests) - 70%
#   - 快速，无外部依赖
#   - Maven: mvn test
#   - Python: pytest
#   - Go: go test ./...

# L2: 集成测试 (Integration Tests) - 20%
#   - 测试组件间交互
#   - 使用TestContainers
#   - 接口测试（Postman/Newman）

# L3: E2E测试 (End-to-End Tests) - 10%
#   - 全链路测试
#   - Cypress / Playwright / Selenium
#   - 性能测试（k6 / JMeter）

# Newman (Postman CLI) 集成测试
# docker run --rm -v $(pwd):/workspace postman/newman run collection.json -e environment.json

# k6 性能测试
# docker run --rm -v $(pwd):/scripts grafana/k6 run /scripts/load-test.js
```

---

## 7. 发布策略

### 7.1 蓝绿发布

```yaml
# blue-green-deploy.yaml
# 当前版本（蓝色）
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-blue
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
      - name: myapp
        image: harbor.example.com/library/myapp:v1.0.0
---
# 新版本（绿色）
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-green
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
      - name: myapp
        image: harbor.example.com/library/myapp:v2.0.0
---
# Service切换流量
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: production
spec:
  selector:
    app: myapp
    version: blue  # 切换到 green 即完成蓝绿发布
  ports:
  - port: 80
    targetPort: 8080
```

### 7.2 金丝雀发布

```yaml
# canary-deploy.yaml - 使用Istio实现金丝雀发布
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp
  namespace: production
spec:
  hosts:
  - myapp.example.com
  http:
  - route:
    - destination:
        host: myapp
        subset: stable
      weight: 90
    - destination:
        host: myapp
        subset: canary
      weight: 10
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: myapp
  namespace: production
spec:
  host: myapp
  subsets:
  - name: stable
    labels:
      version: v1.0.0
  - name: canary
    labels:
      version: v2.0.0
```

### 7.3 滚动更新

```yaml
# 滚动更新策略
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 6
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2        # 最多多出2个Pod
      maxUnavailable: 0  # 不允许不可用
  minReadySeconds: 30    # Pod就绪后等待30秒
  revisionHistoryLimit: 10
```

---

## 8. ArgoCD GitOps

### 8.1 ArgoCD部署

```bash
# 安装ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 获取初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 安装CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && mv argocd /usr/local/bin/

# 登录
argocd login argocd.example.com
argocd account update-password
```

### 8.2 Application配置

```yaml
# argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/k8s-manifests.git
    targetRevision: main
    path: apps/myapp/production
    helm:
      valueFiles:
        - values.yaml
        - values-production.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 8.3 GitOps工作流

```bash
# 1. 代码变更触发CI构建新镜像
# 2. CI更新Git仓库中的镜像版本
# 3. ArgoCD检测到Git变更，自动同步到K8s

# 示例：CI中更新镜像版本
# 使用yq或kustomize更新
kustomize edit set image myapp=harbor.example.com/library/myapp:${NEW_TAG}
git add kustomization.yaml
git commit -m "chore: update myapp to ${NEW_TAG}"
git push

# 或使用ArgoCD CLI
argocd app set myapp --parameter image.tag=${NEW_TAG}
argocd app sync myapp
```

---

## 9. 完整CI/CD示例

### 9.1 Python项目Pipeline

```yaml
# .gitlab-ci.yml - Python项目
variables:
  PIP_CACHE_DIR: "$CI_PROJECT_DIR/.cache/pip"

cache:
  paths:
    - .cache/pip/
    - venv/

stages:
  - lint
  - test
  - build
  - deploy

lint:
  stage: lint
  image: python:3.11-slim
  before_script:
    - pip install ruff mypy
  script:
    - ruff check .
    - mypy --ignore-missing-imports src/

test:
  stage: test
  image: python:3.11-slim
  services:
    - postgres:15-alpine
    - redis:7-alpine
  variables:
    POSTGRES_DB: test_db
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
    DATABASE_URL: "postgresql://test:test@postgres:5432/test_db"
    REDIS_URL: "redis://redis:6379/0"
  before_script:
    - pip install -r requirements.txt -r requirements-dev.txt
  script:
    - pytest --cov=src --cov-report=xml --cov-report=term tests/
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml

docker-build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  only:
    - main
```

### 9.2 Go项目Pipeline

```yaml
# .gitlab-ci.yml - Go项目
stages:
  - test
  - build
  - deploy

test:
  stage: test
  image: golang:1.21
  script:
    - go mod download
    - go vet ./...
    - golangci-lint run
    - go test -race -coverprofile=coverage.out ./...
    - go tool cover -func=coverage.out
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.out

build:
  stage: build
  image: golang:1.21
  script:
    - CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o app ./cmd/server
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  only:
    - main
```

---

## 10. 故障排查与最佳实践

### 10.1 常见CI/CD问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 构建超时 | 依赖下载慢 | 配置镜像源和缓存 |
| 测试不稳定 | 外部依赖不稳定 | Mock外部服务 |
| 镜像构建慢 | 每次全量构建 | 多阶段构建+缓存 |
| 部署失败 | K8s资源不足 | 检查资源配额 |
| 权限问题 | ServiceAccount权限 | 配置RBAC |
| 镜像漏洞 | 基础镜像老旧 | 定期更新基础镜像 |

### 10.2 CI/CD最佳实践

1. **流水线即代码** - Pipeline配置文件版本化
2. **快速反馈** - 单元测试 < 5分钟，整个流水线 < 15分钟
3. **并行执行** - 独立任务并行运行
4. **缓存优化** - Maven/npm/Docker层缓存
5. **制品不可变** - 同一镜像部署到所有环境
6. **环境一致性** - 使用容器化构建环境
7. **安全左移** - 在CI阶段集成安全扫描
8. **GitOps** - 以Git为唯一部署真相源
9. **自动回滚** - 部署失败自动回滚
10. **通知告警** - 构建失败即时通知

---

> 📅 最后更新: 2026-05-02
