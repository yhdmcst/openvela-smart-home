/*
 * tool_environment_monitor.c - 环境感知与主动巡检模块
 *
 * 物理AI核心模块，实现：
 *   1. 多传感器模拟（光照/人体红外/门磁/空气质量/噪音）
 *   2. 定时主动巡检（非用户触发，Agent 自主决策）
 *   3. 模糊指令解析（"有点冷""太暗了" → 感知环境 → 决策执行）
 *   4. 异常检测与自动建议
 *
 * 设计理念：
 *   物理AI = 感知(Perceive) → 推理(Reason) → 决策(Decide) → 执行(Act)
 *   本模块覆盖"感知"和"推理"层
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include "smart_home_tools.h"

/* ---------- 传感器基础数据 ---------- */
typedef struct {
    float base_illuminance;    /* 基础光照 (lux) */
    float base_pm25;           /* 基础PM2.5 */
    float base_co2;            /* 基础CO2 */
    float base_noise;          /* 基础噪音 */
} sensor_profile_t;

static sensor_profile_t g_profiles[] = {
    /* 客厅 */   { 15000.0, 25.0, 500.0, 35.0 },
    /* 卧室 */   { 8000.0,  20.0, 450.0, 25.0 },
    /* 厨房 */   { 20000.0, 45.0, 600.0, 55.0 },
    /* 浴室 */   { 5000.0,  15.0, 480.0, 50.0 },
    /* 书房 */   { 12000.0, 18.0, 420.0, 20.0 },
    /* 室外 */   { 60000.0, 55.0, 420.0, 60.0 },
};

static bool g_sensor_initialized = false;
static uint32_t g_read_count = 0;

static const char* loc_name(int idx) {
    const char *names[] = {"客厅", "卧室", "厨房", "浴室", "书房", "室外"};
    return (idx >= 0 && idx < 6) ? names[idx] : "未知";
}

static void sensor_init(void) {
    if (g_sensor_initialized) return;
    srand((unsigned int)time(NULL));
    g_sensor_initialized = true;
    fprintf(stdout, "[EnvMonitor] 多传感器模块初始化完成 (光照/人体/门磁/PM2.5/CO2/噪音)\n");
}

/* ---------- 单传感器读取 ---------- */
int tool_sensor_read(device_location_t loc, sensor_data_t *data) {
    if (!data) return TOOL_ERR_PARAM;
    if (loc < 0 || loc >= LOCATION_COUNT) return TOOL_ERR_PARAM;
    sensor_init();

    sensor_profile_t *p = &g_profiles[loc];
    float noise_factor = ((float)(rand() % 100) / 100.0 - 0.5) * 0.4; /* ±20% */

    memset(data, 0, sizeof(*data));
    data->illuminance    = p->base_illuminance * (1.0 + noise_factor);
    data->motion_detected = (loc == LOCATION_LIVING_ROOM || loc == LOCATION_BEDROOM)
                            && (rand() % 10 < 7); /* 70%概率有人 */
    data->door_open       = (loc == LOCATION_OUTDOOR) ? false : (rand() % 20 == 0);
    data->window_open     = (loc == LOCATION_BATHROOM) ? (rand() % 3 == 0) : (rand() % 15 == 0);
    data->pm25            = p->base_pm25 * (0.8 + ((float)(rand() % 40) / 100.0));
    data->co2             = p->base_co2  * (0.9 + ((float)(rand() % 20) / 100.0));
    data->noise           = p->base_noise * (0.8 + ((float)(rand() % 40) / 100.0));

    /* 边界保护 */
    if (data->illuminance < 0)    data->illuminance = 0;
    if (data->pm25 < 0)           data->pm25 = 0;
    if (data->noise < 0)          data->noise = 0;

    time_t now = time(NULL);
    strftime(data->update_time, 31, "%H:%M:%S", localtime(&now));

    fprintf(stdout, "[Sensor] %s: 光照=%.0flux 有人=%s 门=%s 窗=%s PM2.5=%.1f CO2=%.0f 噪音=%.0fdB\n",
            loc_name(loc), data->illuminance,
            data->motion_detected ? "是" : "否",
            data->door_open ? "开" : "关",
            data->window_open ? "开" : "关",
            data->pm25, data->co2, data->noise);

    g_read_count++;
    return TOOL_SUCCESS;
}

/* ---------- 批量传感器读取 ---------- */
int tool_sensor_read_all(sensor_data_t *data_array, int *count) {
    if (!data_array || !count) return TOOL_ERR_PARAM;
    int success = 0;
    for (int i = 0; i < LOCATION_COUNT; i++) {
        if (tool_sensor_read((device_location_t)i, &data_array[i]) == TOOL_SUCCESS)
            success++;
    }
    *count = success;
    return (success > 0) ? TOOL_SUCCESS : TOOL_ERR_IO;
}

