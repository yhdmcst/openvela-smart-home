# Good Morning Skill - 早安智能家居场景

```yaml
skill:
  name: good_morning_skill
  version: "1.0.0"
  description: "每天早上8点自动播报天气，并根据室温自动调节空调的早安场景"
  author: "openvela智能家居参赛团队"
  trigger:
    type: schedule
    cron: "0 8 * * *"                     # 每天早上8点触发
    manual_trigger: "早上好"               # 也支持手动语音触发

  # ============================================================
  # 工具依赖声明（注册到Agent的Tool列表）
  # ============================================================
  required_tools:
    - name: read_temperature
      description: "读取温湿度数据"
    - name: light_control
      description: "灯光控制"
    - name: text_to_speech            # 可选：语音播报
      description: "文字转语音播报"
      required: false

  # ============================================================
  # ReAct 推理步骤
  # 格式: Thought → Action → Observation → (循环) → Final Answer
  # ============================================================
  steps:
    # ---------- Step 1: 读取室内外温湿度 ----------
    - id: step1_read_indoor
      thought: |
        用户触发了早安场景。我需要先了解当前室内环境状况，
        然后根据数据决定是否需要调节空调。先读取客厅温湿度。
      action:
        tool: read_temperature
        params:
          location: "客厅"
      observation_expected: |
        获取客厅的实时温度和湿度数据。
      on_observation:
        store_as: indoor_temp_humidity
        temperature_var: "indoor_temp"
        humidity_var: "indoor_humidity"

    - id: step2_read_outdoor
      thought: |
        了解室外天气有助于判断是否需要开窗通风，
        以及今天适合穿什么衣服。读取室外温湿度。
      action:
        tool: read_temperature
        params:
          location: "室外"
      observation_expected: |
        获取室外温度和湿度数据。
      on_observation:
        store_as: outdoor_temp_humidity
        temperature_var: "outdoor_temp"

    # ---------- Step 2: 空调自动调节 ----------
    - id: step3_decide_ac
      thought: |
        室内温度是 {{indoor_temp}}°C，室外温度是 {{outdoor_temp}}°C。
        我需要根据温度判断是否需要调节空调：
        - 如果室内温度 >= 28°C：太热了，需要开空调降温
        - 如果室内温度 <= 18°C：太冷了，需要开暖气
        - 如果 18°C < 温度 < 28°C：温度舒适，不需要调节
      condition:
        - if: "{{indoor_temp}} >= 28"
          thought: "室内温度 {{indoor_temp}}°C 偏高，需要开启空调降温至 26°C"
          action:
            tool: ac_control                  # 空调控制Tool（需补充实现）
            params:
              mode: "cool"
              target_temp: 26
        - if: "{{indoor_temp}} <= 18"
          thought: "室内温度 {{indoor_temp}}°C 偏低，需要开启暖气升温至 22°C"
          action:
            tool: ac_control
            params:
              mode: "heat"
              target_temp: 22
        - if: "{{indoor_temp}} > 18 AND {{indoor_temp}} < 28"
          thought: "室内温度 {{indoor_temp}}°C 舒适，无需调节空调"
          action: skip

    # ---------- Step 3: 窗帘控制（可选扩展） ----------
    - id: step4_curtain
      thought: |
        根据室外温度和天气判断是否需要拉开窗帘：
        - 如果室外温度适中且不是极端天气，建议拉开窗帘享受自然光
      condition:
        - if: "{{outdoor_temp}} >= 15 AND {{outdoor_temp}} <= 30"
          thought: "室外温度 {{outdoor_temp}}°C 适宜，建议拉开窗帘通风采光"
          action:
            tool: curtain_control
            params:
              action: "open"
        - if: "{{outdoor_temp}} > 30"
          thought: "室外温度 {{outdoor_temp}}°C 偏高，建议关闭窗帘遮阳"
          action:
            tool: curtain_control
            params:
              action: "close"

    # ---------- Step 4: 灯光控制 ----------
    - id: step5_light
      thought: |
        早上应该提供柔和的灯光，不要太刺眼。
        把客厅灯光调到 40% 亮度，营造舒适氛围。
      action:
        tool: light_control
        params:
          location: "客厅"
          action: "调亮度"
          brightness: 40
      observation_expected: |
        客厅灯光已调节至 40% 亮度。

    # ---------- Step 5: 播报早安信息 ----------
    - id: step6_greeting
      thought: |
        已收集所有环境数据，现在向用户播报早安信息：
        - 今天日期和星期
        - 室内外温度和湿度
        - 空调和灯光调节结果
      action:
        tool: text_to_speech
        params:
          text: |
            早上好！今天是 {{current_date}}。
            室外温度 {{outdoor_temp}}°C，湿度 {{outdoor_humidity}}%。
            室内温度 {{indoor_temp}}°C，湿度 {{indoor_humidity}}%。
            空调已自动调节，客厅灯光已设为柔光模式。
            祝您有愉快的一天！
      observation_expected: |
        语音播报完成。

  # ============================================================
  # 最终响应模板
  # ============================================================
  final_answer: |
    ☀️ 早安场景已执行完成！

    📊 环境报告：
    - 室外：{{outdoor_temp}}°C / {{outdoor_humidity}}%
    - 室内：{{indoor_temp}}°C / {{indoor_humidity}}%

    🔧 自动调节：
    - 空调状态：{{ac_status}}
    - 灯光：客厅柔光模式（40%）
    - 窗帘：{{curtain_status}}

    💡 今日建议：
    - 体感温度 {{feel_temp}}，建议穿着 {{clothing_suggestion}}
    {{ventilation_suggestion}}

  # ============================================================
  # 错误处理
  # ============================================================
  on_error:
    - if: "sensor_read_failed"
      fallback: "传感器读取失败，使用昨天同时段数据作为近似值"
    - if: "ac_control_failed"
      fallback: "空调控制失败，请手动调节"
    - if: "any_error"
      response: "早安场景部分功能执行失败，已完成的操作：{{completed_steps}}"

  # ============================================================
  # 扩展：场景联动规则（复赛可增强）
  # ============================================================
  extensions:
    weather_alert:
      description: "接入天气预报API，极端天气自动提醒"
      trigger: "{{outdoor_temp}} > 35 OR {{outdoor_temp}} < 0"
      action: "播报极端天气警告"

    energy_saving:
      description: "节能模式：无人房间自动关灯关空调"
      trigger: "{{room_occupied}} == false 持续 30 分钟"
      action: "关闭该房间灯光和空调"

    security_link:
      description: "与安防系统联动，离家模式自动全屋关灯"
      trigger: "离家模式激活"
      action: "全屋关灯 + 关空调 + 关窗帘"
```

