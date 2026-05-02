#!/bin/bash
#=============================================================================
# Falco 运行时威胁检测安装脚本
# 用途: 容器运行时安全监控、异常行为检测
#=============================================================================

set -euo pipefail

FALCO_VERSION="${FALCO_VERSION:-0.36.2}"
NAMESPACE="${NAMESPACE:-falco}"
WEBHOOK_URL="${WEBHOOK_URL:-}"

log_info()  { echo -e "\033[0;32m[INFO]\033[0m  $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; }

#--- 安装 Falco (K8S DaemonSet) ---
install_falco() {
    log_info "安装 Falco ${NAMESPACE}..."

    # 使用 Helm 安装
    helm repo add falcosecurity https://falcosecurity.github.io/charts
    helm repo update

    helm upgrade --install falco falcosecurity/falco \
        --namespace ${NAMESPACE} \
        --create-namespace \
        --set falcosidekick.enabled=true \
        --set falcosidekick.config.slack.webhookurl="${WEBHOOK_URL}" \
        --set falco.grpc.enabled=true \
        --set falco.grpc.output.enabled=true \
        --set driver.kind=modern_ebpf \
        --set falco.rules_file[0]=/etc/falco/falco_rules.yaml \
        --set falco.rules_file[1]=/etc/falco/k8s_audit_rules.yaml \
        --set falco.json_output=true \
        --set falco.json_include_output_property=true \
        --set falco.priority=warning \
        --set resources.requests.cpu=100m \
        --set resources.requests.memory=256Mi \
        --set resources.limits.cpu=500m \
        --set resources.limits.memory=512Mi

    log_info "Falco 安装完成"
    kubectl -n ${NAMESPACE} get pods
}

#--- 自定义 Falco 规则 ---
apply_custom_rules() {
    log_info "应用自定义检测规则..."

    cat <<'RULES' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-custom-rules
  namespace: falco
data:
  custom-rules.yaml: |
    - rule: 检测容器内 Crypto Mining
      desc: 检测加密货币挖矿行为
      condition: >
        spawned_process and container and
        (proc.name in (xmrig, minerd, cpuminer, cgminer) or
         proc.cmdline contains "stratum+tcp" or
         proc.cmdline contains "stratum+ssl")
      output: "检测到挖矿行为 (user=%user.name container=%container.name command=%proc.cmdline)"
      priority: CRITICAL
      tags: [crypto, mining, mitre_execution]

    - rule: 检测异常 kubectl exec
      desc: 检测对生产容器的 exec 操作
      condition: >
        spawned_process and container and
        proc.name = kubectl and
        proc.cmdline contains "exec" and
        k8s.ns.name = production
      output: "生产容器 exec 操作 (user=%user.name command=%proc.cmdline)"
      priority: WARNING
      tags: [k8s, exec, mitre_lateral_movement]

    - rule: 检测敏感目录写入
      desc: 检测对系统敏感目录的写入
      condition: >
        open_write and container and
        (fd.name startswith /etc or
         fd.name startswith /usr/bin or
         fd.name startswith /root/.ssh)
      output: "敏感目录写入 (user=%user.name file=%fd.name container=%container.name)"
      priority: CRITICAL
      tags: [filesystem, mitre_persistence]

    - rule: 检测容器逃逸尝试
      desc: 检测可能的容器逃逸行为
      condition: >
        (spawned_process and container and proc.name = nsenter) or
        (open_read and container and fd.name = /proc/1/root)
      output: "可能的容器逃逸 (user=%user.name command=%proc.cmdline)"
      priority: CRITICAL
      tags: [container_escape, mitre_privilege_escalation]

    - rule: 检测异常网络扫描
      desc: 检测容器内的网络扫描行为
      condition: >
        spawned_process and container and
        (proc.name in (nmap, masscan, zmap) or
         proc.cmdline contains "nc -z" or
         proc.cmdline contains "hping3")
      output: "网络扫描行为 (user=%user.name command=%proc.cmdline container=%container.name)"
      priority: CRITICAL
      tags: [network, scanning, mitre_discovery]

    - rule: 检测 Secret 文件访问
      desc: 检测对 K8S Secret 挂载的异常访问
      condition: >
        open_read and container and
        fd.name startswith /var/run/secrets
      output: "Secret 文件访问 (user=%user.name file=%fd.name container=%container.name)"
      priority: NOTICE
      tags: [k8s, secrets, mitre_credential_access]

    - rule: 检测异常 Cron 创建
      desc: 检测容器内创建 cron 任务
      condition: >
        spawned_process and container and
        (proc.name = crontab or
         fd.name startswith /etc/cron)
      output: "异常 Cron 创建 (user=%user.name command=%proc.cmdline)"
      priority: CRITICAL
      tags: [persistence, cron, mitre_persistence]
RULES

    log_info "自定义规则已应用"
}

#--- 帮助 ---
usage() {
    cat <<EOF
Falco 运行时威胁检测管理脚本

用法: $0 <command> [options]

命令:
  install          安装 Falco (K8S DaemonSet)
  rules            应用自定义检测规则
  status           查看运行状态
  logs             查看检测日志

环境变量:
  WEBHOOK_URL      告警通知地址 (Slack/钉钉)
  NAMESPACE        安装命名空间 (默认: falco)

示例:
  $0 install
  WEBHOOK_URL=https://hooks.slack.com/xxx $0 install
  $0 rules
  $0 status
EOF
}

main() {
    local cmd="${1:-help}"
    shift || true

    case "${cmd}" in
        install) install_falco ;;
        rules)   apply_custom_rules ;;
        status)  kubectl -n ${NAMESPACE} get pods ;;
        logs)    kubectl -n ${NAMESPACE} logs -l app=falco --tail=100 -f ;;
        help|*)  usage ;;
    esac
}

main "$@"