/* ---------- 模糊指令解析（物理AI关键能力） ---------- */
int tool_fuzzy_command_parse(const char *user_input, char *action_json, size_t buf_size) {
    if (!user_input || !action_json) return TOOL_ERR_PARAM;

    /*
     * 模糊指令映射表：
     *   "有点冷" / "好冷"  → 查温湿度 → 判断是否开暖气
     *   "太暗了" / "看不清" → 查光照 → 开灯或拉开窗帘
     *   "好热" / "太热了"  → 查温度 → 开空调或开窗
     *   "闷" / "不透气"    → 查CO2 → 开窗通风
     *   "吵" / "太吵了"    → 查噪音 → 关窗
     *   "有人吗"           → 查人体红外 → 报告
     */

    sensor_data_t sensors[LOCATION_COUNT];
    tool_sensor_read_all(sensors, &(int){0});

    /* 默认先查客厅 */
    sensor_data_t *s = &sensors[LOCATION_LIVING_ROOM];

    if (strstr(user_input, "冷") || strstr(user_input, "凉")) {
        float temp = 25.0; /* 模拟中从device_state读取 */
        if (temp < 20.0)
            snprintf(action_json, buf_size,
                "{\"intent\":\"climate\",\"action\":\"heat\",\"reason\":\"室温%.1f°C偏冷，建议开启暖气\"}", temp);
        else
            snprintf(action_json, buf_size,
                "{\"intent\":\"climate\",\"action\":\"none\",\"reason\":\"室温%.1f°C正常，无需调节\"}", temp);
        return TOOL_SUCCESS;
    }

    if (strstr(user_input, "热") || strstr(user_input, "烫")) {
        float temp = 28.0;
        if (temp > 27.0)
            snprintf(action_json, buf_size,
                "{\"intent\":\"climate\",\"action\":\"cool\",\"reason\":\"室温%.1f°C偏高，建议开启空调降温\"}", temp);
        else
            snprintf(action_json, buf_size,
                "{\"intent\":\"climate\",\"action\":\"none\",\"reason\":\"室温%.1f°C尚可接受\"}", temp);
        return TOOL_SUCCESS;
    }

    if (strstr(user_input, "暗") || strstr(user_input, "黑") || strstr(user_input, "看不清")) {
        if (s->illuminance < 3000)
            snprintf(action_json, buf_size,
                "{\"intent\":\"light\",\"action\":\"on\",\"reason\":\"光照仅%.0flux，自动开灯\",\"brightness\":80}", s->illuminance);
        else if (s->illuminance < 10000)
            snprintf(action_json, buf_size,
                "{\"intent\":\"curtain\",\"action\":\"open\",\"reason\":\"光照%.0flux偏低，拉开窗帘采光\"}", s->illuminance);
        else
            snprintf(action_json, buf_size,
                "{\"intent\":\"none\",\"reason\":\"光照%.0flux充足\"}", s->illuminance);
        return TOOL_SUCCESS;
    }

    if (strstr(user_input, "闷") || strstr(user_input, "不透气")) {
        if (s->co2 > 800)
            snprintf(action_json, buf_size,
                "{\"intent\":\"window\",\"action\":\"open\",\"reason\":\"CO2浓度%.0fppm偏高，开窗通风\"}", s->co2);
        else
            snprintf(action_json, buf_size,
                "{\"intent\":\"none\",\"reason\":\"CO2浓度%.0fppm正常\"}", s->co2);
        return TOOL_SUCCESS;
    }

    if (strstr(user_input, "吵") || strstr(user_input, "噪音")) {
        if (s->noise > 45)
            snprintf(action_json, buf_size,
                "{\"intent\":\"window\",\"action\":\"close\",\"reason\":\"噪音%.0fdB偏高，自动关窗降噪\"}", s->noise);
        else
            snprintf(action_json, buf_size,
                "{\"intent\":\"none\",\"reason\":\"噪音%.0fdB正常\"}", s->noise);
        return TOOL_SUCCESS;
    }

    if (strstr(user_input, "有人吗") || strstr(user_input, "谁在")) {
        int count = 0;
        for (int i = 0; i < LOCATION_COUNT; i++)
            if (sensors[i].motion_detected) count++;
        snprintf(action_json, buf_size,
            "{\"intent\":\"query\",\"answer\":\"检测到%d个区域有人活动\"}", count);
        return TOOL_SUCCESS;
    }

    if (strstr(user_input, "空气") || strstr(user_input, "PM") || strstr(user_input, "雾霾")) {
        if (s->pm25 > 75)
            snprintf(action_json, buf_size,
                "{\"intent\":\"purifier\",\"action\":\"on\",\"reason\":\"PM2.5=%.1fμg/m³超标，建议开启空气净化器\"}", s->pm25);
        else
            snprintf(action_json, buf_size,
                "{\"intent\":\"none\",\"reason\":\"PM2.5=%.1fμg/m³，空气质量良好\"}", s->pm25);
        return TOOL_SUCCESS;
    }

    /* 未匹配 */
    snprintf(action_json, buf_size, "{\"intent\":\"unknown\",\"message\":\"无法解析模糊指令\"}");
    return TOOL_ERR_PARAM;
}

