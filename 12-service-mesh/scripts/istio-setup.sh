#!/bin/bash
#=============================================================================
# Istio Service Mesh 安装与配置脚本
# 用途: 安装 Istio、配置流量管理、安全策略、可观测性
#=============================================================================

set -euo pipefail

ISTIO_VERSION="${ISTIO_VERSION:-1.20.2}"
NAMESPACE="${NAMESPACE:-istio-system}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*"; }

#--- 安装 Istio ---
install_istio() {
    log_info "安装 Istio ${ISTIO_VERSION}..."

    # 下载 istioctl
    if ! command -v istioctl &>/dev/null; then
        curl -fsSL "https://istio.io/downloadIstio" | ISTIO_VERSION=${ISTIO_VERSION} sh -
        cp "istio-${ISTIO_VERSION}/bin/istioctl" /usr/local/bin/
    fi

    # 使用生产配置安装
    istioctl install --set profile=default \
        --set meshConfig.accessLogFile=/dev/stdout \
        --set meshConfig.enableAutoMtls=true \
        --set values.global.proxy.resources.requests.cpu=100m \
        --set values.global.proxy.resources.requests.memory=128Mi \
        -y

    # 验证安装
    kubectl -n ${NAMESPACE} get pods
    istioctl verify-install

    log_info "Istio 安装完成"
}

#--- 部署示例应用 ---
deploy_sample_app() {
    local ns="production"
    kubectl create namespace ${ns} --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace ${ns} istio-injection=enabled --overwrite

    # 部署多版本应用
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-stable
  namespace: ${ns}
  labels:
    app: app-service
    version: stable
spec:
  replicas: 3
  selector:
    matchLabels:
      app: app-service
      version: stable
  template:
    metadata:
      labels:
        app: app-service
        version: stable
    spec:
      serviceAccountName: app-service
      containers:
        - name: app
          image: nginx:1.25
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 20
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-canary
  namespace: ${ns}
  labels:
    app: app-service
    version: canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-service
      version: canary
  template:
    metadata:
      labels:
        app: app-service
        version: canary
    spec:
      serviceAccountName: app-service
      containers:
        - name: app
          image: nginx:1.26
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: app-service
  namespace: ${ns}
spec:
  selector:
    app: app-service
  ports:
    - port: 8080
      targetPort: 8080
      name: http
EOF

    log_info "示例应用部署完成"
}

#--- 配置可观测性 ---
setup_observability() {
    log_info "配置可观测性组件..."

    # Kiali (服务拓扑)
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml 2>/dev/null || true

    # Jaeger (分布式追踪)
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml 2>/dev/null || true

    # Prometheus
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml 2>/dev/null || true

    # Grafana
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml 2>/dev/null || true

    log_info "可观测性组件部署完成"
    log_info "访问 Kiali: istioctl dashboard kiali"
    log_info "访问 Jaeger: istioctl dashboard jaeger"
}

#--- 金丝雀发布 ---
canary_deploy() {
    local weight="${1:-10}"
    log_info "配置金丝雀发布, canary 权重: ${weight}%"

    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: app-canary
  namespace: production
spec:
  hosts:
    - app-service
  http:
    - route:
        - destination:
            host: app-service
            subset: stable
          weight: $((100 - weight))
        - destination:
            host: app-service
            subset: canary
          weight: ${weight}
EOF

    log_info "金丝雀流量已调整: stable=$((100-weight))%, canary=${weight}%"
}

#--- 健康检查 ---
health_check() {
    log_info "Istio 健康检查..."
    echo ""

    echo "=== 控制平面 ==="
    kubectl -n ${NAMESPACE} get pods
    echo ""

    echo "=== 数据平面 ==="
    istioctl proxy-status
    echo ""

    echo "=== 服务网格 ==="
    kubectl -n production get virtualservices,destinationrules,peerauthentication 2>/dev/null || echo "暂无配置"
    echo ""

    # 分析配置
    istioctl analyze --namespace production 2>/dev/null || true
}

#--- 帮助 ---
usage() {
    cat <<EOF
Istio Service Mesh 管理脚本

用法: $0 <command> [options]

命令:
  install                  安装 Istio
  sample-app              部署示例多版本应用
  observability           部署可观测性组件 (Kiali/Jaeger/Grafana)
  canary <weight>         配置金丝雀发布权重 (0-100)
  health                  健康检查

示例:
  $0 install
  $0 sample-app
  $0 canary 20
  $0 health
EOF
}

main() {
    local cmd="${1:-help}"
    shift || true

    case "${cmd}" in
        install)       install_istio ;;
        sample-app)    deploy_sample_app ;;
        observability) setup_observability ;;
        canary)        canary_deploy "${1:-10}" ;;
        health)        health_check ;;
        help|*)        usage ;;
    esac
}

main "$@"
