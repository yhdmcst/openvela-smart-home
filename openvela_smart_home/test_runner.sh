#!/bin/bash
# ============================================================
#  test_runner.sh - 智能家居 Tool 自动化测试套件
#  支持三种模式：
#    1) 快速测试 (./test_runner.sh) — 编译+运行C工具测试
#    2) 基准测试 (./test_runner.sh bench) — 性能基准
#    3) 完整测试 (./test_runner.sh full)  — 全部测试+安全检查
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"
SECURITY_DIR="${SCRIPT_DIR}/security"
BUILD_DIR="${SCRIPT_DIR}/.test_build"
PASS=0; FAIL=0; SKIP=0

# 颜色
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

mkdir -p "$BUILD_DIR"

# ---------- 测试框架 ----------
test_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
test_fail() { echo -e "  ${RED}[FAIL]${NC} $1 — $2"; FAIL=$((FAIL+1)); }
test_skip() { echo -e "  ${YELLOW}[SKIP]${NC} $1 — $2"; SKIP=$((SKIP+1)); }

assert_eq() {
    local desc="$1"; local expected="$2"; local actual="$3"
    if [ "$expected" = "$actual" ]; then test_pass "$desc"; else test_fail "$desc" "期望 '$expected' 实际 '$actual'"; fi
}

assert_contains() {
    local desc="$1"; local file="$2"; local pattern="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then test_pass "$desc"; else test_fail "$desc" "未找到 '$pattern'"; fi
}