/* ---------- ⭐ 主动环境巡检（物理AI核心：自主决策） ---------- */
int tool_environment_patrol(patrol_report_t *report) {
    if (!report) return TOOL_ERR_PARAM;

    sensor_init();
    memset(report, 0, sizeof(*report));

    fprintf(stdout, "\n[Patrol] ╔══════════════════════════════════╗\n");
    fprintf(stdout, "[Patrol] ║  🏠 主动环境巡检启动           ║\n");
    fprintf(stdout, "[Patrol] ║  Agent自主决策，无需用户触发    ║\n");
    fprintf(stdout, "[Patrol] ╚══════════════════════════════════╝\n\n");

    sensor_data_t sensors[LOCATION_COUNT];
    int count = 0;
    tool_sensor_read_all(sensors, &count);

    int actions = 0;
    bool anomaly = false;
    char buf[2048] = "";
    char sug[512] = "";

    /* 逐区域巡检并自动决策 */
    for (int i = 0; i < LOCATION_COUNT; i++) {
        sensor_data_t *s = &sensors[i];
        char line[256];

        snprintf(line, sizeof(line), "📍 %s: ", loc_name(i));

        /* 1. 光照 → 自动调节窗帘（物理AI：感知→执行） */
        if (i != LOCATION_OUTDOOR) {
            if (s->illuminance > 50000) {
                strcat(line, "☀️强光→自动关窗帘遮阳 | ");
                actions++;
                anomaly = true;
                strcat(sug, "• 建议为客厅安装遮光帘\n");
            } else if (s->illuminance < 2000 && s->motion_detected) {
                strcat(line, "🌙光照不足且有人→自动开灯 | ");
                actions++;
            } else {
                strcat(line, "光照正常 | ");
            }
        }

        /* 2. 人体红外 → 节能（物理AI：人走灯灭） */
        if (!s->motion_detected && i != LOCATION_OUTDOOR) {
            strcat(line, "🚶无人→建议关闭该区域设备 | ");
            strcat(sug, "• 节能建议：无人在场时自动关灯关空调\n");
            anomaly = true;
        } else if (s->motion_detected) {
            strcat(line, "👤有人活动 | ");
        }

        /* 3. PM2.5 → 空气净化 */
        if (s->pm25 > 75) {
            strcat(line, "⚠️PM2.5超标→建议开启空气净化器 | ");
            actions++;
            anomaly = true;
            strcat(sug, "• PM2.5超标，建议开启空气净化器\n");
        }

        /* 4. CO2 → 通风 */
        if (s->co2 > 1000) {
            strcat(line, "⚠️CO2过高→建议开窗通风 | ");
            strcat(sug, "• CO2浓度偏高，注意通风\n");
            anomaly = true;
        }

        /* 5. 门窗安全检查 */
        if (s->door_open && i != LOCATION_OUTDOOR) {
            strcat(line, "🚪门未关 | ");
            strcat(sug, "• 检测到未关闭的门\n");
            anomaly = true;
        }

        strcat(buf, line);
        strcat(buf, "\n");
    }

    /* 生成巡检报告 */
    snprintf(report->report, sizeof(report->report),
             "═══ 主动巡检报告 ═══\n"
             "%s\n"
             "共执行 %d 项自动调节 | 发现 %d 项异常",
             buf, actions, anomaly ? 1 : 0);

    snprintf(report->suggestions, sizeof(report->suggestions), "%s", sug);

    report->status          = TOOL_SUCCESS;
    report->action_count    = actions;
    report->anomaly_detected = anomaly;

    fprintf(stdout, "[Patrol] %s\n", report->report);
    if (anomaly)
        fprintf(stdout, "[Patrol] 💡 AI建议:\n%s\n", report->suggestions);
    fprintf(stdout, "[Patrol] ✅ 巡检完成\n\n");

    return TOOL_SUCCESS;
}
