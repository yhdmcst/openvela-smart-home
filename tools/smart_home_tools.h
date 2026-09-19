/*
 * smart_home_tools.h - 智能家居 Tool 统一头文件 v2.0
 *
 * 定义所有 Tool 共用的枚举、结构体和返回值。
 * 涵盖：灯光、温湿度、窗帘、安防、多传感器、主动巡检
 * 遵循 openvela Tool 注册规范。
 */
#ifndef SMART_HOME_TOOLS_H
#define SMART_HOME_TOOLS_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------- 通用返回码 ---------- */
#define TOOL_SUCCESS      0
#define TOOL_ERR_PARAM   -1
#define TOOL_ERR_IO      -2
#define TOOL_ERR_MEMORY  -3
#define TOOL_ERR_TIMEOUT -4

/* ---------- 位置枚举 ---------- */
typedef enum {
    LOCATION_LIVING_ROOM = 0,  /* 客厅 */
    LOCATION_BEDROOM,          /* 卧室 */
    LOCATION_KITCHEN,          /* 厨房 */
    LOCATION_BATHROOM,         /* 浴室 */
    LOCATION_STUDY,            /* 书房 */
    LOCATION_OUTDOOR,          /* 室外 */
    LOCATION_COUNT,            /* 常规区域总数（不含 LOCATION_ALL） */
    LOCATION_ALL = 99          /* 全屋操作 */
} device_location_t;

/* ---------- 灯光控制相关 ---------- */
typedef enum {
    LIGHT_ACTION_ON = 0,
    LIGHT_ACTION_OFF,
    LIGHT_ACTION_SET_BRIGHTNESS,
    LIGHT_ACTION_TOGGLE
} light_action_t;

typedef struct {
    device_location_t location;
    light_action_t    action;
    uint8_t           brightness;
} light_control_params_t;

typedef struct {
    int     status;
    char    location_name[32];
    char    action_desc[64];
    uint8_t current_brightness;
} light_control_result_t;

/* ---------- 温湿度相关 ---------- */
typedef struct {
    int     status;
    float   temperature;
    float   humidity;
    char    location_name[32];
    char    timestamp[32];
} temperature_humidity_t;

/* ---------- 窗帘控制（新增） ---------- */
typedef enum {
    CURTAIN_ACTION_OPEN = 0,
    CURTAIN_ACTION_CLOSE,
    CURTAIN_ACTION_STOP,
    CURTAIN_ACTION_SET_POSITION   /* 0=全关, 100=全开 */
} curtain_action_t;

typedef struct {
    device_location_t location;
    curtain_action_t  action;
    uint8_t           position;        /* 0-100, 仅 SET_POSITION 时有效 */
} curtain_control_params_t;

typedef struct {
    int     status;
    char    location_name[32];
    char    action_desc[64];
    uint8_t current_position;         /* 0=全关, 100=全开 */
    bool    is_moving;
} curtain_control_result_t;

/* ---------- 安防控制（新增） ---------- */
typedef enum {
    SECURITY_ACTION_ARM = 0,          /* 布防 */
    SECURITY_ACTION_DISARM,           /* 撤防 */
    SECURITY_ACTION_ALERT,            /* 报警 */
    SECURITY_ACTION_CHECK             /* 检查状态 */
} security_action_t;

typedef enum {
    SECURITY_MODE_HOME = 0,           /* 在家模式 */
    SECURITY_MODE_AWAY,               /* 离家模式 */
    SECURITY_MODE_NIGHT,              /* 夜间模式 */
    SECURITY_MODE_OFF                 /* 关闭 */
} security_mode_t;

typedef struct {
    int              status;
    security_mode_t  current_mode;
    bool             door_locked[6];   /* 各区域门锁状态 */
    bool             window_closed[6]; /* 各区域窗户状态 */
    bool             alarm_triggered;
    char             status_desc[128];
} security_control_result_t;

/* ---------- 多传感器数据（新增）- 物理感知层 ---------- */
typedef struct {
    float   illuminance;       /* 光照强度 (lux) */
    bool    motion_detected;   /* 人体红外检测 */
    bool    door_open;         /* 门磁状态 */
    bool    window_open;       /* 窗磁状态 */
    float   pm25;              /* PM2.5 (μg/m³) */
    float   co2;               /* CO2浓度 (ppm) */
    float   noise;             /* 噪音 (dB) */
    char    update_time[32];
} sensor_data_t;

/* ---------- 主动巡检报告（新增） ---------- */
typedef struct {
    int     status;
    char    report[1024];      /* 巡检结果文本 */
    int     action_count;      /* 自动执行的动作数 */
    bool    anomaly_detected;  /* 是否检测到异常 */
    char    suggestions[512];  /* AI 建议 */
} patrol_report_t;

/* ---------- 设备状态持久化 ---------- */
typedef struct {
    bool    is_on;
    uint8_t brightness;
} light_persist_t;

typedef struct {
    bool    is_open;
    uint8_t position;
} curtain_persist_t;

typedef struct {
    bool    locked;
    bool    window_closed;
} security_persist_t;

typedef struct {
    light_persist_t    lights[6];
    curtain_persist_t  curtains[6];
    security_persist_t security[6];
    float              last_temp[6];
    float              last_hum[6];
    sensor_data_t      sensors[6];
    security_mode_t    security_mode;
    int                initialized;
} device_state_t;

/* ---------- Tool 注册接口 ---------- */

/* 模块初始化 */
int smart_home_tools_init(void);

/* 灯光控制 */
int tool_light_control(const light_control_params_t *params, light_control_result_t *result);
int get_light_state(device_location_t loc, bool *is_on, uint8_t *brightness);
device_location_t tool_get_location_enum(const char *name);
int tool_light_control_entry(const char *json_params, char *json_result, size_t buf_size);

/* 温湿度读取 */
int tool_temperature_read(const char *location, temperature_humidity_t *result);
int tool_temperature_read_all(temperature_humidity_t *results, int *count);
int tool_temperature_read_entry(const char *json_params, char *json_result, size_t buf_size);

/* 窗帘控制（新增） */
int tool_curtain_control(const curtain_control_params_t *params, curtain_control_result_t *result);

/* 安防控制（新增） */
int tool_security_control(security_action_t action, security_mode_t mode, security_control_result_t *result);
int tool_security_check_all(security_control_result_t *result);

/* 多传感器读取（新增）- 物理感知层 */
int tool_sensor_read(device_location_t loc, sensor_data_t *data);
int tool_sensor_read_all(sensor_data_t *data_array, int *count);

/* 主动环境巡检（新增） */
int tool_environment_patrol(patrol_report_t *report);

/* 模糊指令解析（新增） */
int tool_fuzzy_command_parse(const char *user_input, char *action_json, size_t buf_size);

/* ---------- 状态持久化接口 ---------- */
int device_state_save(const char *filepath);
int device_state_load(const char *filepath);
int device_state_to_json(char *buffer, size_t buf_size);

#ifdef __cplusplus
}
#endif

#endif /* SMART_HOME_TOOLS_H */
