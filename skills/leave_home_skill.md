# Leave Home Skill - 离家模式

```yaml
skill:
  name: leave_home_skill
  version: "1.0.0"
  description: "用户说出'我出门了'时，Agent自动执行全屋安全巡检+设备关闭+安防启动的多设备协同流程"
  author: "openvela智能家居参赛团队"
  trigger:
    manual_trigger: ["我出门了", "拜拜", "再见", "离家模式", "出门"]

  required_tools:
    - name: light_control
    - name: curtain_control
    - name: security_control
    - name: read_temperature
    - name: sensor_read_all

  steps:
    # Step 1: 环境感知预查询（模糊指令理解）
    - id: step1_environment_snapshot
      thought: |
        用户要出门了。在执行离家模式前，我需要先感知全屋当前状态：
        哪些灯还开着？哪些窗户没关？哪个房间还有人？
        物理AI核心策略：先感知(Perceive)，再决策(Decide)，最后执行(Act)。
      action:
        tool: sensor_read_all
        params: {}
      observation_expected: |
        获取全屋传感器数据（光照/人体/门窗/空气质量）
      on_observation:
        store_as: full_sensor_data

    # Step 2: 全屋灯光关闭
    - id: step2_turn_off_lights
      thought: |
        离家前需要关闭所有灯光以节能。
        根据传感器数据，{{occupied_rooms}} 有人活动，但仍执行关闭（离家模式安全优先）。
      action:
        tool: light_control
        params:
          location: "全屋"
          action: "关灯"
      observation_expected: |
        全屋灯光已关闭
      on_observation:
        store_as: light_status

    # Step 3: 关闭所有窗帘
    - id: step3_close_curtains
      thought: |
        离家时关闭窗帘可以保护隐私、防止阳光直射损坏家具。
      action:
        tool: curtain_control
        params:
          location: "全屋"
          action: "close"
      observation_expected: |
        全屋窗帘已关闭

    # Step 4: 门窗安全检查
    - id: step4_security_check
      thought: |
        检查全屋门窗状态，确保所有门窗已关闭。
        物理AI特性：在启动安防前必须确认物理安全条件满足。
      action:
        tool: security_control
        params:
          action: "check"
      observation_expected: |
        返回各区域门窗锁闭状态
      on_observation:
        store_as: door_window_status
        door_issues_var: "door_issues"

    # Step 5: 异常门窗处理
    - id: step5_handle_openings
      condition:
        - if: "{{door_issues}} > 0"
          thought: |
            检测到 {{door_issues}} 处门窗未关闭。离家模式下安全优先，
            已记录异常位置，建议用户检查。
          action: skip
        - if: "{{door_issues}} == 0"
          thought: "所有门窗已关闭，安全条件满足"

    # Step 6: 启动离家安防
    - id: step6_arm_security
      thought: |
        灯光已关、窗帘已拉、门窗已查。现在启动离家安防模式。
        物理AI完整闭环：感知→决策→多设备协同执行→确认反馈。
      action:
        tool: security_control
        params:
          action: "arm"
          mode: "away"
      observation_expected: |
        离家安防模式已启动

  final_answer: |
    🏠 离家模式已启动！物理AI执行报告：

    ✅ 全屋灯光：已关闭（{{light_count}} 个区域）
    ✅ 全屋窗帘：已拉上
    🔒 安防系统：离家模式已布防

    📊 环境快照：
    - 室内温度：{{indoor_temp}}°C
    - 门窗异常：{{door_issues}} 处

    💡 节能预估：本次关闭操作可节省约 {{energy_saved}} kWh/天

    🔐 您的家已进入安全守护模式。
    远程可通过 openvela App 随时查看家中状态。

  on_error:
    - if: "light_control_failed"
      fallback: "部分灯光关闭失败，已记录异常区域"
    - if: "security_arm_failed"
      fallback: "安防启动失败，请手动检查门窗后重试"
    - if: "any_error"
      response: "离家模式部分执行失败\n已完成：{{completed_steps}}\n失败：{{failed_steps}}\n请手动检查后再出门"
```

---

## 多设备协同流程图

```
用户: "我出门了"
    │
    ▼
┌─────────────────────────────────────────┐
│  Step 1: 环境感知 (Perceive)             │
│  sensor_read_all → 光照/人体/门窗/PM2.5  │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  Step 2-3: 设备关闭 (Act)                │
│  light_control("全屋", 关灯)              │
│  curtain_control("全屋", 关闭)            │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  Step 4-5: 安全检查 (Verify)             │
│  security_control(check) → 门窗巡检      │
│  异常检测 → 提醒用户                      │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│  Step 6: 安防启动 (Secure)               │
│  security_control(arm, away)             │
│  → 物理AI完整闭环                          │
└─────────────────────────────────────────┘
```

---

## 使用方式

在 openvela Agent 终端或 Web 面板中输入：

```
> 我出门了
> 拜拜
> 离家模式
```

## 物理AI特性体现

| 特性 | 本Skill的实现 |
|------|-------------|
| **主动感知** | Step1 先查询全屋传感器，获得环境上下文 |
| **多设备协同** | 灯光+窗帘+安防 三个Tool依次编排 |
| **条件决策** | 根据门窗状态决定是否提醒用户 |
| **闭环验证** | 执行后确认每一步是否成功 |
| **异常处理** | 每个Tool失败有fallback策略 |