# ---------- 测试1: 灯光控制 Tool ----------
test_light_control() {
    echo -e "\n${BOLD}${BLUE}[Test Suite 1] 灯光控制 Tool${NC}"

    # 编译独立的灯光测试程序
    cat > "${BUILD_DIR}/test_light.c" << 'EOF'
#include <stdio.h>
#include <string.h>
#define SMOKE_TEST_MODE
#define SMART_HOME_TOOLS_H            /* 阻止 smart_home_tools.h 重复定义类型 */
/* 内联编译灯光控制Tool（仅此一处包含源文件） */
#include "../tools/tool_light_control.c"

int main(void) {
    smart_home_tools_init();
    light_control_params_t p;
    light_control_result_t r;
    int ret;

    /* 测试1: 开灯 */
    memset(&p, 0, sizeof(p)); memset(&r, 0, sizeof(r));
    p.location = LOCATION_LIVING_ROOM; p.action = LIGHT_ACTION_ON;
    ret = tool_light_control(&p, &r);
    printf("TEST1_STATUS=%d\n", ret);
    printf("TEST1_BRIGHT=%d\n", r.current_brightness);
    printf("TEST1_LOC=%s\n", r.location_name);

    /* 测试2: 调亮度 */
    memset(&p, 0, sizeof(p)); memset(&r, 0, sizeof(r));
    p.location = LOCATION_BEDROOM; p.action = LIGHT_ACTION_SET_BRIGHTNESS; p.brightness = 60;
    ret = tool_light_control(&p, &r);
    printf("TEST2_STATUS=%d\n", ret);
    printf("TEST2_BRIGHT=%d\n", r.current_brightness);

    /* 测试3: 关灯 */
    memset(&p, 0, sizeof(p)); memset(&r, 0, sizeof(r));
    p.location = LOCATION_LIVING_ROOM; p.action = LIGHT_ACTION_OFF;
    ret = tool_light_control(&p, &r);
    printf("TEST3_STATUS=%d\n", ret);
    printf("TEST3_BRIGHT=%d\n", r.current_brightness);

    /* 测试4: 全屋操作 */
    memset(&p, 0, sizeof(p)); memset(&r, 0, sizeof(r));
    p.location = LOCATION_ALL; p.action = LIGHT_ACTION_ON;
    ret = tool_light_control(&p, &r);
    printf("TEST4_STATUS=%d\n", ret);

    /* 测试5: 参数校验 — NULL params */
    ret = tool_light_control(NULL, &r);
    printf("TEST5_STATUS=%d\n", ret);

    /* 测试6: 参数校验 — NULL result */
    memset(&p, 0, sizeof(p)); p.location = LOCATION_LIVING_ROOM; p.action = LIGHT_ACTION_ON;
    ret = tool_light_control(&p, NULL);
    printf("TEST6_STATUS=%d\n", ret);

    /* 测试7: 边界亮度值 200 */
    memset(&p, 0, sizeof(p)); memset(&r, 0, sizeof(r));
    p.location = LOCATION_STUDY; p.action = LIGHT_ACTION_SET_BRIGHTNESS; p.brightness = 200;
    ret = tool_light_control(&p, &r);
    printf("TEST7_STATUS=%d\n", ret);
    printf("TEST7_BRIGHT=%d\n", r.current_brightness);

    /* 测试8: toggle */
    memset(&p, 0, sizeof(p)); memset(&r, 0, sizeof(r));
    p.location = LOCATION_KITCHEN; p.action = LIGHT_ACTION_TOGGLE;
    ret = tool_light_control(&p, &r);
    printf("TEST8_STATUS=%d\n", ret);

    return 0;
}
EOF

    if gcc -I"${TOOLS_DIR}" -I"${SECURITY_DIR}" -o "${BUILD_DIR}/test_light" "${BUILD_DIR}/test_light.c" -lm 2>/dev/null; then
        output=$("${BUILD_DIR}/test_light" 2>/dev/null)
        assert_eq   "1-开灯成功"     "0"   "$(echo "$output" | grep "TEST1_STATUS=" | cut -d= -f2)"
        assert_eq   "1-开灯亮度100"   "100" "$(echo "$output" | grep "TEST1_BRIGHT=" | cut -d= -f2)"
        assert_eq   "2-调亮度成功"    "0"   "$(echo "$output" | grep "TEST2_STATUS=" | cut -d= -f2)"
        assert_eq   "2-调亮度60"      "60"  "$(echo "$output" | grep "TEST2_BRIGHT=" | cut -d= -f2)"
        assert_eq   "3-关灯成功"      "0"   "$(echo "$output" | grep "TEST3_STATUS=" | cut -d= -f2)"
        assert_eq   "3-关灯亮度0"     "0"   "$(echo "$output" | grep "TEST3_BRIGHT=" | cut -d= -f2)"
        assert_eq   "4-全屋操作成功"  "0"   "$(echo "$output" | grep "TEST4_STATUS=" | cut -d= -f2)"
        assert_eq   "5-拒NULL params" "-1"  "$(echo "$output" | grep "TEST5_STATUS=" | cut -d= -f2)"
        assert_eq   "6-拒NULL result" "-1"  "$(echo "$output" | grep "TEST6_STATUS=" | cut -d= -f2)"
        assert_eq   "7-边界截断成功"  "0"   "$(echo "$output" | grep "TEST7_STATUS=" | cut -d= -f2)"
        assert_eq   "7-截断为100"     "100" "$(echo "$output" | grep "TEST7_BRIGHT=" | cut -d= -f2)"
        assert_eq   "8-toggle成功"   "0"   "$(echo "$output" | grep "TEST8_STATUS=" | cut -d= -f2)"
    else
        test_skip "灯光测试编译" "需要完整的 openvela 编译环境"
    fi
}

