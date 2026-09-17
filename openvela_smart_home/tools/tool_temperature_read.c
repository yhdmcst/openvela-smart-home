/*
 * tool_temperature_read.c - 智能家居温湿度读取 Tool
 *
 * 功能：读取指定位置的温度和湿度数据。
 *       模拟器版本返回带统计波动的模拟数据。
 *       真实部署时替换为 DHT22/SHT30 传感器驱动。
 *
 * 支持的位置：客厅 / 卧室 / 厨房 / 浴室 / 书房 / 室外
 *
 * openvela Tool 注册标准：
 *   1. 核心函数：tool_temperature_read(location, result) → int
 *   2. 入口函数：tool_temperature_read_entry(json_in, json_out, buf_size) → int
 *   3. 批量函数：tool_temperature_read_all(results, count) → int
 *
 * v2.1 变更：
 *   - 修复 Box-Muller 变换 rand1=1.0 时产生 NaN 的 Bug
 *   - 新增 tool_temperature_read_entry 包装函数
 *   - 修复 get_location_index(NULL) 崩溃
 *   - 用 rand_r() 替代 srand()，避免污染全局随机种子
 *   - 增加 temperature 下限边界保护
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <time.h>
#include <math.h>
#include "smart_home_tools.h"

/* ---------- 传感器配置 ---------- */

typedef struct {
    float base_temp;
    float base_humidity;
    float temp_variance;
    float hum_variance;
} sensor_profile_t;

static const sensor_profile_t g_sensor_profiles[] = {
    /* LOCATION_LIVING_ROOM */ { 25.0f, 60.0f, 1.0f, 3.0f },
    /* LOCATION_BEDROOM */      { 24.5f, 58.0f, 0.8f, 2.5f },
    /* LOCATION_KITCHEN */      { 26.5f, 55.0f, 1.5f, 5.0f },
    /* LOCATION_BATHROOM */     { 26.0f, 70.0f, 1.0f, 4.0f },
    /* LOCATION_STUDY */        { 25.2f, 57.0f, 0.5f, 2.0f },
    /* LOCATION_OUTDOOR */      { 28.0f, 50.0f, 2.0f, 8.0f },
};

#define SENSOR_COUNT (sizeof(g_sensor_profiles) / sizeof(g_sensor_profiles[0]))

static bool     g_sensor_initialized = false;
static uint32_t g_read_count         = 0;
static unsigned int g_rand_seed      = 0;  /* 线程安全的本地种子 */

/* ---------- 辅助函数 ---------- */

/*
 * get_location_index - 位置名 → 传感器表索引
 * 修复：增加 NULL 防御
 */
static int get_location_index(const char *location) {
    if (location == NULL) return LOCATION_LIVING_ROOM;

    if (strstr(location, "客厅") || strstr(location, "起居室"))  return LOCATION_LIVING_ROOM;
    if (strstr(location, "卧室") || strstr(location, "主卧"))    return LOCATION_BEDROOM;
    if (strstr(location, "厨房"))                                return LOCATION_KITCHEN;
    if (strstr(location, "浴室") || strstr(location, "卫生间"))   return LOCATION_BATHROOM;
    if (strstr(location, "书房") || strstr(location, "办公室"))   return LOCATION_STUDY;
    if (strstr(location, "室外") || strstr(location, "户外"))     return LOCATION_OUTDOOR;
    return LOCATION_LIVING_ROOM;
}

/*
 * init_sensor_profiles - 初始化传感器
 * 修复：使用 rand_r() + 本地种子替代 srand()/rand()，避免污染全局随机状态
 */
static void init_sensor_profiles(void) {
    if (g_sensor_initialized) return;

    g_rand_seed = (unsigned int)time(NULL) ^ (g_read_count * 2654435761U);
    g_sensor_initialized = true;

    fprintf(stdout, "[TempSensor] 温湿度传感器模块初始化完成 (%zu 个监测点)\n", SENSOR_COUNT);
}

/*
 * local_rand - 线程安全的伪随机数 [0, 1)
 */
static float local_rand(void) {
    g_rand_seed = g_rand_seed * 1103515245U + 12345U;
    return (float)(g_rand_seed & 0x7FFFFFFF) / (float)0x80000000;
}

