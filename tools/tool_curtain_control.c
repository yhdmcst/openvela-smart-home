/*
 * tool_curtain_control.c - 窗帘控制 Tool
 *
 * 功能：控制智能窗帘的开合、停止和位置调节（0-100%）。
 *       模拟器版本维护内存状态，真实部署时替换为电机驱动。
 *
 * 物理AI特性：根据光照传感器数据自动调节窗帘位置，
 *             实现"感知→决策→执行"闭环。
 */
#include <stdio.h>
#include <string.h>
#include "smart_home_tools.h"

/* ---------- 内部状态 ---------- */
typedef struct {
    bool    is_open;
    uint8_t position;     /* 0=全关, 100=全开 */
    bool    is_moving;
    bool    initialized;
} curtain_state_t;

static curtain_state_t g_curtains[LOCATION_COUNT];
static bool g_curtain_initialized = false;

/* ---------- 辅助 ---------- */
static const char* loc_name_str(int idx) {
    const char *names[] = {"客厅", "卧室", "厨房", "浴室", "书房", "室外"};
    return (idx >= 0 && idx < 6) ? names[idx] : "未知";
}

/* ---------- 初始化 ---------- */
static void curtain_init(void) {
    if (g_curtain_initialized) return;
    for (int i = 0; i < LOCATION_COUNT; i++) {
        g_curtains[i].is_open      = (i != LOCATION_BATHROOM); /* 浴室默认关 */
        g_curtains[i].position     = g_curtains[i].is_open ? 100 : 0;
        g_curtains[i].is_moving    = false;
        g_curtains[i].initialized  = true;
    }
    g_curtain_initialized = true;
    fprintf(stdout, "[Curtain] 窗帘控制模块初始化完成 (%d 区域)\n", LOCATION_COUNT);
}

/* ---------- 核心接口 ---------- */
int tool_curtain_control(const curtain_control_params_t *params,
                         curtain_control_result_t *result) {
    if (!params || !result) return TOOL_ERR_PARAM;

    curtain_init();

    /* 确定操作范围 */
    int start = 0, end = LOCATION_COUNT;
    if (params->location != LOCATION_ALL) {
        if (params->location < 0 || params->location >= LOCATION_COUNT)
            return TOOL_ERR_PARAM;
        start = params->location;
        end   = start + 1;
    }

    fprintf(stdout, "[Curtain] ========== 窗帘控制 ==========\n");
    const char *act_name = "未知";

    for (int i = start; i < end; i++) {
        switch (params->action) {
            case CURTAIN_ACTION_OPEN:
                g_curtains[i].is_open  = true;
                g_curtains[i].position = 100;
                g_curtains[i].is_moving = true;
                act_name = "打开";
                fprintf(stdout, "[Curtain] %s窗帘 → 打开\n", loc_name_str(i));
                break;
            case CURTAIN_ACTION_CLOSE:
                g_curtains[i].is_open  = false;
                g_curtains[i].position = 0;
                g_curtains[i].is_moving = true;
                act_name = "关闭";
                fprintf(stdout, "[Curtain] %s窗帘 → 关闭\n", loc_name_str(i));
                break;
            case CURTAIN_ACTION_STOP:
                g_curtains[i].is_moving = false;
                act_name = "停止";
                fprintf(stdout, "[Curtain] %s窗帘 → 停止\n", loc_name_str(i));
                break;
            case CURTAIN_ACTION_SET_POSITION:
                g_curtains[i].position = params->position;
                g_curtains[i].is_open  = (params->position > 0);
                g_curtains[i].is_moving = true;
                act_name = "定位";
                fprintf(stdout, "[Curtain] %s窗帘 → %d%%\n", loc_name_str(i), params->position);
                break;
        }
    }

    memset(result, 0, sizeof(*result));
    int ref = (params->location != LOCATION_ALL) ? params->location : LOCATION_LIVING_ROOM;
    result->status           = TOOL_SUCCESS;
    result->current_position  = g_curtains[ref].position;
    result->is_moving         = g_curtains[ref].is_moving;
    strncpy(result->location_name, loc_name_str(ref), 31);
    snprintf(result->action_desc, 63, "%s窗帘", act_name);

    fprintf(stdout, "[Curtain] ========== 执行完成 ==========\n");
    return TOOL_SUCCESS;
}

/* 根据光照自动调节（物理AI：感知→决策→执行） */
int tool_curtain_auto_adjust(device_location_t loc, float illuminance) {
    curtain_init();
    if (loc < 0 || loc >= LOCATION_COUNT) return TOOL_ERR_PARAM;

    uint8_t target;
    if (illuminance > 50000)       target = 20;   /* 强光：遮阳 */
    else if (illuminance > 20000)  target = 50;   /* 明亮：半开 */
    else if (illuminance > 5000)   target = 80;   /* 适中：大半开 */
    else if (illuminance > 1000)   target = 100;  /* 偏暗：全开采光 */
    else                           target = 100;  /* 很暗：全开 */

    g_curtains[loc].position = target;
    g_curtains[loc].is_open  = (target > 0);

    fprintf(stdout, "[Curtain-Auto] %s光照=%.0f lux → 窗帘自动调节至 %d%%\n",
            loc_name_str(loc), illuminance, target);
    return TOOL_SUCCESS;
}
