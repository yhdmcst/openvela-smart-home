/*
 * tool_light_control.c - 智能家居灯光控制 Tool
 *
 * 功能：接收自然语言解析后的参数，执行灯光控制操作。
 *
 * 支持的操作：
 *   - 开灯 (LIGHT_ACTION_ON)      — 打开指定位置灯光
 *   - 关灯 (LIGHT_ACTION_OFF)     — 关闭指定位置灯光
 *   - 调节亮度 (LIGHT_ACTION_SET_BRIGHTNESS) — 0-100
 *   - 切换开关 (LIGHT_ACTION_TOGGLE)
 *
 * 支持的位置：
 *   客厅 / 卧室 / 厨房 / 浴室 / 书房 / 室外 / 全屋
 *
 * openvela Tool 注册标准：
 *   1. 核心函数：tool_light_control(params, result) → int
 *   2. 入口函数：tool_light_control_entry(json_params, json_result, buf_size) → int
 *      负责 JSON 解析/序列化，Agent 通过此接口调用
 *   3. 模块初始化：smart_home_tools_init() → int
 *      注册到 agent_init_and_register_tools()
 *
 * v2.1 变更：
 *   - 修复全屋模式未知 action 静默忽略的 Bug
 *   - 新增 tool_light_control_entry 包装函数
 *   - 修复 get_action_description 静态 buffer 的线程安全问题
 *   - 修复 tool_get_location_enum NULL 指针崩溃
 *   - 统一返回值宏（0 → TOOL_SUCCESS）
 *   - 消除全屋/单区 switch 重复代码
 *   - 移除未使用的 time.h
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include "smart_home_tools.h"

/* ---------- 内部状态 ---------- */
typedef struct {
    bool    is_on;
    uint8_t brightness;
    bool    initialized;
} light_state_t;

#define MAX_LIGHT_ZONES LOCATION_COUNT
static light_state_t g_light_states[MAX_LIGHT_ZONES];
static bool g_module_initialized = false;

#ifndef SMOKE_TEST_MODE
extern int device_state_load(const char *filepath);
extern int device_state_save(const char *filepath);
extern int device_state_update_light(int loc_idx, bool is_on, uint8_t brightness);
extern int device_state_get_light(int loc_idx, bool *is_on, uint8_t *brightness);
#endif

/* ---------- 辅助函数 ---------- */

/*
 * get_location_name - 枚举 → 中文名
 */
static const char* get_location_name(device_location_t loc) {
    switch (loc) {
        case LOCATION_LIVING_ROOM: return "客厅";
        case LOCATION_BEDROOM:     return "卧室";
        case LOCATION_KITCHEN:     return "厨房";
        case LOCATION_BATHROOM:    return "浴室";
        case LOCATION_STUDY:       return "书房";
        case LOCATION_OUTDOOR:     return "室外";
        case LOCATION_ALL:         return "全屋";
        default:                   return "未知";
    }
}

/*
 * tool_get_location_enum - 中文名 → 枚举
 */
device_location_t tool_get_location_enum(const char *name) {
    if (name == NULL) return LOCATION_LIVING_ROOM;  /* 防御 NULL */
    if (strstr(name, "客厅") || strstr(name, "起居室"))  return LOCATION_LIVING_ROOM;
    if (strstr(name, "卧室") || strstr(name, "主卧"))    return LOCATION_BEDROOM;
    if (strstr(name, "厨房"))                            return LOCATION_KITCHEN;
    if (strstr(name, "浴室") || strstr(name, "卫生间"))   return LOCATION_BATHROOM;
    if (strstr(name, "书房") || strstr(name, "办公室"))   return LOCATION_STUDY;
    if (strstr(name, "室外") || strstr(name, "户外"))     return LOCATION_OUTDOOR;
    if (strstr(name, "全屋") || strstr(name, "所有"))     return LOCATION_ALL;
    return LOCATION_LIVING_ROOM;
}

/*
 * get_action_description - 操作 → 中文描述
 *
 * 修复：不再返回 static buffer 地址，改为写入调用者提供的 buffer，
 *       避免多线程竞争和悬垂指针问题。
 */