/*
 * simulate_sensor_read - 带正态分布波动的模拟传感器读取
 *
 * 修复说明：
 *   Box-Muller 变换要求 rand1, rand2 ∈ (0, 1]，但 rand() / RAND_MAX
 *   可能产生精确的 1.0。log(rand1+ε) 当 rand1=1.0 且 ε>0 时，
 *   log(1.0+ε) > 0 → -2.0*log > 0 → sqrt(负数) = NaN。
 *
 *   修复方案：将 rand1 缩放到 (0, 1) 而非 (0, 1+ε)，消除溢出窗口。
 */
static void simulate_sensor_read(const sensor_profile_t *profile,
                                 float *temperature,
                                 float *humidity) {
    /* rand1, rand2 ∈ (0, 1)，确保 log 参数 ∈ (0, 1) */
    float rand1 = local_rand() * 0.999999f + 0.000001f;  /* (1e-6, 1.0) 开区间 */
    float rand2 = local_rand() * 0.999999f + 0.000001f;

    /* Box-Muller 变换：rand1, rand2 → 标准正态分布 */
    float noise = sqrtf(-2.0f * logf(rand1)) * cosf(2.0f * 3.14159265f * rand2);
    noise *= 0.3f;  /* 缩放振幅 */

    /* 温度偏移：裁剪到 [-variance, +variance] */
    float temp_offset = noise * profile->temp_variance;
    if (temp_offset >  profile->temp_variance) temp_offset =  profile->temp_variance;
    if (temp_offset < -profile->temp_variance) temp_offset = -profile->temp_variance;

    /* 湿度偏移 */
    float hum_offset = noise * profile->hum_variance;
    if (hum_offset >  profile->hum_variance) hum_offset =  profile->hum_variance;
    if (hum_offset < -profile->hum_variance) hum_offset = -profile->hum_variance;

    /* 四舍五入到一位小数 */
    *temperature = roundf((profile->base_temp + temp_offset) * 10.0f) / 10.0f;
    *humidity    = roundf((profile->base_humidity + hum_offset) * 10.0f) / 10.0f;

    /* 边界保护（温度下限也加上，防止极低温异常） */
    if (*humidity    > 100.0f) *humidity    = 100.0f;
    if (*humidity    <   0.0f) *humidity    =   0.0f;
    if (*temperature < -50.0f) *temperature = -50.0f;  /* 物理下限 */
    if (*temperature >  80.0f) *temperature =  80.0f;  /* 物理上限 */
}

/*
 * get_timestamp - 生成 ISO 格式时间戳
 */
static void get_timestamp(char *buffer, size_t size) {
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    if (tm_info) {
        strftime(buffer, size, "%Y-%m-%d %H:%M:%S", tm_info);
    } else {
        snprintf(buffer, size, "unknown");
    }
}

/* ---------- 核心Tool函数 ---------- */

/*
 * tool_temperature_read - 读取指定位置温湿度
 *
 * @param location: 位置名 ("客厅"/"卧室"/...)，允许 NULL（返回错误）
 * @param result:   输出结构体，调用方保证非 NULL
 * @return:        TOOL_SUCCESS / TOOL_ERR_PARAM / TOOL_ERR_IO
 */
