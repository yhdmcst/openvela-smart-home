/*
 * tool_smart_home.c - 智能家居 Tool 包装器
 *
 * 将自定义的智能家居 Tool（灯光、温湿度、窗帘、安防等）
 * 注册到 AI Agent 的 tool_registry 中，使 LLM 可通过 ReAct 循环调用。
 *
 * Copyright (C) 2026 Xiaomi Corporation
 */

#include "tools/tool_registry.h"
#include "smart_home_tools.h"
#include "cJSON.h"

#include <string.h>
#include <stdio.h>

/* ================================================================
 *  灯光控制 Tool
 * ================================================================ */
static int tool_light_execute(const char *input_json, char *output,
                              size_t output_size)
{
    return tool_light_control_entry(input_json, output, output_size);
}

/* ================================================================
 *  温湿度读取 Tool
 * ================================================================ */
static int tool_temp_execute(const char *input_json, char *output,
                             size_t output_size)
{
    return tool_temperature_read_entry(input_json, output, output_size);
}

/* ================================================================
 *  窗帘控制 Tool
 * ================================================================ */
static int tool_curtain_execute(const char *input_json, char *output,
                                size_t output_size)
{
    /* 解析 JSON 参数 */
    cJSON *json = cJSON_Parse(input_json);
    if (!json) {
        snprintf(output, output_size,
                 "{\"status\":-1,\"error\":\"invalid JSON\"}");
        return OK;
    }

    cJSON *loc = cJSON_GetObjectItem(json, "location");
    cJSON *act = cJSON_GetObjectItem(json, "action");
    cJSON *pos = cJSON_GetObjectItem(json, "position");

    curtain_control_params_t params;
    memset(&params, 0, sizeof(params));
    params.location = loc ? tool_get_location_enum(loc->valuestring)
                          : LOCATION_LIVING_ROOM;
    params.action   = CURTAIN_ACTION_OPEN;
    params.position = 100;

    if (act) {
        if (strstr(act->valuestring, "开"))
            params.action = CURTAIN_ACTION_OPEN;
        else if (strstr(act->valuestring, "关"))
            params.action = CURTAIN_ACTION_CLOSE;
        else if (strstr(act->valuestring, "停"))
            params.action = CURTAIN_ACTION_STOP;
        else if (strstr(act->valuestring, "位置") || strstr(act->valuestring, "百叶"))
            params.action = CURTAIN_ACTION_SET_POSITION;
    }
    if (pos) params.position = (uint8_t)pos->valuedouble;

    curtain_control_result_t result;
    memset(&result, 0, sizeof(result));
    tool_curtain_control(&params, &result);

    cJSON_Delete(json);

    cJSON *out = cJSON_CreateObject();
    cJSON_AddNumberToObject(out, "status", result.status);
    cJSON_AddStringToObject(out, "location", result.location_name);
    cJSON_AddStringToObject(out, "action", result.action_desc);
    cJSON_AddNumberToObject(out, "position", result.current_position);
    cJSON_AddBoolToObject(out, "is_moving", result.is_moving);

    char *str = cJSON_PrintUnformatted(out);
    snprintf(output, output_size, "%s", str ? str : "{}");
    free(str);
    cJSON_Delete(out);
    return OK;
}

/* ================================================================
 *  安防控制 Tool
 * ================================================================ */
static int tool_security_execute(const char *input_json, char *output,
                                 size_t output_size)
{
    cJSON *json = cJSON_Parse(input_json);
    if (!json) {
        snprintf(output, output_size,
                 "{\"status\":-1,\"error\":\"invalid JSON\"}");
        return OK;
    }

    cJSON *act = cJSON_GetObjectItem(json, "action");
    cJSON *mod = cJSON_GetObjectItem(json, "mode");

    security_action_t action = SECURITY_ACTION_CHECK;
    security_mode_t   mode  = SECURITY_MODE_HOME;

    if (act) {
        if (strstr(act->valuestring, "布防"))
            action = SECURITY_ACTION_ARM;
        else if (strstr(act->valuestring, "撤防"))
            action = SECURITY_ACTION_DISARM;
        else if (strstr(act->valuestring, "报警"))
            action = SECURITY_ACTION_ALERT;
    }
    if (mod) {
        if (strstr(mod->valuestring, "在家"))
            mode = SECURITY_MODE_HOME;
        else if (strstr(mod->valuestring, "离家"))
            mode = SECURITY_MODE_AWAY;
        else if (strstr(mod->valuestring, "夜间"))
            mode = SECURITY_MODE_NIGHT;
    }

    security_control_result_t result;
    memset(&result, 0, sizeof(result));
    tool_security_control(action, mode, &result);

    cJSON_Delete(json);

    cJSON *out = cJSON_CreateObject();
    cJSON_AddNumberToObject(out, "status", result.status);
    cJSON_AddStringToObject(out, "status_desc", result.status_desc);
    cJSON_AddBoolToObject(out, "alarm_triggered", result.alarm_triggered);
    cJSON_AddNumberToObject(out, "mode", result.current_mode);

    char *str = cJSON_PrintUnformatted(out);
    snprintf(output, output_size, "%s", str ? str : "{}");
    free(str);
    cJSON_Delete(out);
    return OK;
}