static void get_action_description(light_action_t action, uint8_t brightness,
                                   char *out_buf, size_t buf_size) {
    switch (action) {
        case LIGHT_ACTION_ON:
            snprintf(out_buf, buf_size, "打开灯光");
            break;
        case LIGHT_ACTION_OFF:
            snprintf(out_buf, buf_size, "关闭灯光");
            break;
        case LIGHT_ACTION_SET_BRIGHTNESS:
            snprintf(out_buf, buf_size, "调节亮度至 %d%%", brightness);
            break;
        case LIGHT_ACTION_TOGGLE:
            snprintf(out_buf, buf_size, "切换灯光开关");
            break;
        default:
            snprintf(out_buf, buf_size, "未知操作(%d)", (int)action);
            break;
    }
}

/*
 * apply_light_action - 对单个区域执行灯光操作
 *
 * 提取自原有的两套重复 switch，消除 DRY 违反。
 * 返回 true 表示操作有效，false 表示未知 action（仅全屋模式用到）。
 */
static bool apply_light_action(light_state_t *state, light_action_t action,
                               uint8_t brightness, bool verbose,
                               const char *loc_name) {
    switch (action) {
        case LIGHT_ACTION_ON:
            state->is_on = true;
            if (state->brightness == 0) state->brightness = 100;
            if (verbose) fprintf(stdout, "[LightControl] -> %s灯光已打开，亮度 %d%%\n",
                                 loc_name, state->brightness);
            return true;

        case LIGHT_ACTION_OFF:
            state->is_on      = false;
            state->brightness = 0;
            if (verbose) fprintf(stdout, "[LightControl] -> %s灯光已关闭\n", loc_name);
            return true;

        case LIGHT_ACTION_SET_BRIGHTNESS: {
            /* 边界截断已在调用方处理，这里做最终保护 */
            uint8_t b = (brightness > 100) ? 100 : brightness;
            state->brightness = b;
            state->is_on      = (b > 0);
            if (verbose) fprintf(stdout, "[LightControl] -> %s灯光亮度已调节至 %d%%\n",
                                 loc_name, state->brightness);
            return true;
        }

        case LIGHT_ACTION_TOGGLE:
            state->is_on = !state->is_on;
            if (state->is_on) {
                if (state->brightness == 0) state->brightness = 100;
                if (verbose) fprintf(stdout, "[LightControl] -> %s灯光已切换为【开启】，"
                                     "亮度 %d%%\n", loc_name, state->brightness);
            } else {
                state->brightness = 0;
                if (verbose) fprintf(stdout, "[LightControl] -> %s灯光已切换为【关闭】\n",
                                     loc_name);
            }
            return true;

        default:
            /* 未知操作 */
            return false;
    }
}

/* ---------- 初始化 ---------- */

int smart_home_tools_init(void) {
    if (g_module_initialized) {
        return TOOL_SUCCESS;  /* 幂等 */
    }

    fprintf(stdout, "[SmartHome] 初始化灯光控制模块...\n");

#ifndef SMOKE_TEST_MODE
    int loaded = device_state_load("/data/device_state.json");
    if (loaded == TOOL_SUCCESS) {
        for (int i = 0; i < MAX_LIGHT_ZONES; i++) {
            device_state_get_light(i, &g_light_states[i].is_on,
                                      &g_light_states[i].brightness);
            g_light_states[i].initialized = true;
        }
        fprintf(stdout, "[SmartHome] 已从 device_state.json 恢复上次状态\n");
    } else
#endif
    {
        for (int i = 0; i < MAX_LIGHT_ZONES; i++) {
            g_light_states[i].is_on       = false;
            g_light_states[i].brightness  = 0;
            g_light_states[i].initialized = true;
        }
#ifndef SMOKE_TEST_MODE
        fprintf(stdout, "[SmartHome] 使用默认初始状态\n");
#endif
    }

    g_module_initialized = true;
    fprintf(stdout, "[SmartHome] 灯光控制模块初始化完成 (共 %d 个区域)\n", MAX_LIGHT_ZONES);
    return TOOL_SUCCESS;
}

/* ---------- 核心Tool函数 ---------- */

