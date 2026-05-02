# Jenkins 企业级部署

## 1. 概述

Jenkins 是最成熟的开源 CI/CD 工具之一，拥有超过 1800 个插件，几乎可以集成任何开发工具链。本文介绍 Jenkins 在企业环境中的架构设计、高可用部署、安全加固和性能优化。

## 2. 架构设计

### 2.1 分布式架构

```
┌─────────────────────────────────────────────┐
│                Jenkins Master                │
│  ┌─────────┐ ┌──────────┐ ┌──────────────┐ │
│  │ Web UI  │ │ REST API │ │ 调度引擎     │ │
│  └─────────┘ └──────────┘ └──────────────┘ │
└──────────────────┬──────────────────────────┘
                   │
        ┌──────────┼──────────┐
        │          │          │
   ┌────▼────┐ ┌──▼────┐ ┌──▼────┐
   │ Agent 1 │ │Agent 2│ │Agent 3│
   │(构建机) │ │(K8s Pod)│ │(Docker)│
   └─────────┘ └───────┘ └───────┘
```

### 2.2 Master 节点职责

Master 节点应**仅负责**：
- 调度构建任务
- 管理插件和配置
- 提供 Web UI 和 API
- 协调 Agent 节点

**绝不应该**在 Master 上执行构建任务。

### 2.3 Agent 类型

| 类型 | 适用场景 | 优势 | 劣势 |
|------|----------|------|------|
| 静态 Agent | 固定构建环境 | 稳定，性能好 | 资源利用率低 |
| Docker Agent | 容器化构建 | 环境隔离，按需创建 | Docker 网络复杂 |
| K8s Pod Agent | 云原生构建 | 弹性伸缩 | 配置复杂 |
| 云 Agent | 临时构建 | 按需付费 | 网络延迟 |

## 3. 安装与配置

### 3.1 系统要求

| 组件 | 最低配置 | 推荐配置 |
|------|----------|----------|
| Master CPU | 4 核 | 8 核 |
| Master 内存 | 8 GB | 16 GB |
| Master 磁盘 | 100 GB SSD | 500 GB SSD |
| Agent CPU | 2 核 | 4 核 |
| Agent 内存 | 4 GB | 8 GB |

### 3.2 高可用方案

#### 方案一：Jenkins + K8s

```yaml
# jenkins-values.yaml (Helm Chart)
controller:
  image: jenkins/jenkins:lts
  resources:
    requests:
      cpu: "2"
      memory: "4Gi"
    limits:
      cpu: "4"
      memory: "8Gi"
  installPlugins:
    - kubernetes:latest
    - workflow-aggregator:latest
    - git:latest
    - blueocean:latest
  JCasC:
    configScripts:
      kubernetes-config: |
        jenkins:
          clouds:
          - kubernetes:
              name: "kubernetes"
              serverUrl: "https://kubernetes.default"
              namespace: "jenkins"
              jenkinsUrl: "http://jenkins:8080"
              podLabels:
              - key: "jenkins/agent"
                value: "true"
              templates:
              - name: "default"
                label: "kubernetes"
                containers:
                - name: "jnlp"
                  image: "jenkins/inbound-agent:latest"
                  workingDir: "/home/jenkins/agent"
                  resourceRequestCpu: "500m"
                  resourceRequestMemory: "1Gi"

agent:
  enabled: true
  image: jenkins/inbound-agent
  tag: latest

persistence:
  enabled: true
  storageClass: "gp3"
  size: "100Gi"
```

#### 方案二：Jenkins 主备

```yaml
# 使用共享存储实现主备
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: jenkins-master
spec:
  replicas: 1  # 主备模式只运行一个活跃实例
  serviceName: jenkins
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      containers:
      - name: jenkins
        image: jenkins/jenkins:lts
        ports:
        - containerPort: 8080
        - containerPort: 50000
        volumeMounts:
        - name: jenkins-data
          mountPath: /var/jenkins_home
        livenessProbe:
          httpGet:
            path: /login
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /login
            port: 8080
          initialDelaySeconds: 20
          periodSeconds: 10
  volumeClaimTemplates:
  - metadata:
      name: jenkins-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: "gp3"
      resources:
        requests:
          storage: 100Gi
```

## 4. 安全加固

### 4.1 认证与授权

```groovy
// Jenkins CasC (Configuration as Code) 安全配置
jenkins:
  securityRealm:
    ldap:
      configurations:
      - server: "ldap://ldap.company.com"
        rootDN: "dc=company,dc=com"
        userSearchBase: "ou=users"
        userSearch: "uid={0}"
        groupSearchBase: "ou=groups"
  authorizationStrategy:
    roleBased:
      roles:
        global:
        - name: "admin"
          permissions:
          - "Overall/Administer"
          assignments:
          - "admin-group"
        - name: "developer"
          permissions:
          - "Overall/Read"
          - "Job/Build"
          - "Job/Read"
          assignments:
          - "dev-group"
```

### 4.2 凭据管理

