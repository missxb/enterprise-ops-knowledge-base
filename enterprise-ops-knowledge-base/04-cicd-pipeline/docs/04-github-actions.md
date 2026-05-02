# GitHub Actions

## 1. 概述

GitHub Actions 是 GitHub 原生的 CI/CD 平台，允许在 GitHub 仓库中自动化构建、测试和部署流程。它使用 YAML 格式定义工作流，支持丰富的社区 Actions 生态。

## 2. 核心概念

### 2.1 Workflow（工作流）

Workflow 是一个自动化过程，定义在 `.github/workflows/` 目录下的 YAML 文件中。一个仓库可以有多个 Workflow。

### 2.2 Event（事件）

Event 触发 Workflow 执行的条件，如 `push`、`pull_request`、`schedule` 等。

### 2.3 Job（任务）

Job 是 Workflow 中的一组 Step，运行在同一个 Runner 上。多个 Job 默认并行执行。

### 2.4 Step（步骤）

Step 是 Job 中的单个任务，可以是 Action 或 Shell 命令。

### 2.5 Action

Action 是可复用的工作流单元，可以从 GitHub Marketplace 获取或自行开发。

## 3. 工作流配置详解

### 3.1 基础结构

```yaml
# .github/workflows/ci.yml
name: CI Pipeline
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  workflow_dispatch:  # 手动触发

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm run build
      - run: npm test
```

### 3.2 矩阵构建

```yaml
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        node-version: [18, 20, 22]
        exclude:
          - os: windows-latest
            node-version: 18
      fail-fast: false
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
      - run: npm ci
      - run: npm test
```

### 3.3 缓存策略

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # 方式一：使用 actions/cache
      - uses: actions/cache@v4
        with:
          path: |
            ~/.npm
            node_modules
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      # 方式二：setup-node 内置缓存
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - run: npm ci
```

### 3.4 Secrets 与环境变量

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production  # 绑定 GitHub Environment
    steps:
      - name: Deploy
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
        run: |
          aws eks update-kubeconfig --name prod-cluster
          kubectl set image deployment/myapp myapp=$IMAGE_TAG
```

## 4. 容器化构建

### 4.1 Docker 构建与推送

```yaml
name: Docker Build
on:
  push:
    tags: ['v*']

jobs:
  docker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### 4.2 多平台构建

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build multi-platform
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: myapp:latest
```

## 5. 部署工作流

### 5.1 Kubernetes 部署

```yaml
name: Deploy to K8s
on:
  workflow_run:
    workflows: ["CI Pipeline"]
    types: [completed]
    branches: [main]

jobs:
  deploy:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Setup kubectl
        uses: azure/setup-kubectl@v3

      - name: Configure kubeconfig
        run: |
          mkdir -p $HOME/.kube
          echo "${{ secrets.KUBECONFIG }}" | base64 -d > $HOME/.kube/config

      - name: Deploy with Helm
        run: |
          helm upgrade --install myapp ./charts/myapp \
            --namespace production \
            --set image.tag=${{ github.sha }} \
            --wait --timeout 300s

      - name: Verify deployment
        run: |
          kubectl rollout status deployment/myapp -n production --timeout=300s
          kubectl get pods -n production -l app=myapp
```

### 5.2 蓝绿部署

```yaml
name: Blue-Green Deploy
on:
  workflow_dispatch:
    inputs:
      target:
        description: 'Deploy target (blue/green)'
        required: true
        type: choice
        options:
          - blue
          - green

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to ${{ inputs.target }}
        run: |
          DEPLOY_ENV=${{ inputs.target }}
          # 部署到非活跃环境
          kubectl apply -f k8s/${DEPLOY_ENV}/
          kubectl rollout status deployment/myapp-${DEPLOY_ENV}

          # 切换 Service 指向
          kubectl patch service myapp -p '{"spec":{"selector":{"version":"${DEPLOY_ENV}"}}}'

          # 验证新版本
          curl -f https://app.company.com/health || {
            echo "Health check failed, rolling back"
            kubectl patch service myapp -p '{"spec":{"selector":{"version":"$([ "$DEPLOY_ENV" = "blue" ] && echo "green" || echo "blue")"}}}'
            exit 1
          }
```

