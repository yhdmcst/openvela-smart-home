/*
 * test_smart_home.c - 智能家居 Tool 综合测试
 * 测试所有 Tool 的核心功能
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "smart_home_tools.h"

static int total = 0, passed = 0;

#define TEST(name, expr) do { \
    total++; \
    int _ret = (expr); \
    if (_ret == TOOL_SUCCESS) { \
        passed++; \
        fprintf(stdout, "  OK %s\n", name); \
    } else { \
        fprintf(stdout, "  FAIL %s (ret=%d)\n", name, _ret); \
    } \
} while(0)

int main(void) {
    fprintf(stdout, "\n");
    fprintf(stdout, "+=========================================+\n");
    fprintf(stdout, "|  openvela Smart Home Tool Test         |\n");
    fprintf(stdout, "+=========================================+\n\n");

    /* ---- 1. Module Init ---- */
    fprintf(stdout, "--- 1. Module Init ---\n");
    TEST("smart_home_tools_init",       smart_home_tools_init());
    TEST("smart_home_tools_init (idempotent)", smart_home_tools_init());

    /* ---- 2. Light Control ---- */
    fprintf(stdout, "\n--- 2. Light Control ---\n");
    light_control_params_t lp;
    light_control_result_t lr;
    memset(&lp, 0, sizeof(lp));
    memset(&lr, 0, sizeof(lr));

    lp.location = LOCATION_LIVING_ROOM; lp.action = LIGHT_ACTION_ON;
    TEST("Living Room Light ON", tool_light_control(&lp, &lr));

    lp.location = LOCATION_LIVING_ROOM; lp.action = LIGHT_ACTION_SET_BRIGHTNESS; lp.brightness = 60;
    TEST("Living Room Brightness 60%", tool_light_control(&lp, &lr));

    lp.location = LOCATION_BEDROOM; lp.action = LIGHT_ACTION_ON;
    TEST("Bedroom Light ON", tool_light_control(&lp, &lr));

    lp.location = LOCATION_ALL; lp.action = LIGHT_ACTION_OFF;
    TEST("All Lights OFF", tool_light_control(&lp, &lr));

    lp.location = LOCATION_ALL; lp.action = LIGHT_ACTION_ON;
    TEST("All Lights ON", tool_light_control(&lp, &lr));

    /* ---- 3. Temperature/Humidity ---- */
    fprintf(stdout, "\n--- 3. Temperature/Humidity ---\n");
    temperature_humidity_t th;
    memset(&th, 0, sizeof(th));
    TEST("Living Room Temp", tool_temperature_read("living", &th));
    fprintf(stdout, "     temp=%.1fC humidity=%.0f%% time=%s\n",
            th.temperature, th.humidity, th.timestamp);

    memset(&th, 0, sizeof(th));
    TEST("Bedroom Temp", tool_temperature_read("bedroom", &th));

    memset(&th, 0, sizeof(th));
    TEST("Outdoor Temp", tool_temperature_read("outdoor", &th));

    temperature_humidity_t ths[6];
    int cnt = 0;
    TEST("Read All Temps", tool_temperature_read_all(ths, &cnt));
    fprintf(stdout, "     %d/6 locations read\n", cnt);

    /* ---- 4. Curtain Control ---- */
    fprintf(stdout, "\n--- 4. Curtain Control ---\n");
    curtain_control_params_t cp;
    curtain_control_result_t cr;
    memset(&cp, 0, sizeof(cp)); memset(&cr, 0, sizeof(cr));
    cp.location = LOCATION_LIVING_ROOM; cp.action = CURTAIN_ACTION_OPEN;
    TEST("Open Living Room Curtain", tool_curtain_control(&cp, &cr));

    memset(&cp, 0, sizeof(cp)); memset(&cr, 0, sizeof(cr));
    cp.location = LOCATION_BEDROOM; cp.action = CURTAIN_ACTION_SET_POSITION; cp.position = 50;
    TEST("Bedroom Curtain 50%", tool_curtain_control(&cp, &cr));

    memset(&cp, 0, sizeof(cp)); memset(&cr, 0, sizeof(cr));
    cp.location = LOCATION_ALL; cp.action = CURTAIN_ACTION_CLOSE;
    TEST("All Curtains CLOSE", tool_curtain_control(&cp, &cr));

    /* ---- 5. Security Control ---- */
    fprintf(stdout, "\n--- 5. Security Control ---\n");
    security_control_result_t sr;
    memset(&sr, 0, sizeof(sr));
    TEST("Arm Away Mode", tool_security_control(SECURITY_ACTION_ARM, SECURITY_MODE_AWAY, &sr));
    fprintf(stdout, "     status: %s\n", sr.status_desc);

    memset(&sr, 0, sizeof(sr));
    TEST("Disarm", tool_security_control(SECURITY_ACTION_DISARM, SECURITY_MODE_OFF, &sr));

    memset(&sr, 0, sizeof(sr));
    TEST("Security Check All", tool_security_check_all(&sr));

    /* ---- 6. Multi-Sensor ---- */
    fprintf(stdout, "\n--- 6. Multi-Sensor ---\n");
    sensor_data_t sd;
    memset(&sd, 0, sizeof(sd));
    TEST("Living Room Sensor", tool_sensor_read(LOCATION_LIVING_ROOM, &sd));
    fprintf(stdout, "     lux=%.0f motion=%s PM2.5=%.1f CO2=%.0f\n",
            sd.illuminance, sd.motion_detected?"Y":"N", sd.pm25, sd.co2);

    memset(&sd, 0, sizeof(sd));
    TEST("Outdoor Sensor", tool_sensor_read(LOCATION_OUTDOOR, &sd));

    sensor_data_t sds[6];
    cnt = 0;
    TEST("Read All Sensors", tool_sensor_read_all(sds, &cnt));
    fprintf(stdout, "     %d/6 sensors read\n", cnt);

    /* ---- 7. Fuzzy Command ---- */
    fprintf(stdout, "\n--- 7. Fuzzy Command ---\n");
    char act_json[512];
    memset(act_json, 0, sizeof(act_json));
    TEST("Fuzzy 'too dark'", tool_fuzzy_command_parse("\xe5\xa4\xaa\xe6\x9a\x97\xe4\xba\x86", act_json, sizeof(act_json)));
    fprintf(stdout, "     JSON: %s\n", act_json);

    memset(act_json, 0, sizeof(act_json));
    TEST("Fuzzy 'so cold'", tool_fuzzy_command_parse("\xe5\xa5\xbd\xe5\x86\xb7\xe5\x95\x8a", act_json, sizeof(act_json)));
    fprintf(stdout, "     JSON: %s\n", act_json);

    memset(act_json, 0, sizeof(act_json));
    TEST("Fuzzy 'anyone'", tool_fuzzy_command_parse("\xe6\x9c\x89\xe4\xba\xba\xe5\x90\x97", act_json, sizeof(act_json)));

    /* ---- 8. Environment Patrol ---- */
    fprintf(stdout, "\n--- 8. Environment Patrol ---\n");
    patrol_report_t pr;
    memset(&pr, 0, sizeof(pr));
    TEST("Patrol", tool_environment_patrol(&pr));
    fprintf(stdout, "     actions: %d anomaly: %s\n", pr.action_count, pr.anomaly_detected?"Y":"N");

    /* ---- 9. Persistence ---- */
    fprintf(stdout, "\n--- 9. Persistence ---\n");
    TEST("Save State", device_state_save("device_state.json"));
    TEST("Load State", device_state_load("device_state.json"));

    /* ---- Summary ---- */
    fprintf(stdout, "\n");
    fprintf(stdout, "+=========================================+\n");
    fprintf(stdout, "|  TEST REPORT                           |\n");
    fprintf(stdout, "|  PASSED: %d/%d                        |\n", passed, total);
    if (passed == total) {
        fprintf(stdout, "|  *** ALL PASSED ***                     |\n");
    } else {
        fprintf(stdout, "|  SOME FAILED                           |\n");
    }
    fprintf(stdout, "+=========================================+\n");

    return (passed == total) ? 0 : 1;
}
