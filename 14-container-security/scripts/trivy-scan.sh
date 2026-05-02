#!/bin/bash
#=============================================================================
# Trivy 容器镜像安全扫描脚本
# 用途: CI/CD 集成镜像扫描、漏洞报告、合规检查
#=============================================================================

set -euo pipefail

TRIVY_VERSION="${TRIVY_VERSION:-0.48.3}"
REPORT_DIR="${REPORT_DIR:-./scan-reports}"
SEVERITY="${SEVERITY:-CRITICAL,HIGH}"
EXIT_CODE="${EXIT_CODE:-1}"
IGNORE_UNFIXED="${IGNORE_UNFIXED:-true}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

#--- 安装 Trivy ---
install_trivy() {
    log_info "安装 Trivy ${TRIVY_VERSION}..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq wget apt-transport-https gnupg lsb-release
        wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg
        echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/trivy.list
        apt-get update -qq && apt-get install -y -qq trivy
    elif command -v yum &>/dev/null; then
        cat > /etc/yum.repos.d/trivy.repo <<EOF
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/deb/public.key
EOF
        yum install -y trivy
    else
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v${TRIVY_VERSION}
    fi
    log_info "Trivy 安装完成: $(trivy --version)"
}

#--- 扫描镜像 ---
scan_image() {
    local image="$1"
    local report_name="${image//\//-}"
    report_name="${report_name//:/-}"
    mkdir -p "${REPORT_DIR}"

    log_info "扫描镜像: ${image}"
    log_info "严重级别: ${SEVERITY}"

    # JSON 报告 (机器可读)
    trivy image \
        --severity "${SEVERITY}" \
        --format json \
        --output "${REPORT_DIR}/${report_name}.json" \
        ${IGNORE_UNFIXED:+--ignore-unfixed} \
        "${image}" 2>/dev/null

    # 表格报告 (人类可读)
    trivy image \
        --severity "${SEVERITY}" \
        --format table \
        --output "${REPORT_DIR}/${report_name}.txt" \
        ${IGNORE_UNFIXED:+--ignore-unfixed} \
        "${image}" 2>/dev/null

    # SARIF 报告 (GitHub Security)
    trivy image \
        --severity "${SEVERITY}" \
        --format sarif \
        --output "${REPORT_DIR}/${report_name}.sarif" \
        ${IGNORE_UNFIXED:+--ignore-unfixed} \
        "${image}" 2>/dev/null || true

    # 统计漏洞数量
    local critical=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "${REPORT_DIR}/${report_name}.json" 2>/dev/null || echo 0)
    local high=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "${REPORT_DIR}/${report_name}.json" 2>/dev/null || echo 0)
    local medium=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM")] | length' "${REPORT_DIR}/${report_name}.json" 2>/dev/null || echo 0)

    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║         镜像安全扫描报告                  ║"
    echo "╠══════════════════════════════════════════╣"
    printf "║  镜像:     %-30s║\n" "${image}"
    printf "║  CRITICAL: %-30s║\n" "${critical}"
    printf "║  HIGH:     %-30s║\n" "${high}"
    printf "║  MEDIUM:   %-30s║\n" "${medium}"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    # 报告路径
    log_info "报告已保存:"
    log_info "  JSON:  ${REPORT_DIR}/${report_name}.json"
    log_info "  Table: ${REPORT_DIR}/${report_name}.txt"
    log_info "  SARIF: ${REPORT_DIR}/${report_name}.sarif"

    # 判断是否通过
    if [[ ${critical} -gt 0 ]]; then
        log_error "❌ 发现 ${critical} 个 CRITICAL 漏洞, 镜像不安全!"
        return ${EXIT_CODE}
    elif [[ ${high} -gt 0 ]]; then
        log_warn "⚠️  发现 ${high} 个 HIGH 漏洞, 建议修复"
        return 0
    else
        log_info "✅ 镜像安全检查通过"
        return 0
    fi
}

#--- 扫描文件系统 ---
scan_fs() {
    local path="$1"
    log_info "扫描文件系统: ${path}"

    trivy fs \
        --severity "${SEVERITY}" \
        --format table \
        ${IGNORE_UNFIXED:+--ignore-unfixed} \
        "${path}"
}

#--- 扫描 Kubernetes 集群 ---
scan_k8s() {
    log_info "扫描 Kubernetes 集群..."

    trivy k8s \
        --severity "${SEVERITY}" \
        --format table \
        --namespace "${1:-default}" \
        cluster
}

#--- 生成 SBOM ---
generate_sbom() {
    local image="$1"
    local output="${REPORT_DIR}/sbom.spdx.json"

    log_info "生成 SBOM: ${image}"
    trivy image \
        --format spdx-json \
        --output "${output}" \
        "${image}"

    log_info "SBOM 已保存: ${output}"
}

#--- CI/CD 集成入口 ---
ci_scan() {
    local image="$1"
    local ci_platform="${CI_PLATFORM:-github}"

    log_info "CI/CD 镜像扫描 (平台: ${ci_platform})"

    # 扫描
    scan_image "${image}"
    local exit_code=$?

    # 根据 CI 平台输出
    case "${ci_platform}" in
        github)
            # GitHub Actions annotations
            if [[ -f "${REPORT_DIR}/${image//\//-}.sarif" ]]; then
                echo "::notice::Trivy scan completed. Report: ${REPORT_DIR}/"
            fi
            if [[ ${exit_code} -ne 0 ]]; then
                echo "::error::Image ${image} has CRITICAL vulnerabilities!"
            fi
            ;;
        gitlab)
            # GitLab CI artifacts
            log_info "报告将作为 CI artifacts 保存"
            ;;
    esac

    return ${exit_code}
}

#--- 帮助 ---
usage() {
    cat <<EOF
Trivy 容器镜像安全扫描脚本

用法: $0 <command> [options]

命令:
  install                   安装 Trivy
  image <image>             扫描容器镜像
  fs <path>                 扫描文件系统
  k8s [namespace]           扫描 K8S 集群
  sbom <image>              生成 SBOM
  ci <image>                CI/CD 集成扫描

环境变量:
  SEVERITY       漏洞级别 (默认: CRITICAL,HIGH)
  IGNORE_UNFIXED 忽略无修复的漏洞 (默认: true)
  EXIT_CODE      发现CRITICAL时的退出码 (默认: 1)
  CI_PLATFORM    CI平台 (github/gitlab, 默认: github)
  REPORT_DIR     报告目录 (默认: ./scan-reports)

示例:
  $0 install
  $0 image nginx:latest
  $0 image myapp:v1.0 --severity CRITICAL
  $0 fs /path/to/project
  $0 k8s production
  $0 ci myapp:v1.0
EOF
}

main() {
    local cmd="${1:-help}"
    shift || true

    case "${cmd}" in
        install) install_trivy ;;
        image)   scan_image "$@" ;;
        fs)      scan_fs "$@" ;;
        k8s)     scan_k8s "$@" ;;
        sbom)    generate_sbom "$@" ;;
        ci)      ci_scan "$@" ;;
        help|*)  usage ;;
    esac
}

main "$@"