```groovy
// 推荐使用 Jenkins Credentials 插件
// 避免在 Jenkinsfile 中硬编码凭据
pipeline {
    environment {
        // 从 Jenkins Credentials 获取
        DOCKER_CREDS = credentials('docker-registry-creds')
        AWS_ACCESS_KEY = credentials('aws-access-key')
    }
    stages {
        stage('Push Image') {
            steps {
                sh '''
                    echo $DOCKER_CREDS_PSW | docker login -u $DOCKER_CREDS_USR --password-stdin
                    docker push myapp:latest
                '''
            }
        }
    }
}
```

### 4.3 脚本安全

```groovy
// Jenkins Script Security 配置
// 禁用危险的脚本控制台访问
// 通过 Script Security 插件控制脚本签名

// 在 Jenkinsfile 中使用 approved 方法
@NonCPS
def parseJson(String json) {
    def slurper = new groovy.json.JsonSlurperClassic()
    return slurper.parseText(json)
}
```

## 5. 性能优化

### 5.1 JVM 调优

```bash
# Jenkins Master JVM 参数
JAVA_OPTS="-Xms4g -Xmx4g \
  -XX:+UseG1GC \
  -XX:+ParallelRefProcEnabled \
  -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+UseCGroupMemoryLimitForHeap \
  -Dhudson.model.DirectoryBrowserSupport.CSP= \
  -Djenkins.install.runSetupWizard=false"
```

### 5.2 构建缓存

```groovy
// 使用缓存加速构建
pipeline {
    agent {
        kubernetes {
            yaml '''
                spec:
                  containers:
                  - name: maven
                    image: maven:3.9-eclipse-temurin-17
                    volumeMounts:
                    - name: maven-cache
                      mountPath: /root/.m2/repository
                  volumes:
                  - name: maven-cache
                    persistentVolumeClaim:
                      claimName: maven-cache-pvc
            '''
        }
    }
    stages {
        stage('Build') {
            steps {
                sh 'mvn clean package -DskipTests'
            }
        }
    }
}
```

### 5.3 并行构建

```groovy
// 矩阵构建
pipeline {
    agent none
    stages {
        stage('Build Matrix') {
            matrix {
                axes {
                    axis {
                        name 'PLATFORM'
                        values 'linux', 'windows', 'macos'
                    }
                    axis {
                        name 'VERSION'
                        values '17', '21'
                    }
                }
                stages {
                    stage('Build') {
                        steps {
                            sh "make build PLATFORM=$PLATFORM VERSION=$VERSION"
                        }
                    }
                }
            }
        }
    }
}
```

## 6. 插件管理

### 6.1 必装插件清单

| 插件 | 用途 |
|------|------|
| Blue Ocean | 现代化 UI |
| Pipeline | 流水线支持 |
| Kubernetes | K8s 动态 Agent |
| Credentials Binding | 凭据注入 |
| Git | Git 集成 |
| Docker Pipeline | Docker 构建 |
| SonarQube Scanner | 代码质量 |
| Job DSL | 任务自动化 |
| Configuration as Code | 配置即代码 |
| Role-based Authorization | 角色授权 |

### 6.2 插件版本管理

```yaml
# plugins.txt - 固定版本，避免升级导致不兼容
kubernetes:4029.v5712230ccb_f8
workflow-aggregator:600.vb_57cdd26fdd7
git:5.2.2
blueocean:1.27.15
```

## 7. 监控与运维

### 7.1 Jenkins 指标采集

```yaml
# Prometheus 监控配置
- job_name: 'jenkins'
  metrics_path: '/prometheus'
  static_configs:
  - targets: ['jenkins:8080']
  relabel_configs:
  - source_labels: [__address__]
    target_label: instance
```

**关键监控指标：**
- `jenkins_queue_size_value`：队列长度
- `jenkins_node_count_value`：节点数量
- `jenkins_executor_count_value`：执行器数量
- `jenkins_job_count_value`：任务数量

### 7.2 备份策略

```bash
#!/bin/bash
# Jenkins 备份脚本
JENKINS_HOME="/var/jenkins_home"
BACKUP_DIR="/backup/jenkins"
DATE=$(date +%Y%m%d_%H%M%S)

# 备份关键目录
tar czf $BACKUP_DIR/jenkins_${DATE}.tar.gz \
  $JENKINS_HOME/config.xml \
  $JENKINS_HOME/credentials.xml \
  $JENKINS_HOME/secrets \
  $JENKINS_HOME/users \
  $JENKINS_HOME/jobs \
  $JENKINS_HOME/plugins

# 保留最近 30 天的备份
find $BACKUP_DIR -name "jenkins_*.tar.gz" -mtime +30 -delete
```

## 8. 迁移策略

### 8.1 从传统 Jenkins 迁移到 K8s

1. **评估阶段**：盘点现有 Job 和插件
2. **准备阶段**：搭建 K8s 集群和 Helm Chart
3. **迁移阶段**：逐个迁移 Job，使用 JCasC 管理配置
4. **验证阶段**：对比新旧环境的构建结果
5. **切换阶段**：DNS 切换，关闭旧实例

## 9. 总结

企业级 Jenkins 部署的核心要点：
1. **架构分离**：Master 只负责调度，构建在 Agent 上执行
2. **安全第一**：LDAP 集成、凭据管理、脚本安全
3. **配置即代码**：JCasC 管理所有配置
4. **弹性伸缩**：K8s 动态 Agent 按需分配
5. **持续运维**：监控、备份、版本管理