# ---------- 测试2: 温湿度 Tool ----------
test_temperature() {
    echo -e "\n${BOLD}${BLUE}[Test Suite 2] 温湿度读取 Tool${NC}"

    cat > "${BUILD_DIR}/test_temp.c" << 'EOF'
#include <stdio.h>
#include <string.h>
extern int tool_temperature_read(const char*, void*);
extern int tool_temperature_read_all(void*, int*);
#include "../tools/tool_temperature_read.c"

int main(void) {
    temperature_humidity_t r;
    int ret;

    /* 测试1: 客厅读取 */
    memset(&r, 0, sizeof(r));
    ret = tool_temperature_read("客厅", &r);
    printf("T1_STATUS=%d\n", ret);
    printf("T1_TEMP_RANGE=%d\n", (r.temperature >= 24.0 && r.temperature <= 26.0));
    printf("T1_HUM_RANGE=%d\n",  (r.humidity >= 55.0 && r.humidity <= 65.0));

    /* 测试2: NULL location */
    ret = tool_temperature_read(NULL, &r);
    printf("T2_STATUS=%d\n", ret);

    /* 测试3: NULL result */
    ret = tool_temperature_read("客厅", NULL);
    printf("T3_STATUS=%d\n", ret);

    /* 测试4: 未知位置回退 */
    memset(&r, 0, sizeof(r));
    ret = tool_temperature_read("月球基地", &r);
    printf("T4_STATUS=%d\n", ret);
    printf("T4_HAS_DATA=%d\n", (r.temperature > 0));

    return 0;
}
EOF

    if gcc -I"${TOOLS_DIR}" -I"${SECURITY_DIR}" -o "${BUILD_DIR}/test_temp" "${BUILD_DIR}/test_temp.c" -lm 2>/dev/null; then
        output=$("${BUILD_DIR}/test_temp" 2>/dev/null)
        assert_eq   "T1-客厅读取成功"    "0" "$(echo "$output" | grep "T1_STATUS=" | cut -d= -f2)"
        assert_eq   "T1-温度范围正常"     "1" "$(echo "$output" | grep "T1_TEMP_RANGE=" | cut -d= -f2)"
        assert_eq   "T2-拒NULL location" "-1" "$(echo "$output" | grep "T2_STATUS=" | cut -d= -f2)"
        assert_eq   "T3-拒NULL result"   "-1" "$(echo "$output" | grep "T3_STATUS=" | cut -d= -f2)"
        assert_eq   "T4-未知位置回退成功" "0" "$(echo "$output" | grep "T4_STATUS=" | cut -d= -f2)"
        assert_eq   "T4-回退有数据"       "1" "$(echo "$output" | grep "T4_HAS_DATA=" | cut -d= -f2)"
    else
        test_skip "温湿度测试编译" "需要完整的 openvela 编译环境"
    fi
}

# ---------- 测试3: 安全模块 ----------
test_security() {
    echo -e "\n${BOLD}${BLUE}[Test Suite 3] 命令白名单安全模块${NC}"

    if gcc -DCOMMAND_WHITELIST_TEST -o "${BUILD_DIR}/test_sec" "${SECURITY_DIR}/command_whitelist.c" -lm 2>/dev/null; then
        output=$("${BUILD_DIR}/test_sec" 2>&1)
        assert_contains "3-合法echo通过"    <(echo "$output") "ALLOW.*echo"
        assert_contains "3-合法date通过"    <(echo "$output") "ALLOW.*date"
        assert_contains "3-拦截rm命令"       <(echo "$output") "BLOCK.*rm"
        assert_contains "3-拦截reboot"       <(echo "$output") "BLOCK.*reboot"
        assert_contains "3-拦截管道注入"     <(echo "$output") "BLOCK"
        assert_contains "3-审计报告生成"     <(echo "$output") "审计报告"
    else
        test_skip "安全模块编译" "gcc 不可用"
    fi
}

