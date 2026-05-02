#!/bin/bash
#=============================================================================
# JMeter 分布式压测管理脚本
# 用途: 管理分布式压测环境、执行压测、收集结果
# 适用场景: 企业级性能测试、容量评估、稳定性验证
#=============================================================================

set -euo pipefail

#--- 配置区 ---
JMETER_HOME="${JMETER_HOME:-/opt/apache-jmeter}"
JMETER_VERSION="5.6.3"
TEST_PLAN_DIR="$(cd "$(dirname "$0")/../jmeter" && pwd)"
REPORT_DIR="$(cd "$(dirname "$0")/../reports" && pwd)"
RESULTS_DIR="${REPORT_DIR}/raw"
LOG_DIR="${REPORT_DIR}/logs"

# 分布式 Slave 节点列表
SLAVE_NODES="${SLAVE_NODES:-slave1:1099,slave2:1099,slave3:1099}"

# 压测参数
THREADS="${THREADS:-100}"
RAMP_UP="${RAMP_UP:-30}"
DURATION="${DURATION:-300}"
LOOPS="${LOOPS:-1}"

# 目标应用
TARGET_HOST="${TARGET_HOST:-app.example.com}"
TARGET_PORT="${TARGET_PORT:-8080}"
TARGET_PROTOCOL="${TARGET_PROTOCOL:-https}"

# 告警阈值
ERROR_RATE_THRESHOLD="${ERROR_RATE_THRESHOLD:-5}"      # 错误率阈值(%)
RT_P95_THRESHOLD="${RT_P95_THRESHOLD:-2000}"           # P95响应时间阈值(ms)
RT_P99_THRESHOLD="${RT_P99_THRESHOLD:-5000}"           # P99响应时间阈值(ms)

# 钉钉/企业微信告警
WEBHOOK_URL="${WEBHOOK_URL:-}"

#--- 颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*"; }

#--- 初始化 ---
init() {
    log_info "初始化压测环境..."
    mkdir -p "${TEST_PLAN_DIR}" "${REPORT_DIR}" "${RESULTS_DIR}" "${LOG_DIR}"

    # 检查 JMeter
    if [[ ! -d "${JMETER_HOME}" ]]; then
        log_error "JMeter 未安装: ${JMETER_HOME}"
        log_info "请先运行: $0 install"
        exit 1
    fi

    # 检查 Java
    if ! command -v java &>/dev/null; then
        log_error "Java 未安装"
        exit 1
    fi

    java_version=$(java -version 2>&1 | head -1)
    log_info "Java 版本: ${java_version}"
    log_info "JMeter 路径: ${JMETER_HOME}"
    log_info "测试计划目录: ${TEST_PLAN_DIR}"
    log_info "报告目录: ${REPORT_DIR}"
}

#--- 安装 JMeter ---
install_jmeter() {
    log_info "安装 JMeter ${JMETER_VERSION}..."

    local install_dir="/opt"
    local download_url="https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz"

    # 检查 Java 11+
    if ! command -v java &>/dev/null; then
        log_info "安装 Java 11..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq openjdk-11-jdk
        elif command -v yum &>/dev/null; then
            yum install -y java-11-openjdk java-11-openjdk-devel
        fi
    fi

    # 下载 JMeter
    if [[ ! -f "/tmp/apache-jmeter-${JMETER_VERSION}.tgz" ]]; then
        log_info "下载 JMeter..."
        curl -fSL "${download_url}" -o "/tmp/apache-jmeter-${JMETER_VERSION}.tgz"
    fi

    # 解压安装
    tar -xzf "/tmp/apache-jmeter-${JMETER_VERSION}.tgz" -C "${install_dir}"
    ln -snf "${install_dir}/apache-jmeter-${JMETER_VERSION}" "${JMETER_HOME}"

    # 安装常用插件
    log_info "安装 JMeter 插件..."
    local plugins_dir="${JMETER_HOME}/lib/ext"
    local plugin_manager_url="https://jmeter-plugins.org/get/"

    # 下载插件管理器
    curl -fSL "${plugin_manager_url}" -o "${plugins_dir}/jmeter-plugins-manager.jar" 2>/dev/null || true

    # 配置环境变量
    cat >> /etc/profile.d/jmeter.sh <<'ENVEOF'
export JMETER_HOME=/opt/apache-jmeter
export PATH="${JMETER_HOME}/bin:${PATH}"
ENVEOF

    log_ok "JMeter ${JMETER_VERSION} 安装完成"
}