int tool_temperature_read(const char *location,
                          temperature_humidity_t *result) {
    /* ---- 1. 参数校验 ---- */
    if (location == NULL || location[0] == '\0') {
        fprintf(stderr, "[TempSensor] 错误: location 为空\n");
        if (result) result->status = TOOL_ERR_PARAM;
        return TOOL_ERR_PARAM;
    }
    if (result == NULL) {
        fprintf(stderr, "[TempSensor] 错误: result 为 NULL\n");
        return TOOL_ERR_PARAM;
    }

    /* 防御性清零 */
    memset(result, 0, sizeof(temperature_humidity_t));

    /* 超长输入保护：截断日志打印 */
    size_t loc_len = strlen(location);
    if (loc_len > 64) {
        fprintf(stderr, "[TempSensor] 警告: location 超长 (%zu 字符)，截断处理\n", loc_len);
    }

    /* ---- 2. 初始化 ---- */
    init_sensor_profiles();

    /* ---- 3. 定位传感器 ---- */
    int idx = get_location_index(location);
    const sensor_profile_t *profile = &g_sensor_profiles[idx];  /* 默认回退到客厅 */

    if (idx < 0 || (size_t)idx >= SENSOR_COUNT) {
        fprintf(stderr, "[TempSensor] 警告: 未知位置 '%s'，回退到客厅传感器\n", location);
        profile = &g_sensor_profiles[LOCATION_LIVING_ROOM];
    }

    /* ---- 4. 读取 ---- */
    float temp = 0.0f, hum = 0.0f;
    simulate_sensor_read(profile, &temp, &hum);
    g_read_count++;

    /* ---- 5. ReAct Observation 日志 ---- */
    fprintf(stdout, "[TempSensor] ================ 温湿度读取 ================\n");
    fprintf(stdout, "[TempSensor] 位置: %s\n",
            (loc_len <= 32) ? location : "(超长)");         /* 防日志溢出 */
    fprintf(stdout, "[TempSensor] 温度: %.1f°C | 湿度: %.0f%%\n", temp, hum);

    /* 体感描述 */
    const char *temp_feel;
    if      (temp < 10.0f) temp_feel = "寒冷";
    else if (temp < 18.0f) temp_feel = "偏凉";
    else if (temp < 24.0f) temp_feel = "舒适";
    else if (temp < 28.0f) temp_feel = "温暖";
    else if (temp < 35.0f) temp_feel = "炎热";
    else                   temp_feel = "酷热";

    fprintf(stdout, "[TempSensor] 体感: %s\n", temp_feel);
    fprintf(stdout, "[TempSensor] ================================================\n");

    /* ---- 6. 填充结果 ---- */
    result->status      = TOOL_SUCCESS;
    result->temperature = temp;
    result->humidity    = hum;

    strncpy(result->location_name, location, sizeof(result->location_name) - 1);
    result->location_name[sizeof(result->location_name) - 1] = '\0';

    get_timestamp(result->timestamp, sizeof(result->timestamp));
    result->timestamp[sizeof(result->timestamp) - 1] = '\0';

    return TOOL_SUCCESS;
}

/* ---------- 批量读取 ---------- */

/*
 * tool_temperature_read_all - 一次读取全部 6 个位置
 */
int tool_temperature_read_all(temperature_humidity_t *results, int *count) {
    if (results == NULL || count == NULL) return TOOL_ERR_PARAM;

    static const char *locations[] = {"客厅", "卧室", "厨房", "浴室", "书房", "室外"};
    int total   = (int)(sizeof(locations) / sizeof(locations[0]));
    int success = 0;

    fprintf(stdout, "[TempSensor] 批量读取所有位置温湿度...\n");

    for (int i = 0; i < total; i++) {
        if (tool_temperature_read(locations[i], &results[i]) == TOOL_SUCCESS) {
            success++;
        }
    }

    *count = success;
    fprintf(stdout, "[TempSensor] 批量读取完成: %d/%d 成功\n", success, total);

    return (success > 0) ? TOOL_SUCCESS : TOOL_ERR_IO;
}

/* ---------- openvela Tool Entry（注册入口） ---------- */

/*
 * tool_temperature_read_entry - openvela Agent 调用的标准入口
 *
 * 输入 JSON: {"location":"客厅"}
 * 输出 JSON: {"status":0,"temperature":25.0,"humidity":60.0,
 *             "location_name":"客厅","timestamp":"2026-07-05 15:00:00"}
 *
 * 遵循 openvela Tool 注册规范。
 */
int tool_temperature_read_entry(const char *json_params,
                                char *json_result, size_t buf_size) {
    if (json_params == NULL || json_result == NULL || buf_size == 0) {
        return TOOL_ERR_PARAM;
    }

    /* 确保模块已初始化 */
    if (!g_sensor_initialized) {
        init_sensor_profiles();
    }

    /* 从 JSON 提取 location */
    char location[64] = "客厅";  /* 默认值 */
    const char *loc_ptr = strstr(json_params, "\"location\"");
    if (loc_ptr) {
        loc_ptr = strchr(loc_ptr, ':');
        if (loc_ptr) {
            loc_ptr++;
            while (*loc_ptr == ' ' || *loc_ptr == '"' || *loc_ptr == '\t') loc_ptr++;
            size_t i = 0;
            while (*loc_ptr && *loc_ptr != '"' && i < sizeof(location) - 1) {
                location[i++] = *loc_ptr++;
            }
            location[i] = '\0';
        }
    }

    /* 调用核心函数 */
    temperature_humidity_t result;
    int ret = tool_temperature_read(location, &result);

    /* 序列化为 JSON（Agent 可直接解析） */
    snprintf(json_result, buf_size,
             "{\"status\":%d,\"temperature\":%.1f,\"humidity\":%.1f,"
             "\"location_name\":\"%s\",\"timestamp\":\"%s\"}",
             result.status,
             (double)result.temperature,
             (double)result.humidity,
             result.location_name,
             result.timestamp);

    return ret;
}
