#!/bin/bash
#=============================================================================
# 内部开发者平台 (IDP) 快速部署脚本
# 组件: Backstage + ArgoCD + Harbor + Keycloak
#=============================================================================

set -euo pipefail

NAMESPACE="${NAMESPACE:-platform}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log_info()  { echo -e "\033[0;32m[INFO]\033[0m  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $(date '+%H:%M:%S') $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $(date '+%H:%M:%S') $*"; }

#--- 部署 Backstage ---
deploy_backstage() {
    log_info "部署 Backstage 开发者门户..."

    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # Helm 安装
    helm repo add backstage https://backstage.github.io/charts 2>/dev/null || true
    helm repo update

    cat > /tmp/backstage-values.yaml <<'EOF'
appConfig:
  app:
    title: Internal Developer Portal
    baseUrl: https://backstage.example.com
  backend:
    baseUrl: https://backstage.example.com
    cors:
      origin: https://backstage.example.com
  integrations:
    github:
      - host: github.com
        token: ${GITHUB_TOKEN}
  auth:
    providers:
      github:
        development:
          clientId: ${GITHUB_CLIENT_ID}
          clientSecret: ${GITHUB_CLIENT_SECRET}
  catalog:
    locations:
      - type: github
        target: https://github.com/company/backstage-catalog/blob/main/catalog-info.yaml
        rules:
          - allow: [Component, System, API, Resource, Location]
      - type: github-discovery
        target: https://github.com/company/*
        rules:
          - allow: [Component, System, API]

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: backstage.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: backstage-tls
      hosts:
        - backstage.example.com

resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi

postgresql:
  enabled: true
  primary:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
EOF

    helm upgrade --install backstage backstage/backstage \
        --namespace ${NAMESPACE} \
        --values /tmp/backstage-values.yaml \
        --wait --timeout 10m

    log_info "Backstage 部署完成"
}

#--- 部署 Harbor ---
deploy_harbor() {
    log_info "部署 Harbor 镜像仓库..."

    helm repo add harbor https://helm.goharbor.io 2>/dev/null || true
    helm repo update

    helm upgrade --install harbor harbor/harbor \
        --namespace harbor \
        --create-namespace \
        --set expose.type=ingress \
        --set expose.ingress.hosts.core=harbor.example.com \
        --set expose.ingress.hosts.notary=notary.example.com \
        --set expose.tls.secretName=harbor-tls \
        --set harborAdminPassword=Harbor12345 \
        --set persistence.enabled=true \
        --set persistence.persistentVolumeClaim.registry.size=100Gi \
        --set persistence.persistentVolumeClaim.database.size=10Gi \
        --set persistence.persistentVolumeClaim.redis.size=5Gi \
        --set persistence.persistentVolumeClaim.jobservice.size=5Gi \
        --set externalURL=https://harbor.example.com \
        --set metrics.enabled=true \
        --set metrics.serviceMonitor.enabled=true \
        --wait --timeout 15m

    log_info "Harbor 部署完成: https://harbor.example.com"
}

#--- 部署 Keycloak (SSO) ---
deploy_keycloak() {
    log_info "部署 Keycloak SSO..."

    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo update

    helm upgrade --install keycloak bitnami/keycloak \
        --namespace sso \
        --create-namespace \
        --set auth.adminUser=admin \
        --set auth.adminPassword=admin123 \
        --set proxy=edge \
        --set ingress.enabled=true \
        --set ingress.hostname=sso.example.com \
        --set ingress.tls=true \
        --set resources.requests.cpu=200m \
        --set resources.requests.memory=512Mi \
        --set resources.limits.cpu=1000m \
        --set resources.limits.memory=2Gi \
        --set postgresql.enabled=true \
        --wait --timeout 10m

    log_info "Keycloak 部署完成: https://sso.example.com"
}

#--- 帮助 ---
usage() {
    cat <<EOF
内部开发者平台 (IDP) 部署脚本

用法: $0 <command>

命令:
  backstage     部署 Backstage 开发者门户
  harbor        部署 Harbor 镜像仓库
  keycloak      部署 Keycloak SSO
  all           部署全部组件

示例:
  $0 all
  $0 backstage
  $0 harbor
EOF
}

main() {
    local cmd="${1:-help}"
    shift || true

    case "${cmd}" in
        backstage) deploy_backstage ;;
        harbor)    deploy_harbor ;;
        keycloak)  deploy_keycloak ;;
        all)
            deploy_keycloak
            deploy_harbor
            deploy_backstage
            ;;
        help|*)    usage ;;
    esac
}

main "$@"