#--- 生成测试计划 ---
generate_test_plan() {
    local plan_name="${1:-stress-test}"
    local plan_file="${TEST_PLAN_DIR}/${plan_name}.jmx"

    log_info "生成测试计划: ${plan_name}"

    cat > "${plan_file}" <<'JMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0" jmeter="5.6.3">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="企业级压力测试" enabled="true">
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
      <stringProp name="TestPlan.comments">自动生成的企业级压测计划</stringProp>
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel">
        <collectionProp name="Arguments.arguments">
          <elementProp name="HOST" elementType="Argument">
            <stringProp name="Argument.name">HOST</stringProp>
            <stringProp name="Argument.value">${__P(host,app.example.com)}</stringProp>
          </elementProp>
          <elementProp name="PORT" elementType="Argument">
            <stringProp name="Argument.name">PORT</stringProp>
            <stringProp name="Argument.value">${__P(port,8080)}</stringProp>
          </elementProp>
          <elementProp name="PROTOCOL" elementType="Argument">
            <stringProp name="Argument.name">PROTOCOL</stringProp>
            <stringProp name="Argument.value">${__P(protocol,https)}</stringProp>
          </elementProp>
        </collectionProp>
      </elementProp>
    </TestPlan>
    <hashTree>
      <!-- 线程组: 梯度加压 -->
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="梯度加压线程组" enabled="true">
        <intProp name="ThreadGroup.num_threads">${__P(threads,100)}</intProp>
        <intProp name="ThreadGroup.ramp_time">${__P(rampup,30)}</intProp>
        <longProp name="ThreadGroup.duration">${__P(duration,300)}</longProp>
        <boolProp name="ThreadGroup.scheduler">true</boolProp>
        <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
      </ThreadGroup>
      <hashTree>
        <!-- HTTP 请求默认值 -->
        <ConfigTestElement guiclass="HttpDefaultsGui" testclass="ConfigTestElement" testname="HTTP 请求默认值" enabled="true">
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments"/>
          </elementProp>
          <stringProp name="HTTPSampler.domain">${HOST}</stringProp>
          <stringProp name="HTTPSampler.port">${PORT}</stringProp>
          <stringProp name="HTTPSampler.protocol">${PROTOCOL}</stringProp>
          <stringProp name="HTTPSampler.connect_timeout">5000</stringProp>
          <stringProp name="HTTPSampler.response_timeout">30000</stringProp>
        </ConfigTestElement>
        <hashTree/>

        <!-- HTTP Cookie 管理器 -->
        <CookieManager guiclass="CookiePanel" testclass="CookieManager" testname="Cookie 管理器" enabled="true">
          <collectionProp name="CookieManager.cookies"/>
          <boolProp name="CookieManager.clearEachIteration">false</boolProp>
        </CookieManager>
        <hashTree/>

        <!-- HTTP 头管理器 -->
        <HeaderManager guiclass="HeaderPanel" testclass="HeaderManager" testname="HTTP 头管理器" enabled="true">
          <collectionProp name="HeaderManager.headers">
            <elementProp name="" elementType="Header">
              <stringProp name="Header.name">Content-Type</stringProp>
              <stringProp name="Header.value">application/json</stringProp>
            </elementProp>
            <elementProp name="" elementType="Header">
              <stringProp name="Header.name">User-Agent</stringProp>
              <stringProp name="Header.value">JMeter-LoadTest/1.0</stringProp>
            </elementProp>
          </collectionProp>
        </HeaderManager>
        <hashTree/>

        <!-- 事务控制器: 首页访问 -->
        <TransactionController guiclass="TransactionControllerGui" testclass="TransactionController" testname="首页访问" enabled="true">
          <boolProp name="TransactionController.includeTimers">false</boolProp>
        </TransactionController>
        <hashTree>
          <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="GET 首页" enabled="true">
            <stringProp name="HTTPSampler.path">/</stringProp>
            <stringProp name="HTTPSampler.method">GET</stringProp>
            <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          </HTTPSamplerProxy>
          <hashTree/>
        </hashTree>

        <!-- 事务控制器: API 调用 -->
        <TransactionController guiclass="TransactionControllerGui" testclass="TransactionController" testname="API 调用" enabled="true">
          <boolProp name="TransactionController.includeTimers">false</boolProp>
        </TransactionController>
        <hashTree>
          <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="GET API 列表" enabled="true">
            <stringProp name="HTTPSampler.path">/api/v1/items</stringProp>
            <stringProp name="HTTPSampler.method">GET</stringProp>
            <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          </HTTPSamplerProxy>
          <hashTree>
            <ResponseAssertion guiclass="AssertionGui" testclass="ResponseAssertion" testname="状态码 200" enabled="true">
              <collectionProp name="Asserion.test_strings">
                <stringProp name="49586">200</stringProp>
              </collectionProp>
              <stringProp name="Assertion.test_field">Assertion.response_code</stringProp>
              <intProp name="Assertion.test_type">8</intProp>
            </ResponseAssertion>
            <hashTree/>
          </hashTree>
        </hashTree>

        <!-- 思考时间 -->
        <ConstantTimer guiclass="ConstantTimerGui" testclass="ConstantTimer" testname="思考时间" enabled="true">
          <stringProp name="ConstantTimer.delay">1000</stringProp>
        </ConstantTimer>
        <hashTree/>

        <!-- 聚合报告 -->
        <ResultCollector guiclass="StatVisualizer" testclass="ResultCollector" testname="聚合报告" enabled="true">
          <boolProp name="ResultCollector.error_logging">false</boolProp>
          <objProp>
            <name>saveConfig</name>
            <value class="SampleSaveConfiguration">
              <time>true</time>
              <latency>true</latency>
              <timestamp>true</timestamp>
              <success>true</success>
              <label>true</label>
              <code>true</code>
              <message>true</message>
              <threadName>true</threadName>
              <dataType>true</dataType>
              <encoding>false</encoding>
              <assertions>true</assertions>
              <subresults>true</subresults>
              <responseData>false</responseData>
              <samplerData>false</samplerData>
              <xml>false</xml>
              <fieldNames>true</fieldNames>
              <responseHeaders>false</responseHeaders>
              <requestHeaders>false</requestHeaders>
              <responseDataOnError>true</responseDataOnError>
              <saveAssertionResultsFailureMessage>true</saveAssertionResultsFailureMessage>
              <bytes>true</bytes>
              <sentBytes>true</sentBytes>
              <url>true</url>
              <threadCounts>true</threadCounts>
              <connectTime>true</connectTime>
            </value>
          </objProp>
          <stringProp name="filename">results.jtl</stringProp>
        </ResultCollector>
        <hashTree/>
      </hashTree>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
JMEOF

    log_ok "测试计划已生成: ${plan_file}"
}

