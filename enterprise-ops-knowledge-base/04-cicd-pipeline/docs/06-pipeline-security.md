# 流水线安全

## 1. 概述

CI/CD 流水线是软件供应链中的关键环节，也是攻击者的重要目标。本文系统性地介绍流水线安全的威胁模型、防护策略和最佳实践。

## 2. 威胁模型

### 2.1 OWASP CI/CD Top 10

| 排名 | 威胁 | 描述 |
|------|------|------|
| CICD-SEC-1 | 不充分的流水分隔 | 测试环境与生产环境未隔离 |
| CICD-SEC-2 | 不充分的访问控制 | CI/CD 系统权限过大 |
| CICD-SEC-3 | 依赖链攻击 | 恶意依赖注入 |
| CICD-SEC-4 | 流水线中的秘密泄露 | 凭据在日志中暴露 |
| CICD-SEC-5 | 不充分的PBAC | 构建环境权限过大 |
| CICD-SEC-6 | 不充分的凭据管理 | 硬编码凭据 |
| CICD-SEC-7 | 不完整的审计 | 缺少操作审计日志 |
| CICD-SEC-8 | Artifact 妥协 | 制品被篡改 |
| CICD-SEC-9 | 缺少认证 | API 端点未认证 |
| CICD-SEC-10 | 不安全的系统配置 | 默认配置未加固 |

### 2.2 攻击面分析

```
代码提交 → CI 触发 → 依赖下载 → 构建 → 测试 → 制品推送 → 部署
    ↑          ↑          ↑        ↑      ↑        ↑         ↑
  恶意代码   触发注入   供应链攻击  构建篡改 测试绕过  制品替换  部署劫持
```

## 3. 代码安全

### 3.1 分支保护

```yaml
# GitHub 分支保护规则
# Settings → Branches → Add rule
branches:
  - name: main
    protection:
      required_pull_request_reviews:
        required_approving_review_count: 2
        dismiss_stale_reviews: true
        require_code_owner_reviews: true
      required_status_checks:
        strict: true
        contexts:
          - "ci/build"
          - "ci/test"
          - "security/scan"
      enforce_admins: true
      required_linear_history: true
      allow_force_pushes: false
      allow_deletions: false
```

### 3.2 代码签名

```bash
# GPG 签名配置
git config --global user.signingkey <GPG_KEY_ID>
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# 验证签名
git log --show-signature
git verify-commit HEAD
```

### 3.3 预提交检查

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files

  - repo: https://github.com/bridgecrewio/checkov
    rev: v3.2.0
    hooks:
      - id: checkov
        args: [--framework, kubernetes]

  - repo: https://github.com/trufflesecurity/trufflehog
    rev: v3.63.0
    hooks:
      - id: trufflehog
```

## 4. 凭据管理

### 4.1 凭据分层策略

| 层级 | 工具 | 适用场景 |
|------|------|----------|
| 开发环境 | .env.local | 本地开发（不提交） |
| CI/CD | Vault/Secret Manager | 流水线运行时 |
| 运行时 | K8s Secrets/CSI | 应用运行时 |
| 长期存储 | HSM/KMS | 密钥加密存储 |

### 4.2 HashiCorp Vault 集成

```yaml
# Jenkins Pipeline + Vault
pipeline {
    agent any
    environment {
        VAULT_ADDR = 'https://vault.company.com'
    }
    stages {
        stage('Get Secrets') {
            steps {
                withVault([
                    configuration: [
                        vaultUrl: env.VAULT_ADDR,
                        vaultCredentialId: 'vault-token',
                        engineVersion: 2
                    ],
                    vaultSecrets: [
                        [
                            path: 'secret/data/myapp/production',
                            secretValues: [
                                [envVar: 'DB_PASSWORD', vaultKey: 'db_password'],
                                [envVar: 'API_KEY', vaultKey: 'api_key']
                            ]
                        ]
                    ]
                ]) {
                    sh 'echo "Secrets loaded securely"'
                    // 使用环境变量，不要 echo 密钥
                    sh 'make deploy'
                }
            }
        }
    }
}
```

### 4.3 AWS Secrets Manager 集成

```yaml
# GitHub Actions + AWS Secrets
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-southeast-1

      - name: Get secrets
        id: secrets
        run: |
          DB_PASSWORD=$(aws secretsmanager get-secret-value \
            --secret-id myapp/production/db \
            --query SecretString --output text | jq -r '.password')
          echo "::add-mask::$DB_PASSWORD"
          echo "db_password=$DB_PASSWORD" >> $GITHUB_OUTPUT