/* ================================================================
 *  多传感器读取 Tool
 * ================================================================ */
static int tool_sensor_execute(const char *input_json, char *output,
                               size_t output_size)
{
    cJSON *json = cJSON_Parse(input_json);
    if (!json) {
        snprintf(output, output_size,
                 "{\"status\":-1,\"error\":\"invalid JSON\"}");
        return OK;
    }

    cJSON *loc = cJSON_GetObjectItem(json, "location");
    cJSON *all = cJSON_GetObjectItem(json, "all");

    cJSON_Delete(json);

    cJSON *out = cJSON_CreateObject();

    if (all && all->valueint) {
        /* 读取所有位置 */
        sensor_data_t data[LOCATION_COUNT];
        int count = 0;
        for (int i = 0; i < LOCATION_COUNT; i++) {
            tool_sensor_read((device_location_t)i, &data[i]);
        }
        count = LOCATION_COUNT;
        cJSON_AddNumberToObject(out, "count", count);
        cJSON *arr = cJSON_AddArrayToObject(out, "sensors");
        for (int i = 0; i < count; i++) {
            cJSON *item = cJSON_CreateObject();
            cJSON_AddNumberToObject(item, "illuminance", data[i].illuminance);
            cJSON_AddBoolToObject(item, "motion_detected", data[i].motion_detected);
            cJSON_AddBoolToObject(item, "door_open", data[i].door_open);
            cJSON_AddBoolToObject(item, "window_open", data[i].window_open);
            cJSON_AddNumberToObject(item, "pm25", data[i].pm25);
            cJSON_AddNumberToObject(item, "co2", data[i].co2);
            cJSON_AddNumberToObject(item, "noise", data[i].noise);
            cJSON_AddItemToArray(arr, item);
        }
    } else {
        /* 读取指定位置 */
        device_location_t location = loc ? tool_get_location_enum(loc->valuestring)
                                        : LOCATION_LIVING_ROOM;
        sensor_data_t data;
        memset(&data, 0, sizeof(data));
        int ret = tool_sensor_read(location, &data);

        cJSON_AddNumberToObject(out, "status", ret);
        cJSON_AddNumberToObject(out, "illuminance", data.illuminance);
        cJSON_AddBoolToObject(out, "motion_detected", data.motion_detected);
        cJSON_AddBoolToObject(out, "door_open", data.door_open);
        cJSON_AddBoolToObject(out, "window_open", data.window_open);
        cJSON_AddNumberToObject(out, "pm25", data.pm25);
        cJSON_AddNumberToObject(out, "co2", data.co2);
        cJSON_AddNumberToObject(out, "noise", data.noise);
    }

    char *str = cJSON_PrintUnformatted(out);
    snprintf(output, output_size, "%s", str ? str : "{}");
    free(str);
    cJSON_Delete(out);
    return OK;
}

/* ================================================================
 *  环境巡检 Tool
 * ================================================================ */
static int tool_patrol_execute(const char *input_json, char *output,
                               size_t output_size)
{
    patrol_report_t report;
    memset(&report, 0, sizeof(report));
    tool_environment_patrol(&report);

    cJSON *out = cJSON_CreateObject();
    cJSON_AddNumberToObject(out, "status", report.status);
    cJSON_AddStringToObject(out, "report", report.report);
    cJSON_AddNumberToObject(out, "action_count", report.action_count);
    cJSON_AddBoolToObject(out, "anomaly_detected", report.anomaly_detected);
    cJSON_AddStringToObject(out, "suggestions", report.suggestions);

    char *str = cJSON_PrintUnformatted(out);
    snprintf(output, output_size, "%s", str ? str : "{}");
    free(str);
    cJSON_Delete(out);
    return OK;
}

/* ================================================================
 *  模糊指令解析 Tool
 * ================================================================ */
static int tool_fuzzy_execute(const char *input_json, char *output,
                              size_t output_size)
{
    cJSON *json = cJSON_Parse(input_json);
    if (!json) {
        snprintf(output, output_size,
                 "{\"status\":-1,\"error\":\"invalid JSON\"}");
        return OK;
    }

    cJSON *text = cJSON_GetObjectItem(json, "text");
    if (!text || !text->valuestring) {
        cJSON_Delete(json);
        snprintf(output, output_size,
                 "{\"status\":-1,\"error\":\"missing 'text' field\"}");
        return OK;
    }

    char action_buf[512];
    memset(action_buf, 0, sizeof(action_buf));
    int ret = tool_fuzzy_command_parse(text->valuestring, action_buf,
                                       sizeof(action_buf));
    cJSON_Delete(json);

    cJSON *out = cJSON_CreateObject();
    cJSON_AddNumberToObject(out, "status", ret);
    cJSON_AddStringToObject(out, "parsed_action", action_buf);

    char *str = cJSON_PrintUnformatted(out);
    snprintf(output, output_size, "%s", str ? str : "{}");
    free(str);
    cJSON_Delete(out);
    return OK;
}