---

## 使用方式

### 1. 自动触发（每天8点）
```bash
# 系统crontab自动执行，无需手动干预
```

### 2. 手动触发
在 openvela Agent 终端中输入：
```
> 早上好
```

### 3. 通过API触发（预留）
```bash
curl -X POST http://localhost:8080/agent/command \
  -H "Content-Type: application/json" \
  -d '{"command": "执行早安场景"}'
```

---

## Skill 注册到 Agent

将此文件放置到 `packages_ai_agent/skills/` 目录，Agent 启动时自动加载：

```c
// 在 agent_init_and_register_tools() 中添加：
agent_load_skill(agent_handle, "/data/skills/good_morning_skill.md");
```

---

## 依赖清单

| Tool名称 | 状态 | 说明 |
|----------|------|------|
| `read_temperature` | ✅ 已实现 | `tool_temperature_read.c` |
| `light_control` | ✅ 已实现 | `tool_light_control.c` |
| `ac_control` | ⚠️ 需补充 | 空调红外/智能插座控制 |
| `curtain_control` | ✅ 已实现 | `tool_curtain_control.c` |
| `text_to_speech` | ⚠️ 可选 | 语音播报模块 |

> 注：`ac_control` 和 `curtain_control` 可作为初赛加分项开发，核心灯光+温湿度已完全就绪。