## 6. 自定义 Action 开发

### 6.1 JavaScript Action

```yaml
# action.yml
name: 'Custom Deploy Action'
description: 'Deploy application to K8s'
inputs:
  namespace:
    description: 'K8s namespace'
    required: true
  image-tag:
    description: 'Docker image tag'
    required: true
outputs:
  deployment-url:
    description: 'Deployment URL'
runs:
  using: 'node20'
  main: 'dist/index.js'
```

```javascript
// index.js
const core = require('@actions/core');
const k8s = require('@kubernetes/client-node');

async function run() {
  try {
    const namespace = core.getInput('namespace');
    const imageTag = core.getInput('image-tag');

    const kc = new k8s.KubeConfig();
    kc.loadFromDefault();
    const k8sApi = kc.makeApiClient(k8s.AppsV1Api);

    // 更新 Deployment
    const deployment = await k8sApi.readNamespacedDeployment('myapp', namespace);
    deployment.body.spec.template.spec.containers[0].image = `myapp:${imageTag}`;
    await k8sApi.replaceNamespacedDeployment('myapp', namespace, deployment.body);

    core.setOutput('deployment-url', `https://${namespace}.company.com`);
  } catch (error) {
    core.setFailed(error.message);
  }
}

run();
```

### 6.2 Composite Action

```yaml
# .github/actions/deploy-k8s/action.yml
name: 'Deploy to Kubernetes'
description: 'Deploy application using kubectl'
inputs:
  namespace:
    description: 'Target namespace'
    required: true
  image:
    description: 'Docker image'
    required: true
runs:
  using: 'composite'
  steps:
    - name: Deploy
      shell: bash
      run: |
        kubectl set image deployment/myapp myapp=${{ inputs.image }} -n ${{ inputs.namespace }}
        kubectl rollout status deployment/myapp -n ${{ inputs.namespace }} --timeout=300s
    - name: Verify
      shell: bash
      run: |
        kubectl get pods -n ${{ inputs.namespace }} -l app=myapp
```

## 7. 安全最佳实践

### 7.1 最小权限原则

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read        # 只读代码
      packages: write       # 推送镜像
      id-token: write       # OIDC 身份验证
    steps:
      - uses: actions/checkout@v4
```

### 7.2 使用 OIDC 避免长期凭据

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions
          aws-region: ap-southeast-1

      - name: Deploy
        run: |
          aws eks update-kubeconfig --name prod-cluster
          kubectl set image deployment/myapp myapp=$IMAGE_TAG
```

### 7.3 依赖安全

```yaml
# 锁定 Action 版本（使用 SHA）
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

# 使用 Dependabot 自动更新
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

## 8. Self-hosted Runner

### 8.1 部署 Self-hosted Runner

```yaml
# K8s 部署 self-hosted runner
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: github-runner
  namespace: github-runners
spec:
  replicas: 3
  template:
    spec:
      organization: your-org
      labels:
        - self-hosted
        - linux
        - x64
      resources:
        requests:
          cpu: "1"
          memory: "2Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
      dockerVolumeMounts:
        - name: docker-cache
          mountPath: /var/lib/docker
```

### 8.2 Runner 自动伸缩

```yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: github-runner-autoscaler
spec:
  scaleTargetRef:
    kind: RunnerDeployment
    name: github-runner
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: PercentageRunnersBusy
      scaleUpThreshold: '0.75'
      scaleDownThreshold: '0.25'
      scaleUpFactor: '2'
      scaleDownFactor: '0.5'
```

## 9. 总结

GitHub Actions 的核心优势：
1. **原生集成**：与 GitHub 仓库无缝协作
2. **社区生态**：Marketplace 提供数千个现成 Action
3. **灵活配置**：支持多种触发方式和矩阵构建
4. **安全模型**：OIDC、Environment Protection Rules
5. **可扩展性**：支持自定义 Action 和 Self-hosted Runner