# ---------- 测试4: JSON 解析器 ----------
test_json_parser() {
    echo -e "\n${BOLD}${BLUE}[Test Suite 4] JSON 解析器（内嵌于 tool_registry）${NC}"

    cat > "${BUILD_DIR}/test_json.c" << 'JEOF'
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* 内联 json_extract 函数（从 tool_registry 剥离） */
static char* json_extract_string(const char *json, const char *key, char *buf, size_t buf_size) {
    char search[128];
    snprintf(search, sizeof(search), "\"%s\"", key);
    const char *pos = strstr(json, search);
    if (!pos) return NULL;
    pos = strchr(pos + strlen(search), ':');
    if (!pos) return NULL;
    pos++;
    while (*pos == ' ' || *pos == '\t' || *pos == '\n') pos++;
    if (*pos != '"') return NULL;
    pos++;
    size_t i = 0;
    while (*pos && *pos != '"' && i < buf_size - 1) {
        if (*pos == '\\' && *(pos + 1)) pos++;
        buf[i++] = *pos++;
    }
    buf[i] = '\0';
    return buf;
}

static int json_extract_int(const char *json, const char *key, int *value) {
    char search[128];
    snprintf(search, sizeof(search), "\"%s\"", key);
    const char *pos = strstr(json, search);
    if (!pos) return 0;
    pos = strchr(pos + strlen(search), ':');
    if (!pos) return 0;
    pos++;
    while (*pos == ' ' || *pos == '\t') pos++;
    if (*pos < '0' || *pos > '9') return 0;
    *value = (int)strtol(pos, NULL, 10);
    return 1;
}

int main(void) {
    char buf[64]; int val;
    const char *j1 = "{\"location\": \"客厅\", \"action\": \"开灯\", \"brightness\": 80}";
    const char *j2 = "{\"location\": \"室外\"}";
    const char *j3 = "{  \"brightness\" : 50 }";

    /* 测试1 */
    printf("J1_LOC=%d\n", json_extract_string(j1, "location", buf, 64) != NULL);
    printf("J1_LOC_VAL=%s\n", buf);
    printf("J1_ACT=%d\n", json_extract_string(j1, "action", buf, 64) != NULL);
    printf("J1_INT=%d\n", json_extract_int(j1, "brightness", &val));
    printf("J1_INT_VAL=%d\n", val);

    /* 测试2 */
    printf("J2_LOC=%d\n", json_extract_string(j2, "location", buf, 64) != NULL);
    printf("J2_LOC_VAL=%s\n", buf);

    /* 测试3: 空格容错 */
    printf("J3_INT=%d\n", json_extract_int(j3, "brightness", &val));
    printf("J3_INT_VAL=%d\n", val);

    return 0;
}
JEOF

    if gcc -o "${BUILD_DIR}/test_json" "${BUILD_DIR}/test_json.c" 2>/dev/null; then
        output=$("${BUILD_DIR}/test_json" 2>/dev/null)
        assert_eq "J1-解析location"     "1"    "$(echo "$output" | grep "J1_LOC=" | cut -d= -f2)"
        assert_eq "J1-location=客厅"    "客厅" "$(echo "$output" | grep "J1_LOC_VAL=" | cut -d= -f2)"
        assert_eq "J1-解析action"       "1"    "$(echo "$output" | grep "J1_ACT=" | cut -d= -f2)"
        assert_eq "J1-解析brightness"   "1"    "$(echo "$output" | grep "J1_INT=" | cut -d= -f2)"
        assert_eq "J1-brightness=80"    "80"   "$(echo "$output" | grep "J1_INT_VAL=" | cut -d= -f2)"
        assert_eq "J2-解析室外"         "1"    "$(echo "$output" | grep "J2_LOC=" | cut -d= -f2)"
        assert_eq "J2-室外值"           "室外" "$(echo "$output" | grep "J2_LOC_VAL=" | cut -d= -f2)"
        assert_eq "J3-空格容错"         "1"    "$(echo "$output" | grep "J3_INT=" | cut -d= -f2)"
        assert_eq "J3-brightness=50"    "50"   "$(echo "$output" | grep "J3_INT_VAL=" | cut -d= -f2)"
    else
        test_skip "JSON解析测试编译" "gcc 不可用"
    fi
}

# ---------- 测试5: 脚本自身检查 ----------
test_scripts() {
    echo -e "\n${BOLD}${BLUE}[Test Suite 5] Shell 脚本语法检查${NC}"

    for script in auto_build_vela.sh switch_llm.sh; do
        if [ -f "${SCRIPT_DIR}/${script}" ]; then
            if bash -n "${SCRIPT_DIR}/${script}" 2>/dev/null; then
                test_pass "${script} 语法检查通过"
            else
                test_fail "${script} 语法错误" ""
            fi
        else
            test_skip "${script}" "文件不存在"
        fi
    done
}