/* ================================================================
 *  注册函数：从 tool_registry_init() 调用
 * ================================================================ */
void register_smart_home_tools(void)
{
    /* 初始化智能家居工具模块 */
    smart_home_tools_init();

    /* 1. 灯光控制 */
    REGISTER_TOOL(
        "light_control",
        "Control smart lights: turn on/off, adjust brightness (0-100), "
        "toggle. Supports locations: 客厅(living room), 卧室(bedroom), "
        "厨房(kitchen), 浴室(bathroom), 书房(study), 全屋(all).",
        TOOL_SCHEMA_BEGIN()
            TOOL_PARAM_STR("location",
                "Light location: 客厅/卧室/厨房/浴室/书房/全屋")
            ","
            TOOL_PARAM_STR("action",
                "Action: 开灯(turn on)/关灯(turn off)/调亮度(set brightness)"
                "/切换(toggle)")
            ","
            TOOL_PARAM_NUM("brightness",
                "Brightness level 0-100 (only for 调亮度)")
            TOOL_SCHEMA_END_REQUIRED("\"location\",\"action\""),
        tool_light_execute);

    /* 2. 温湿度读取 */
    REGISTER_TOOL(
        "read_temperature",
        "Read temperature (Celsius) and humidity (%) at a location. "
        "Supports: 客厅/卧室/厨房/浴室/书房/室外.",
        TOOL_SCHEMA_BEGIN()
            TOOL_PARAM_STR("location",
                "Location: 客厅/卧室/厨房/浴室/书房/室外")
            TOOL_SCHEMA_END_REQUIRED("\"location\""),
        tool_temp_execute);

    /* 3. 窗帘控制 */
    REGISTER_TOOL(
        "curtain_control",
        "Control smart curtains: open/close/set position. "
        "Supports: 客厅/卧室/厨房/浴室/书房.",
        TOOL_SCHEMA_BEGIN()
            TOOL_PARAM_STR("location",
                "Curtain location: 客厅/卧室/厨房/浴室/书房")
            ","
            TOOL_PARAM_STR("action",
                "Action: 开(open)/关(close)/停(stop)/设位置(set position)")
            ","
            TOOL_PARAM_NUM("position",
                "Position 0-100 (only for 设位置)")
            TOOL_SCHEMA_END_REQUIRED("\"location\",\"action\""),
        tool_curtain_execute);

    /* 4. 安防控制 */
    REGISTER_TOOL(
        "security_control",
        "Control home security system: arm/disarm/alert/check. "
        "Modes: 在家(home)/离家(away)/夜间(night).",
        TOOL_SCHEMA_BEGIN()
            TOOL_PARAM_STR("action",
                "Action: 布防(arm)/撤防(disarm)/报警(alert)/检查(check)")
            ","
            TOOL_PARAM_STR("mode",
                "Mode: 在家(home)/离家(away)/夜间(night)")
            TOOL_SCHEMA_END_REQUIRED("\"action\""),
        tool_security_execute);

    /* 5. 多传感器读取 */
    REGISTER_TOOL(
        "sensor_read",
        "Read environment sensor data: light, motion, door/window status, "
        "PM2.5, CO2, noise. Set 'all'=true to read all locations.",
        TOOL_SCHEMA_BEGIN()
            TOOL_PARAM_STR("location",
                "Location: 客厅/卧室/厨房/浴室/书房")
            ","
            TOOL_PARAM_BOOL("all",
                "Set true to read all locations at once")
            TOOL_SCHEMA_END_REQUIRED(""),
        tool_sensor_execute);

    /* 6. 环境巡检 */
    REGISTER_TOOL_NO_PARAMS(
        "environment_patrol",
        "Auto-inspect all rooms for anomalies (open windows, lights on, "
        "temperature/humidity, etc.) and provide suggestions.",
        tool_patrol_execute);

    /* 7. 模糊指令解析 */
    REGISTER_TOOL(
        "fuzzy_command",
        "Parse a fuzzy natural language command into a structured action. "
        "Input is Chinese text like '太热了' or '把客厅灯打开'.",
        TOOL_SCHEMA_BEGIN()
            TOOL_PARAM_STR("text",
                "Natural language command in Chinese")
            TOOL_SCHEMA_END_REQUIRED("\"text\""),
        tool_fuzzy_execute);
}