#--- 执行压测 ---
run_test() {
    local plan_file="${1:-}"
    local test_name="${2:-test-$(date +%Y%m%d-%H%M%S)}"

    if [[ -z "${plan_file}" ]]; then
        log_error "请指定测试计划文件"
        echo "用法: $0 run <test-plan.jmx> [test-name]"
        exit 1
    fi

    if [[ ! -f "${plan_file}" ]]; then
        log_error "测试计划不存在: ${plan_file}"
        exit 1
    fi

    init

    local result_file="${RESULTS_DIR}/${test_name}.jtl"
    local log_file="${LOG_DIR}/${test_name}.log"
    local report_dir="${REPORT_DIR}/${test_name}"

    log_info "=========================================="
    log_info "开始压测: ${test_name}"
    log_info "测试计划: ${plan_file}"
    log_info "并发线程: ${THREADS}"
    log_info "Ramp-Up:  ${RAMP_UP}s"
    log_info "持续时间: ${DURATION}s"
    log_info "目标主机: ${TARGET_HOST}:${TARGET_PORT}"
    log_info "=========================================="

    # 检查 Slave 节点连通性
    check_slaves

    # 清理旧结果
    rm -f "${result_file}"
    rm -rf "${report_dir}"

    # 执行分布式压测
    local start_time=$(date +%s)

    local slave_args=""
    if [[ -n "${SLAVE_NODES}" ]]; then
        slave_args="-R ${SLAVE_NODES//,/ }"
        log_info "分布式模式: ${SLAVE_NODES}"
    fi

    "${JMETER_HOME}/bin/jmeter" -n -t "${plan_file}" \
        -l "${result_file}" \
        -j "${log_file}" \
        -e -o "${report_dir}" \
        ${slave_args} \
        -Jthreads="${THREADS}" \
        -Jrampup="${RAMP_UP}" \
        -Jduration="${DURATION}" \
        -Jhost="${TARGET_HOST}" \
        -Jport="${TARGET_PORT}" \
        -Jprotocol="${TARGET_PROTOCOL}" \
        2>&1 | tee "${log_file}"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_ok "压测完成! 耗时: ${duration}s"
    log_info "结果文件: ${result_file}"
    log_info "HTML报告: ${report_dir}/index.html"

    # 分析结果
    analyze_results "${result_file}" "${test_name}"
}