```

## 5. 供应链安全

### 5.1 依赖锁定

```json
// package-lock.json 或 pnpm-lock.yaml
// 始终提交 lock 文件
// 使用 npm ci 而非 npm install
{
  "scripts": {
    "ci": "npm ci --ignore-scripts",
    "postinstall": "node -e \"console.log('Dependencies installed')\""
  }
}
```

### 5.2 SBOM（软件物料清单）

```yaml
# 生成 SBOM
jobs:
  sbom:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate SBOM
        uses: anchore/sbom-action@v0
        with:
          image: myapp:${{ github.sha }}
          format: spdx-json
          output-file: sbom.spdx.json

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.spdx.json
```

### 5.3 容器镜像签名

```yaml
# 使用 Cosign 签名
jobs:
  sign:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - name: Install Cosign
        uses: sigstore/cosign-installer@v3

      - name: Sign image
        run: |
          cosign sign --yes \
            --oidc-issuer=https://token.actions.githubusercontent.com \
            ghcr.io/company/myapp@${{ steps.build.outputs.digest }}

      - name: Verify image
        run: |
          cosign verify \
            --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
            --certificate-identity-regexp="^https://github.com/company/" \
            ghcr.io/company/myapp:${{ github.sha }}
```

## 6. 运行时安全

### 6.1 构建环境隔离

```yaml
# 使用一次性容器执行构建
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: maven:3.9-eclipse-temurin-17
      options: --read-only  # 只读文件系统
    steps:
      - uses: actions/checkout@v4
      - run: mvn clean package
```

### 6.2 网络隔离

```yaml
# Jenkins K8s Agent 网络策略
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: jenkins-agent-policy
  namespace: jenkins
spec:
  podSelector:
    matchLabels:
      jenkins/agent: "true"
  policyTypes:
    - Ingress
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: jenkins
      ports:
        - port: 8080
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8
      ports:
        - port: 443
  ingress: []  # 禁止入站
```

## 7. 安全扫描集成

### 7.1 SAST（静态应用安全测试）

```yaml
# SonarQube 集成
jobs:
  sonarqube:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: SonarQube Scan
        uses: sonarqube-quality-gate-action@master
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        with:
          args: >
            -Dsonar.projectKey=myapp
            -Dsonar.sources=src
            -Dsonar.tests=test
            -Dsonar.qualitygate.wait=true
```

### 7.2 DAST（动态应用安全测试）

```yaml
jobs:
  dast:
    runs-on: ubuntu-latest
    needs: deploy-staging
    steps:
      - name: OWASP ZAP Scan
        uses: zaproxy/action-full-scan@v0.7.0
        with:
          target: 'https://staging.company.com'
          rules_file_name: '.zap/rules.tsv'
          cmd_options: '-a -j -l WARN'
```

### 7.3 容器扫描

```yaml
jobs:
  container-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Run Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'myapp:${{ github.sha }}'
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'

      - name: Upload to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-results.sarif'
```

## 8. 审计与合规

### 8.1 审计日志

```yaml
# Jenkins 审计插件配置
jenkins:
  auditTrail:
    plugin: "audit-trail"
    patterns:
      - ".*config.xml.*"
      - ".*credentials.*"
      - ".*script.*"
    loggers:
      - logFile:
          log: "/var/log/jenkins/audit.log"
          limit: 10
          size: 10MB
```

### 8.2 合规检查

```yaml
# 合规性流水线
jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - name: Check license compliance
        uses: fossa-contrib/fossa-action@v3
        with:
          api-key: ${{ secrets.FOSSA_API_KEY }}

      - name: Check secrets in code
        run: |
          trufflehog git file://. --only-verified --fail

      - name: Check IaC compliance
        run: |
          checkov -d . --framework kubernetes --compact
```

## 9. 应急响应

### 9.1 流水线被入侵的响应流程

1. **立即停止**：暂停所有流水线执行
2. **隔离**：撤销所有 CI/CD 相关凭据
3. **审计**：检查最近的构建日志和部署记录
4. **回滚**：回滚最近的部署到已知安全版本
5. **修复**：修复漏洞，更新凭据
6. **恢复**：逐步恢复流水线运行

### 9.2 自动化响应

```yaml
# 自动撤销泄露的凭据
jobs:
  rotate-secrets:
    if: github.event_name == 'security_advisory'
    runs-on: ubuntu-latest
    steps:
      - name: Rotate all CI secrets
        run: |
          # 轮换 AWS 密钥
          aws iam create-access-key --user-name ci-user
          aws iam delete-access-key --user-name ci-user --access-key-id $OLD_KEY
          # 轮换数据库密码
          # ...更多凭据轮换
```

## 10. 总结

流水线安全的核心原则：
1. **最小权限**：CI/CD 系统只获取必要的权限
2. **零信任**：不信任任何输入，验证所有依赖
3. **纵深防御**：多层安全检查，不依赖单一防线
4. **自动化**：安全检查自动化，减少人为疏忽
5. **可观测性**：完整的审计日志和监控告警