/*
 * tool_light_control - 核心灯光控制
 *
 * @param params: 输入 (light_control_params_t)，调用方保证非 NULL
 * @param result: 输出 (light_control_result_t)，调用方保证非 NULL
 * @return:      TOOL_SUCCESS(0) / TOOL_ERR_PARAM(-1) / TOOL_ERR_IO(-2)
 *
 * 设计保证：所有路径均填充 result->status，Agent 可安全读取。
 */
int tool_light_control(const light_control_params_t *params,
                       light_control_result_t *result) {
    /* ---- 1. 参数校验 ---- */
    if (params == NULL) {
        fprintf(stderr, "[LightControl] 错误: params 为 NULL\n");
        if (result) result->status = TOOL_ERR_PARAM;
        return TOOL_ERR_PARAM;
    }
    if (result == NULL) {
        fprintf(stderr, "[LightControl] 错误: result 为 NULL\n");
        return TOOL_ERR_PARAM;
    }

    /* 防御性清零：确保所有字段有确定值 */
    memset(result, 0, sizeof(light_control_result_t));

    /* ---- 2. 状态校验 ---- */
    if (!g_module_initialized) {
        fprintf(stderr, "[LightControl] 错误: 模块未初始化\n");
        result->status = TOOL_ERR_IO;
        return TOOL_ERR_IO;
    }

    /* 位置合法性 */
    if (params->location < LOCATION_LIVING_ROOM ||
        (params->location > LOCATION_OUTDOOR && params->location != LOCATION_ALL)) {
        fprintf(stderr, "[LightControl] 错误: 无效位置 %d\n", (int)params->location);
        result->status = TOOL_ERR_PARAM;
        return TOOL_ERR_PARAM;
    }

    /* action 合法性（统一校验，消除全屋/单区不一致） */
    if (params->action < LIGHT_ACTION_ON || params->action > LIGHT_ACTION_TOGGLE) {
        fprintf(stderr, "[LightControl] 错误: 无效操作 %d\n", (int)params->action);
        result->status = TOOL_ERR_PARAM;
        return TOOL_ERR_PARAM;
    }

    /* ---- 3. 日志头 ---- */
    const char *loc_name = get_location_name(params->location);
    char act_desc[64];
    get_action_description(params->action, params->brightness, act_desc, sizeof(act_desc));

    fprintf(stdout, "[LightControl] ==================== 灯光控制 ====================\n");
    fprintf(stdout, "[LightControl] 位置: %s | 操作: %s\n", loc_name, act_desc);

    /* ---- 4. 执行操作 ---- */
    if (params->location == LOCATION_ALL) {
        /* 全屋：对所有常规区域执行同一操作 */
        fprintf(stdout, "[LightControl] 执行全屋操作（共 %d 个区域）...\n", LOCATION_COUNT);
        for (int i = 0; i < LOCATION_COUNT; i++) {
            apply_light_action(&g_light_states[i], params->action,
                              params->brightness, false, NULL);
        }
    } else {
        /* 单区域 */
        int idx = (int)params->location;
        apply_light_action(&g_light_states[idx], params->action,
                          params->brightness, true, loc_name);
    }

    /* ---- 5. 填充返回结果 ---- */
    if (params->location != LOCATION_ALL) {
        result->current_brightness = g_light_states[(int)params->location].brightness;
    } else {
        result->current_brightness = g_light_states[LOCATION_LIVING_ROOM].brightness;
    }

    strncpy(result->location_name, loc_name, sizeof(result->location_name) - 1);
    result->location_name[sizeof(result->location_name) - 1] = '\0';

    strncpy(result->action_desc, act_desc, sizeof(result->action_desc) - 1);
    result->action_desc[sizeof(result->action_desc) - 1] = '\0';

    result->status = TOOL_SUCCESS;

    /* ---- 6. 持久化 ---- */
#ifndef SMOKE_TEST_MODE
    if (params->location == LOCATION_ALL) {
        for (int i = 0; i < LOCATION_COUNT; i++) {
            device_state_update_light(i, g_light_states[i].is_on,
                                         g_light_states[i].brightness);
        }
    } else {
        int idx = (int)params->location;
        device_state_update_light(idx, g_light_states[idx].is_on,
                                     g_light_states[idx].brightness);
    }
    device_state_save("device_state.json");
#endif

    fprintf(stdout, "[LightControl] ==================== 执行完成 ====================\n");
    return TOOL_SUCCESS;
}

