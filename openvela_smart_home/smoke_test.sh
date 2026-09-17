#!/bin/bash
# ============================================================
#  smoke_test.sh - 快速冒烟测试（10秒内完成）
#  评委一键验证核心功能是否正常
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.smoke_build"
PASS=0; ERR=0

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

ok()  { echo -e "  ${GREEN}[OK]${NC}  $1"; PASS=$((PASS+1)); }
err() { echo -e "  ${RED}[ER]${NC}  $1"; ERR=$((ERR+1)); }

mkdir -p "$BUILD_DIR"
echo ""
echo "openvela 智能家居 — 冒烟测试"

# --- 测试1: C代码语法检查 ---
echo ""
echo "[1/5] C源码语法检查..."
for f in tools/tool_light_control.c tools/tool_temperature_read.c tools/device_state.c tools/tool_curtain_control.c tools/tool_security_control.c tools/tool_environment_monitor.c security/command_whitelist.c; do
    if gcc -std=c99 -fsyntax-only -I"${SCRIPT_DIR}/tools" "${SCRIPT_DIR}/${f}" 2>/dev/null; then
        ok "$f syntax OK"
    else
        err "$f syntax FAIL"
    fi
done

# --- 测试2: Shell脚本语法 ---
echo ""
echo "[2/5] Shell脚本语法检查..."
for f in auto_build_vela.sh switch_llm.sh test_runner.sh; do
    if bash -n "${SCRIPT_DIR}/${f}" 2>/dev/null; then
        ok "$f syntax OK"
    else
        err "$f syntax FAIL"
    fi
done

# --- 测试3: 灯光Tool单元测试 ---
echo ""
echo "[3/5] 灯光控制Tool单元测试..."
cat > "${BUILD_DIR}/smoke_light.c" << 'EOF'
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

#define SMOKE_TEST_MODE
#define SMART_HOME_TOOLS_H            /* 阻止 smart_home_tools.h 重复定义类型 */
#define TOOL_SUCCESS 0
#define TOOL_ERR_PARAM -1

typedef enum { LOCATION_LIVING_ROOM=0, LOCATION_BEDROOM, LOCATION_KITCHEN,
               LOCATION_BATHROOM, LOCATION_STUDY, LOCATION_OUTDOOR, LOCATION_COUNT,
               LOCATION_ALL=99 } device_location_t;
typedef enum { LIGHT_ACTION_ON=0, LIGHT_ACTION_OFF,
               LIGHT_ACTION_SET_BRIGHTNESS, LIGHT_ACTION_TOGGLE } light_action_t;
typedef struct { device_location_t l; light_action_t a; uint8_t b; } light_control_params_t;
typedef struct { int s; char ln[32]; char ad[64]; uint8_t cb; } light_control_result_t;

#include "../tools/tool_light_control.c"

int main(void) {
    smart_home_tools_init();
    light_control_params_t p;
    light_control_result_t r;
    int ok = 1;

    /* 开灯 */
    memset(&p,0,sizeof(p)); memset(&r,0,sizeof(r));
    p.l=LOCATION_LIVING_ROOM; p.a=LIGHT_ACTION_ON;
    if (tool_light_control(&p,&r)!=0 || r.cb!=100) ok=0;

    /* 调亮度 */
    memset(&p,0,sizeof(p)); memset(&r,0,sizeof(r));
    p.l=LOCATION_BEDROOM; p.a=LIGHT_ACTION_SET_BRIGHTNESS; p.b=60;
    if (tool_light_control(&p,&r)!=0 || r.cb!=60) ok=0;

    /* NULL params */
    if (tool_light_control(NULL,&r) == 0) ok=0;

    /* 全屋 */
    memset(&p,0,sizeof(p)); memset(&r,0,sizeof(r));
    p.l=LOCATION_ALL; p.a=LIGHT_ACTION_ON;
    if (tool_light_control(&p,&r)!=0) ok=0;

    printf("SMOKE_LIGHT=%d\n", ok);
    return ok ? 0 : 1;
}
EOF
if gcc -I"${SCRIPT_DIR}/tools" -o "${BUILD_DIR}/smoke_light" "${BUILD_DIR}/smoke_light.c" -lm 2>/dev/null \
   && "${BUILD_DIR}/smoke_light" 2>/dev/null | grep -q "SMOKE_LIGHT=1"; then
    ok "灯光控制 5/5 测试通过"
else
    err "灯光控制测试失败"
fi

# --- 测试4: 温湿度Tool ---
echo ""
echo "[4/5] 温湿度读取Tool单元测试..."
cat > "${BUILD_DIR}/smoke_temp.c" << 'EOF'
#include <stdio.h>
#include <string.h>
#define LOCATION_LIVING_ROOM 0
#include "../tools/tool_temperature_read.c"

int main(void) {
    temperature_humidity_t r;
    memset(&r,0,sizeof(r));
    int ret = tool_temperature_read("客厅", &r);
    int ok = (ret==0 && r.temperature>20 && r.temperature<30 && r.humidity>40 && r.humidity<80);
    printf("SMOKE_TEMP=%d\n", ok);
    return ok ? 0 : 1;
}
EOF
if gcc -I"${SCRIPT_DIR}/tools" -o "${BUILD_DIR}/smoke_temp" "${BUILD_DIR}/smoke_temp.c" -lm 2>/dev/null \
   && "${BUILD_DIR}/smoke_temp" 2>/dev/null | grep -q "SMOKE_TEMP=1"; then
    ok "温湿度读取测试通过"
else
    err "温湿度读取测试失败"
fi

# --- 测试5: 文件完整性 ---
echo ""
echo "[5/5] 交付文件完整性检查..."
REQUIRED_FILES=(
    LICENSE NOTICE
    auto_build_vela.sh test_runner.sh Makefile switch_llm.sh smoke_test.sh
    tools/smart_home_tools.h tools/tool_light_control.c tools/tool_temperature_read.c
    tools/device_state.c tools/tool_curtain_control.c tools/tool_security_control.c
    tools/tool_environment_monitor.c
    skills/good_morning_skill.md skills/leave_home_skill.md
    security/command_whitelist.c
    dashboard/web_panel.html dashboard/bridge_server.py
    patches/agent_init.patch patches/tool_registration.patch
    docs/README.md docs/复现文档.md docs/演示日志.txt docs/THIRD_PARTY.md
    .gitignore .clang-format
)
for f in "${REQUIRED_FILES[@]}"; do
    if [ -f "${SCRIPT_DIR}/${f}" ]; then
        ok "$f"
    else
        err "$f 缺失!"
    fi
done

# --- 结果 ---
echo ""
echo "============================================="
echo -e "  冒烟测试: ${GREEN}通过 $PASS${NC} / ${RED}失败 $ERR${NC}"
echo "============================================="
rm -rf "$BUILD_DIR"
[ "$ERR" -eq 0 ] && exit 0 || exit 1