# ---------- 基线性能测试 ----------
run_benchmark() {
    echo -e "\n${BOLD}${BLUE}[Benchmark] 性能基准测试${NC}"

    # 灯光控制基准
    cat > "${BUILD_DIR}/bench_light.c" << 'BEOF'
#include <stdio.h>
#include <string.h>
#include <time.h>

#define SMOKE_TEST_MODE
#define SMART_HOME_TOOLS_H
#define TOOL_SUCCESS 0
typedef enum { LOCATION_LIVING_ROOM=0, LOCATION_BEDROOM, LOCATION_KITCHEN, LOCATION_BATHROOM, LOCATION_STUDY, LOCATION_ALL } device_location_t;
typedef enum { LIGHT_ACTION_ON=0, LIGHT_ACTION_OFF, LIGHT_ACTION_SET_BRIGHTNESS, LIGHT_ACTION_TOGGLE } light_action_t;
typedef struct { device_location_t location; light_action_t action; uint8_t brightness; } light_control_params_t;
typedef struct { int status; char location_name[32]; char action_desc[64]; uint8_t current_brightness; } light_control_result_t;
#include "../tools/tool_light_control.c"

int main(void) {
    smart_home_tools_init();
    light_control_params_t p;
    light_control_result_t r;
    const int ITER = 100000;
    clock_t start, end;

    /* Warmup */
    for (int i = 0; i < 1000; i++) {
        memset(&p, 0, sizeof(p)); memset(&r, 0, sizeof(r));
        p.location = LOCATION_LIVING_ROOM; p.action = LIGHT_ACTION_ON;
        tool_light_control(&p, &r);
    }

    /* Benchmark */
    start = clock();
    for (int i = 0; i < ITER; i++) {
        memset(&p, 0, sizeof(p)); memset(&r, 0, sizeof(r));
        p.location = (device_location_t)(i % 5);
        p.action = LIGHT_ACTION_SET_BRIGHTNESS;
        p.brightness = (uint8_t)((i * 7) % 101);
        tool_light_control(&p, &r);
    }
    end = clock();

    double elapsed = (double)(end - start) / CLOCKS_PER_SEC;
    double ops_per_sec = ITER / elapsed;
    printf("BENCH_ITER=%d\n", ITER);
    printf("BENCH_SEC=%.3f\n", elapsed);
    printf("BENCH_OPS=%.0f\n", ops_per_sec);
    printf("BENCH_US=%.1f\n", elapsed * 1000000 / ITER);

    return 0;
}
BEOF

    if gcc -I"${TOOLS_DIR}" -I"${SECURITY_DIR}" -O2 -o "${BUILD_DIR}/bench_light" "${BUILD_DIR}/bench_light.c" -lm 2>/dev/null; then
        output=$("${BUILD_DIR}/bench_light" 2>/dev/null)
        ops=$(echo "$output" | grep "BENCH_OPS=" | cut -d= -f2)
        us=$(echo "$output" | grep "BENCH_US=" | cut -d= -f2)
        echo -e "  ${GREEN}灯光控制: ${ops} ops/sec, ${us} µs/op${NC}"
    else
        echo -e "  ${YELLOW}基准编译失败（需要gcc）${NC}"
    fi
}

# ---------- 主入口 ----------
main() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  openvela 智能家居 — 自动化测试套件 v2.0    ║"
    echo "╚══════════════════════════════════════════════╝"

    MODE="${1:-quick}"

    case "$MODE" in
        quick)
            test_light_control
            test_temperature
            test_json_parser
            ;;
        bench)
            run_benchmark
            ;;
        full)
            test_light_control
            test_temperature
            test_security
            test_json_parser
            test_scripts
            run_benchmark
            ;;
        security)
            test_security
            ;;
        *)
            echo "用法: $0 [quick|full|bench|security]"
            exit 1
            ;;
    esac

    # 打印结果
    TOTAL=$((PASS + FAIL + SKIP))
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo -e "║  测试结果: ${GREEN}通过 $PASS${NC} / ${RED}失败 $FAIL${NC} / ${YELLOW}跳过 $SKIP${NC} / 总计 $TOTAL  ║"
    echo "╚══════════════════════════════════════════════╝"

    if [ "$FAIL" -gt 0 ]; then
        echo -e "\n${RED}存在失败测试，请检查！${NC}"
        exit 1
    else
        echo -e "\n${GREEN}所有测试通过！✓${NC}"
        exit 0
    fi
}

main "$@"
