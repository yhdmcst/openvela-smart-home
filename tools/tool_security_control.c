/*
 * tool_security_control.c - 安防控制 Tool
 *
 * 功能：管理家庭安防状态（布防/撤防/离家模式/夜间模式），
 *       检查门窗状态，触发报警。
 *
 * 物理AI特性：
 *   - 离家模式：自动巡检全屋 → 关灯关窗帘 → 启动安防
 *   - 多设备协同：灯+窗帘+门锁+安防 联动
 */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "smart_home_tools.h"

/* ---------- 内部状态 ---------- */
typedef struct {
    bool    door_locked;
    bool    window_closed;
    bool    initialized;
} zone_security_t;

static zone_security_t g_zones[LOCATION_COUNT];
static security_mode_t g_current_mode = SECURITY_MODE_OFF;
static bool g_security_initialized = false;

static const char* mode_name(security_mode_t m) {
    switch (m) {
        case SECURITY_MODE_HOME:  return "在家模式";
        case SECURITY_MODE_AWAY:  return "离家模式";
        case SECURITY_MODE_NIGHT: return "夜间模式";
        case SECURITY_MODE_OFF:   return "已关闭";
        default:                  return "未知";
    }
}

static void security_init(void) {
    if (g_security_initialized) return;
    for (int i = 0; i < LOCATION_COUNT; i++) {
        g_zones[i].door_locked   = true;
        g_zones[i].window_closed = (i != LOCATION_BATHROOM); /* 浴室微开通风 */
        g_zones[i].initialized   = true;
    }
    g_security_initialized = true;
    fprintf(stdout, "[Security] 安防模块初始化完成\n");
}

/* ---------- 核心接口 ---------- */
int tool_security_control(security_action_t action, security_mode_t mode,
                          security_control_result_t *result) {
    if (!result) return TOOL_ERR_PARAM;
    security_init();
    memset(result, 0, sizeof(*result));

    fprintf(stdout, "[Security] ========== 安防控制 ==========\n");

    switch (action) {
        case SECURITY_ACTION_ARM:
            g_current_mode = mode;
            fprintf(stdout, "[Security] 安防模式 → %s\n", mode_name(mode));
            /* 离家模式：自动锁门关窗 */
            if (mode == SECURITY_MODE_AWAY) {
                for (int i = 0; i < LOCATION_COUNT; i++) {
                    g_zones[i].door_locked   = true;
                    g_zones[i].window_closed = true;
                }
                fprintf(stdout, "[Security] 离家模式：全屋门窗已自动锁闭\n");
            }
            break;
        case SECURITY_ACTION_DISARM:
            g_current_mode = SECURITY_MODE_OFF;
            fprintf(stdout, "[Security] 安防已撤防\n");
            break;
        case SECURITY_ACTION_ALERT:
            fprintf(stdout, "[Security] ⚠️ 警报触发！\n");
            break;
        case SECURITY_ACTION_CHECK:
            fprintf(stdout, "[Security] 当前模式: %s\n", mode_name(g_current_mode));
            break;
    }

    result->status       = TOOL_SUCCESS;
    result->current_mode  = g_current_mode;

    /* 填充各区域状态 */
    int issues = 0;
    for (int i = 0; i < LOCATION_COUNT; i++) {
        result->door_locked[i]   = g_zones[i].door_locked;
        result->window_closed[i] = g_zones[i].window_closed;
        if (!g_zones[i].door_locked)   issues++;
        if (!g_zones[i].window_closed) issues++;
    }

    snprintf(result->status_desc, 127,
             "%s | 门窗异常: %d 处",
             mode_name(g_current_mode), issues);

    fprintf(stdout, "[Security] ========== 执行完成 ==========\n");
    return TOOL_SUCCESS;
}

/* 全屋安全检查 */
int tool_security_check_all(security_control_result_t *result) {
    return tool_security_control(SECURITY_ACTION_CHECK, g_current_mode, result);
}