/* ---------- 调试/查询接口 ---------- */

int get_light_state(device_location_t loc, bool *is_on, uint8_t *brightness) {
    if (loc < 0 || loc >= MAX_LIGHT_ZONES) return TOOL_ERR_PARAM;
    if (is_on)      *is_on      = g_light_states[loc].is_on;
    if (brightness) *brightness = g_light_states[loc].brightness;
    return TOOL_SUCCESS;
}

/* ---------- openvela Tool Entry（注册入口） ---------- */

/*
 * tool_light_control_entry - openvela Agent 调用的标准入口
 *
 * 格式：
 *   输入 JSON: {"location":"客厅","action":"开灯","brightness":80}
 *   输出 JSON: {"status":0,"location_name":"客厅","action_desc":"...","current_brightness":100}
 *
 * 遵循 openvela Tool 注册规范：int tool_xxx_entry(json_in, json_out, buf_size)
 */
int tool_light_control_entry(const char *json_params,
                             char *json_result, size_t buf_size) {
    if (json_params == NULL || json_result == NULL || buf_size == 0) {
        return TOOL_ERR_PARAM;
    }

    /* 确保模块已初始化 */
    if (!g_module_initialized) {
        smart_home_tools_init();
    }

    /* 解析 JSON 参数到结构化类型 */
    light_control_params_t params;
    light_control_result_t  result;
    memset(&params, 0, sizeof(params));
    memset(&result, 0, sizeof(result));

    /* 简化的 JSON 解析（嵌入式环境不依赖第三方 JSON 库） */
    char buf[128];
    const char *loc_ptr, *act_ptr;

    /* 提取 location */
    loc_ptr = strstr(json_params, "\"location\"");
    if (loc_ptr) {
        loc_ptr = strchr(loc_ptr, ':');
        if (loc_ptr) {
            loc_ptr++;
            while (*loc_ptr == ' ' || *loc_ptr == '"' || *loc_ptr == '\t') loc_ptr++;
            size_t i = 0;
            while (*loc_ptr && *loc_ptr != '"' && i < sizeof(buf) - 1) buf[i++] = *loc_ptr++;
            buf[i] = '\0';
            params.location = tool_get_location_enum(buf);
        }
    } else {
        params.location = LOCATION_LIVING_ROOM;
    }

    /* 提取 action */
    act_ptr = strstr(json_params, "\"action\"");
    if (act_ptr) {
        act_ptr = strchr(act_ptr, ':');
        if (act_ptr) {
            act_ptr++;
            while (*act_ptr == ' ' || *act_ptr == '"' || *act_ptr == '\t') act_ptr++;
            size_t i = 0;
            while (*act_ptr && *act_ptr != '"' && i < sizeof(buf) - 1) buf[i++] = *act_ptr++;
            buf[i] = '\0';

            if (strstr(buf, "开灯"))       params.action = LIGHT_ACTION_ON;
            else if (strstr(buf, "关灯"))   params.action = LIGHT_ACTION_OFF;
            else if (strstr(buf, "调亮度")) params.action = LIGHT_ACTION_SET_BRIGHTNESS;
            else if (strstr(buf, "切换"))   params.action = LIGHT_ACTION_TOGGLE;
            else                           params.action = LIGHT_ACTION_ON;
        }
    } else {
        params.action = LIGHT_ACTION_ON;
    }

    /* 提取 brightness */
    {
        const char *bri_ptr = strstr(json_params, "\"brightness\"");
        if (bri_ptr) {
            bri_ptr = strchr(bri_ptr, ':');
            if (bri_ptr) {
                params.brightness = (uint8_t)atoi(bri_ptr + 1);
            }
        }
    }

    /* 调用核心函数 */
    int ret = tool_light_control(&params, &result);

    /* 序列化结果为 JSON */
    snprintf(json_result, buf_size,
             "{\"status\":%d,\"location_name\":\"%s\","
             "\"action_desc\":\"%s\",\"current_brightness\":%d}",
             result.status,
             result.location_name,
             result.action_desc,
             result.current_brightness);

    return ret;
}