#--- 检查 Slave 节点 ---
check_slaves() {
    if [[ -z "${SLAVE_NODES}" ]]; then
        log_info "无 Slave 节点, 使用本地模式"
        return 0
    fi

    IFS=',' read -ra slaves <<< "${SLAVE_NODES}"
    for slave in "${slaves[@]}"; do
        local host="${slave%%:*}"
        local port="${slave##*:}"
        if nc -zw3 "${host}" "${port}" 2>/dev/null; then
            log_ok "Slave 可达: ${host}:${port}"
        else
            log_warn "Slave 不可达: ${host}:${port}"
        fi
    done
}

#--- 分析压测结果 ---
analyze_results() {
    local result_file="$1"
    local test_name="$2"

    if [[ ! -f "${result_file}" ]]; then
        log_warn "结果文件不存在, 跳过分析"
        return
    fi

    log_info "分析压测结果..."

    # 使用 awk 分析 JTL 文件
    local analysis=$(awk -F',' '
    NR > 1 {
        total++
        if ($7 == "true") success++
        else fail++
        rt_sum += $2
        if ($2 > rt_max) rt_max = $2
        rts[NR] = $2
    }
    END {
        if (total == 0) { print "ERROR:no_data"; exit }
        avg_rt = rt_sum / total
        err_rate = (fail / total) * 100

        # 排序计算百分位
        n = asort(rts)
        p50 = rts[int(n * 0.5)]
        p90 = rts[int(n * 0.9)]
        p95 = rts[int(n * 0.95)]
        p99 = rts[int(n * 0.99)]

        printf "total=%d success=%d fail=%d err_rate=%.2f avg_rt=%.0f p50=%.0f p90=%.0f p95=%.0f p99=%.0f max_rt=%.0f", \
            total, success, fail, err_rate, avg_rt, p50, p90, p95, p99, rt_max
    }' "${result_file}")

    if [[ "${analysis}" == "ERROR:no_data" ]]; then
        log_warn "无有效数据"
        return
    fi

    # 解析结果
    eval "${analysis}"

    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║         压测结果报告 - ${test_name}         ║"
    echo "╠══════════════════════════════════════════╣"
    printf "║  总请求数:     %-25s║\n" "${total}"
    printf "║  成功数:       %-25s║\n" "${success}"
    printf "║  失败数:       %-25s║\n" "${fail}"
    printf "║  错误率:       %-25s║\n" "${err_rate}%"
    printf "║  平均响应时间: %-25s║\n" "${avg_rt}ms"
    printf "║  P50:          %-25s║\n" "${p50}ms"
    printf "║  P90:          %-25s║\n" "${p90}ms"
    printf "║  P95:          %-25s║\n" "${p95}ms"
    printf "║  P99:          %-25s║\n" "${p99}ms"
    printf "║  最大响应时间: %-25s║\n" "${rt_max}ms"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    # 阈值检查与告警
    local alerts=""
    if (( $(echo "${err_rate} > ${ERROR_RATE_THRESHOLD}" | bc -l) )); then
        alerts+="❌ 错误率 ${err_rate}% 超过阈值 ${ERROR_RATE_THRESHOLD}%\n"
    fi
    if (( $(echo "${p95} > ${RT_P95_THRESHOLD}" | bc -l) )); then
        alerts+="❌ P95响应时间 ${p95}ms 超过阈值 ${RT_P95_THRESHOLD}ms\n"
    fi
    if (( $(echo "${p99} > ${RT_P99_THRESHOLD}" | bc -l) )); then
        alerts+="❌ P99响应时间 ${p99}ms 超过阈值 ${RT_P99_THRESHOLD}ms\n"
    fi

    if [[ -n "${alerts}" ]]; then
        log_warn "发现性能问题:"
        echo -e "${alerts}"
        send_alert "${test_name}" "${alerts}" "${total}" "${err_rate}" "${p95}" "${p99}"
    else
        log_ok "所有指标在阈值范围内 ✓"
    fi

    # 保存分析结果
    cat > "${REPORT_DIR}/${test_name}-summary.txt" <<SUMEOF
压测报告: ${test_name}
时间: $(date '+%Y-%m-%d %H:%M:%S')
========================================
总请求数:     ${total}
成功数:       ${success}
失败数:       ${fail}
错误率:       ${err_rate}%
平均响应时间: ${avg_rt}ms
P50:          ${p50}ms
P90:          ${p90}ms
P95:          ${p95}ms
P99:          ${p99}ms
最大响应时间: ${rt_max}ms
========================================
阈值检查:
  错误率阈值:   ${ERROR_RATE_THRESHOLD}%  → $([ $(echo "${err_rate} > ${ERROR_RATE_THRESHOLD}" | bc -l) -eq 1 ] && echo "❌ 超标" || echo "✅ 正常")
  P95阈值:      ${RT_P95_THRESHOLD}ms   → $([ $(echo "${p95} > ${RT_P95_THRESHOLD}" | bc -l) -eq 1 ] && echo "❌ 超标" || echo "✅ 正常")
  P99阈值:      ${RT_P99_THRESHOLD}ms   → $([ $(echo "${p99} > ${RT_P99_THRESHOLD}" | bc -l) -eq 1 ] && echo "❌ 超标" || echo "✅ 正常")
SUMEOF
}

#--- 发送告警 ---
send_alert() {
    local test_name="$1"
    local alerts="$2"
    local total="$3"
    local err_rate="$4"
    local p95="$5"
    local p99="$6"

    if [[ -z "${WEBHOOK_URL}" ]]; then
        log_info "未配置告警 Webhook, 跳过通知"
        return
    fi

    local payload=$(cat <<ALERTEOF
{
    "msgtype": "markdown",
    "markdown": {
        "title": "⚠️ 压测告警",
        "text": "## ⚠️ 压测性能告警\n\n**测试名称:** ${test_name}\n\n**告警详情:**\n${alerts}\n\n**性能指标:**\n- 总请求数: ${total}\n- 错误率: ${err_rate}%\n- P95: ${p95}ms\n- P99: ${p99}ms\n\n**时间:** $(date '+%Y-%m-%d %H:%M:%S')"
    }
}
ALERTEOF
)

    curl -s -X POST "${WEBHOOK_URL}" \
        -H 'Content-Type: application/json' \
        -d "${payload}" >/dev/null 2>&1 || log_warn "告警发送失败"
}

#--- 梯度压测 (逐步加压) ---
run_gradient_test() {
    local plan_file="$1"
    local stages="10,50,100,200,500,1000"

    log_info "执行梯度压测: ${stages}"

    IFS=',' read -ra thread_stages <<< "${stages}"
    for threads in "${thread_stages[@]}"; do
        local test_name="gradient-${threads}users-$(date +%Y%m%d-%H%M%S)"
        log_info "===== 阶段: ${threads} 并发用户 ====="
        THREADS="${threads}" run_test "${plan_file}" "${test_name}"
        sleep 30  # 阶段间隔冷却
    done

    log_ok "梯度压测完成"
}

#--- 生成对比报告 ---
compare_reports() {
    local report1="$1"
    local report2="$2"

    log_info "对比两次压测结果..."
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    压测结果对比                              ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║  %-15s  %-20s  %-20s ║\n" "指标" "基线" "当前"
    echo "╠══════════════════════════════════════════════════════════════╣"

    if [[ -f "${report1}" && -f "${report2}" ]]; then
        # 从报告文件提取数据对比
        local metrics=("总请求数" "错误率" "平均响应时间" "P95" "P99")
        for metric in "${metrics[@]}"; do
            local val1=$(grep "${metric}" "${report1}" | awk -F: '{print $2}' | tr -d ' ')
            local val2=$(grep "${metric}" "${report2}" | awk -F: '{print $2}' | tr -d ' ')
            printf "║  %-15s  %-20s  %-20s ║\n" "${metric}" "${val1:-N/A}" "${val2:-N/A}"
        done
    fi

    echo "╚══════════════════════════════════════════════════════════════╝"
}

#--- 清理旧报告 ---
cleanup() {
    local keep_days="${1:-30}"
    log_info "清理 ${keep_days} 天前的压测报告..."
    find "${REPORT_DIR}" -type f -mtime "+${keep_days}" -delete 2>/dev/null
    find "${RESULTS_DIR}" -type f -mtime "+${keep_days}" -delete 2>/dev/null
    log_ok "清理完成"
}

#--- 帮助 ---
usage() {
    cat <<EOF
JMeter 分布式压测管理脚本

用法: $0 <command> [options]

命令:
  install                              安装 JMeter
  init                                 初始化环境
  generate [plan-name]                 生成测试计划模板
  run <plan.jmx> [test-name]          执行压测
  gradient <plan.jmx>                  梯度压测(逐步加压)
  compare <report1> <report2>          对比两次压测结果
  cleanup [days]                       清理旧报告(默认30天)

环境变量:
  THREADS          并发线程数 (默认: 100)
  RAMP_UP          Ramp-Up 时间秒 (默认: 30)
  DURATION         持续时间秒 (默认: 300)
  TARGET_HOST      目标主机 (默认: app.example.com)
  TARGET_PORT      目标端口 (默认: 8080)
  SLAVE_NODES      分布式Slave节点 (默认: slave1:1099,slave2:1099)
  WEBHOOK_URL      告警通知地址

示例:
  $0 install
  $0 generate api-stress
  THREADS=200 DURATION=600 $0 run jmeter/api-stress.jmx load-test-v1
  $0 gradient jmeter/api-stress.jmx
EOF
}

#--- 主入口 ---
main() {
    local cmd="${1:-help}"
    shift || true

    case "${cmd}" in
        install)    install_jmeter ;;
        init)       init ;;
        generate)   generate_test_plan "${1:-stress-test}" ;;
        run)        run_test "$@" ;;
        gradient)   run_gradient_test "$@" ;;
        compare)    compare_reports "$@" ;;
        cleanup)    cleanup "${1:-30}" ;;
        help|*)     usage ;;
    esac
}

main "$@"
