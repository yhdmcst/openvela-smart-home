#!/usr/bin/env python3
"""
bridge_server.py v2.0 — openvela 物理AI Web Dashboard 桥接服务器

物理AI核心特性：
  1. 模糊指令理解："有点冷"/"太暗了" → 感知环境 → 自主决策
  2. 主动环境巡检：定时触发，Agent自主感知+决策+执行，无需用户指令
  3. 多传感器模拟：光照/人体红外/门磁/PM2.5/CO2/噪音
  4. 多设备协同：灯光+窗帘+安防 联动编排（离家模式）
  5. 端侧推理演示：本地决策，不依赖云端

用法：
  python3 bridge_server.py [--port 8080] [--patrol-interval 60]
"""
import http.server
import json
import os
import sys
import time
import re
import random
import threading
from urllib.parse import urlparse

# ============ 配置 ============
PORT = 8080
PATROL_INTERVAL = 60  # 主动巡检间隔（秒），0 表示禁用
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
STATE_FILE = os.path.join(PROJECT_DIR, "device_state.json")

LOCATIONS = ["客厅", "卧室", "厨房", "浴室", "书房", "室外"]
ROOM_ICONS = {"客厅": "🛋️", "卧室": "🛏️", "厨房": "🍳", "浴室": "🛁", "书房": "📚", "室外": "🌤️"}

# ============ 全局状态 ============
patrol_log = []          # 主动巡检日志
patrol_running = False   # 巡检线程状态
last_patrol_time = 0

# ============ 设备状态管理 ============
def load_state():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except: pass
    return default_state()

def default_state():
    state = {
        "lights": {}, "temperature": {}, "curtains": {}, "sensors": {}, "security": {}
    }
    for loc in LOCATIONS:
        state["lights"][loc] = {"is_on": False, "brightness": 0}
        state["temperature"][loc] = {"temp": 25.0, "humidity": 60.0}
        state["curtains"][loc] = {"is_open": loc != "浴室", "position": 100 if loc != "浴室" else 0}
        state["sensors"][loc] = generate_sensor_data(loc)
    state["security"] = {"mode": "off", "armed": False, "alarm_triggered": False}
    return state

def save_state(state):
    try:
        with open(STATE_FILE, 'w', encoding='utf-8') as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
    except: pass

# ============ 传感器模拟（物理感知层） ============
SENSOR_PROFILES = {
    "客厅": {"illuminance": 15000, "pm25": 25, "co2": 500, "noise": 35, "motion_pct": 0.7},
    "卧室": {"illuminance": 8000,  "pm25": 20, "co2": 450, "noise": 25, "motion_pct": 0.5},
    "厨房": {"illuminance": 20000, "pm25": 45, "co2": 600, "noise": 55, "motion_pct": 0.3},
    "浴室": {"illuminance": 5000,  "pm25": 15, "co2": 480, "noise": 50, "motion_pct": 0.2},
    "书房": {"illuminance": 12000, "pm25": 18, "co2": 420, "noise": 20, "motion_pct": 0.4},
    "室外": {"illuminance": 60000, "pm25": 55, "co2": 420, "noise": 60, "motion_pct": 0.0},
}

def generate_sensor_data(loc):
    p = SENSOR_PROFILES.get(loc, SENSOR_PROFILES["客厅"])
    noise = lambda v: v * (0.8 + random.random() * 0.4)
    return {
        "illuminance":    round(noise(p["illuminance"]), 1),
        "motion_detected": random.random() < p["motion_pct"],
        "door_open":       loc != "室外" and random.random() < 0.05,
        "window_open":     (loc == "浴室" and random.random() < 0.3) or (loc != "室外" and random.random() < 0.08),
        "pm25":            round(noise(p["pm25"]), 1),
        "co2":             round(noise(p["co2"]), 0),
        "noise":           round(noise(p["noise"]), 1),
        "update_time":     time.strftime("%H:%M:%S")
    }

# ============ 主动环境巡检（物理AI核心） ============
def run_environment_patrol():
    """定时主动巡检：Agent自主感知环境 → 决策 → 执行"""
    global last_patrol_time
    last_patrol_time = time.time()

    state = load_state()
    actions = []
    anomalies = []

    # 1. 刷新所有传感器数据
    for loc in LOCATIONS:
        state["sensors"][loc] = generate_sensor_data(loc)

    # 2. 逐区域分析+自动决策
    for loc in LOCATIONS:
        if loc == "室外": continue
        s = state["sensors"][loc]

        # 光照自动调节窗帘（感知→执行）
        if s["illuminance"] > 50000:
            state["curtains"][loc] = {"is_open": False, "position": 20}
            actions.append(f"☀️ {loc}光照{s['illuminance']:.0f}lux→窗帘自动遮阳至20%")
        elif s["illuminance"] < 2000 and s["motion_detected"]:
            state["lights"][loc] = {"is_on": True, "brightness": 60}
            actions.append(f"💡 {loc}光照不足+有人→自动开灯60%")

        # 人体红外节能（人走灯灭）
        if not s["motion_detected"] and state["lights"][loc]["is_on"]:
            state["lights"][loc] = {"is_on": False, "brightness": 0}
            actions.append(f"🚶 {loc}无人→自动关灯（节能）")

        # PM2.5异常
        if s["pm25"] > 75:
            anomalies.append(f"⚠️ {loc} PM2.5={s['pm25']:.0f}μg/m³ 超标")
        if s["co2"] > 1000:
            anomalies.append(f"⚠️ {loc} CO2={s['co2']:.0f}ppm 偏高")

    # 3. 生成报告
    report = {
        "time": time.strftime("%H:%M:%S"),
        "actions": actions,
        "anomalies": anomalies,
        "auto_decisions": len(actions),
        "active": True  # 标记为主动巡检
    }
    patrol_log.insert(0, report)
    if len(patrol_log) > 50:
        patrol_log.pop()

    save_state(state)

    if actions or anomalies:
        print(f"[Patrol {report['time']}] 主动决策 {len(actions)} 项 | 异常 {len(anomalies)} 项")
    return report

def patrol_loop(interval):
    """后台巡检线程"""
    global patrol_running
    patrol_running = True
    print(f"[Patrol] 主动巡检线程已启动（间隔 {interval}s）")
    # 立即执行一次
    run_environment_patrol()
    while patrol_running:
        time.sleep(interval)
        if patrol_running:
            run_environment_patrol()

# ============ 多设备协同执行器 ============
def execute_leave_home(state):
    """离家模式：多设备协同编排"""
    steps = []
    anomalies = 0

    # Step 1: 刷新传感器（感知）
    for loc in LOCATIONS:
        state["sensors"][loc] = generate_sensor_data(loc)
    steps.append({
        "type": "observe",
        "step": "环境感知",
        "content": "全屋传感器数据已刷新，获得实时环境上下文"
    })

    # Step 2: 全屋关灯
    for loc in LOCATIONS:
        if loc == "室外": continue
        state["lights"][loc] = {"is_on": False, "brightness": 0}
    steps.append({
        "type": "action",
        "step": "全屋关灯",
        "content": f"已关闭 {len(LOCATIONS)-1} 个区域灯光"
    })

    # Step 3: 全屋关窗帘
    for loc in LOCATIONS:
        if loc == "室外": continue
        state["curtains"][loc] = {"is_open": False, "position": 0}
    steps.append({
        "type": "action",
        "step": "全屋关窗帘",
        "content": f"已关闭 {len(LOCATIONS)-1} 个区域窗帘"
    })

    # Step 4: 门窗检查
    for loc in LOCATIONS:
        if loc == "室外": continue
        s = state["sensors"][loc]
        if s["door_open"]:
            anomalies += 1
        if s["window_open"]:
            anomalies += 1

    steps.append({
        "type": "observe",
        "step": "安全检查",
        "content": f"门窗巡检完成，发现 {anomalies} 处异常"
    })

    # Step 5: 启动离家安防
    state["security"] = {"mode": "away", "armed": True, "alarm_triggered": False}
    steps.append({
        "type": "action",
        "step": "安防启动",
        "content": "离家安防模式已布防 🔒"
    })

    save_state(state)
    return steps, anomalies

# ============ 模糊指令处理器 ============
def handle_fuzzy_command(state, command):
    """处理模糊指令：先感知环境 → 再决策执行"""
    loc = extract_location(command) or "客厅"
    s = state["sensors"].get(loc, generate_sensor_data(loc))
    t = state["temperature"].get(loc, {"temp": 25.0, "humidity": 60.0})

    # "有点冷" / "好冷"
    if any(w in command for w in ["冷", "凉", "冻"]):
        temp = t["temp"]
        if temp < 20:
            return {
                "thought": f"用户感觉冷。查询{loc}环境：温度{temp}°C，确实偏低。物理AI自主决策：建议开启暖气。",
                "actions": [{"description": f"感知环境→{loc}温度{temp}°C<20°C→建议开启暖气至22°C"}],
                "observation": f"[Sensor] {loc}温度={temp}°C，体感偏冷",
                "answer": f"🥶 {loc}当前{temp}°C，确实偏冷。已建议开启暖气升温至22°C。这是物理AI根据实际温度做出的自主判断，而非简单响应指令。"
            }
        else:
            return {
                "thought": f"用户感觉冷。查询{loc}温度{temp}°C，实际温度正常。可能是用户个人体感差异。",
                "actions": [{"description": f"感知环境→{loc}温度{temp}°C→判断无需调节"}],
                "observation": f"[Sensor] {loc}温度={temp}°C",
                "answer": f"🤔 {loc}当前{temp}°C，实际温度正常。不过如果您觉得冷，我可以帮您调高温度。这就是物理AI的\"感知优先于执行\"原则。"
            }

    # "好热" / "太热了"
    if any(w in command for w in ["热", "烫", "闷热"]):
        temp = t["temp"]
        if temp > 27:
            return {
                "thought": f"用户感觉热。查询{loc}温度{temp}°C，确实偏高。物理AI决策：建议开空调降温+检查窗帘是否需要遮阳。",
                "actions": [
                    {"description": f"感知环境→{loc}温度{temp}°C>27°C→建议空调降温至26°C"},
                    {"description": f"检查窗帘→光照{s['illuminance']:.0f}lux→建议关闭窗帘遮阳"}
                ],
                "observation": f"[Sensor] {loc}温度={temp}°C, 光照={s['illuminance']:.0f}lux",
                "answer": f"🥵 {loc}当前{temp}°C，确实偏热！物理AI已做出综合决策：\n• 建议空调降温至26°C\n• 光照{s['illuminance']:.0f}lux较强，已建议拉窗帘遮阳\n这是多设备协同决策的结果。"
            }
        else:
            return {
                "thought": f"用户感觉热，但{loc}实际温度{temp}°C尚可。检查CO2是否导致闷热感。",
                "actions": [{"description": f"感知→温度{temp}°C正常, CO2={s['co2']:.0f}ppm"}],
                "observation": f"[Sensor] {loc}温度={temp}°C, CO2={s['co2']:.0f}ppm",
                "answer": f"💨 {loc}温度{temp}°C正常，但CO2浓度{s['co2']:.0f}ppm略高，可能是闷热的原因。建议开窗通风5分钟。"
            }

    # "太暗了"
    if any(w in command for w in ["暗", "黑", "看不清"]):
        ill = s["illuminance"]
        if ill < 3000:
            state["lights"][loc] = {"is_on": True, "brightness": 80}
            save_state(state)
            return {
                "thought": f"用户觉得暗。查询{loc}光照仅{ill:.0f}lux，确实不足。物理AI决策：自动开灯80%。",
                "actions": [{"description": f"感知→光照{ill:.0f}lux<3000lux→自动开灯80%"}],
                "observation": f"[Sensor] {loc}光照={ill:.0f}lux, [Light] 已自动开启80%",
                "answer": f"💡 {loc}光照仅{ill:.0f}lux，确实偏暗。已自动开灯至80%亮度。这是物理AI的\"感知→决策→执行\"完整闭环。"
            }
        elif ill < 10000:
            state["curtains"][loc] = {"is_open": True, "position": 100}
            save_state(state)
            return {
                "thought": f"用户觉得暗。{loc}光照{ill:.0f}lux偏低。物理AI决策：拉开窗帘利用自然光。",
                "actions": [{"description": f"感知→光照{ill:.0f}lux<10000lux→拉开窗帘采光"}],
                "observation": f"[Sensor] {loc}光照={ill:.0f}lux, [Curtain] 窗帘已全开",
                "answer": f"🪟 {loc}光照{ill:.0f}lux偏暗，已拉开窗帘利用自然光。物理AI优先使用自然光源，节能环保。"
            }
        else:
            return {
                "thought": f"{loc}光照{ill:.0f}lux充足，但用户仍觉暗。可能是窗帘或灯具问题。",
                "answer": f"🤔 {loc}光照{ill:.0f}lux已经足够，但如果您觉得暗，我可以调亮灯光。"
            }

    # "闷" / "不透气"
    if any(w in command for w in ["闷", "不透气", "憋"]):
        if s["co2"] > 800:
            state["sensors"][loc]["window_open"] = True
            save_state(state)
            return {
                "thought": f"用户感觉闷。CO2={s['co2']:.0f}ppm偏高。物理AI决策：开窗通风。",
                "actions": [{"description": f"感知→CO2={s['co2']:.0f}ppm>800ppm→自动开窗通风"}],
                "observation": f"[Sensor] {loc} CO2={s['co2']:.0f}ppm",
                "answer": f"🌬️ CO2浓度{s['co2']:.0f}ppm偏高，已开窗通风。物理AI的\"感知→执行\"：发现CO2超标→自动开窗。"
            }
        return {
            "thought": f"用户感觉闷。CO2={s['co2']:.0f}ppm正常，温度{t['temp']}°C。建议检查湿度。",
            "answer": f"💧 {loc}空气指标正常（CO2={s['co2']:.0f}ppm），但湿度{t['humidity']:.0f}%。如果是湿闷，建议开启除湿。"
        }

    return None  # 非模糊指令，走正常流程

# ============ 正常指令执行 ============
def execute_command(state, command):
    """标准 ReAct 推理执行（灯光/温湿度/场景触发）"""
    cmd = command.strip()
    result = {"thought": "", "actions": [], "observation": "", "answer": ""}

    # 开灯
    m = re.search(r'(打开|开)(.+?)的?灯', cmd)
    if m:
        loc = extract_location(cmd) or "客厅"
        state["lights"][loc] = {"is_on": True, "brightness": 100}
        result["thought"] = f'用户想打开{loc}灯光 → 调用 light_control'
        result["actions"].append({"description": f'light_control(location="{loc}", action="开灯")'})
        result["observation"] = f"[LightControl] {loc}灯光已打开，亮度100%"
        result["answer"] = f"✅ {loc}的灯已打开，亮度100%"
        save_state(state)
        return result

    # 全屋关灯
    if re.search(r'关.*(所有|全屋|全部).*灯', cmd) or cmd in ["关灯", "关闭所有灯"]:
        for loc in LOCATIONS:
            if loc != "室外":
                state["lights"][loc] = {"is_on": False, "brightness": 0}
        result["thought"] = '用户想关闭全屋灯光 → 多设备协同执行'
        result["actions"].append({"description": "light_control(location=\"全屋\", action=\"关灯\")"})
        result["observation"] = f"[LightControl] 全屋灯光已关闭（{len(LOCATIONS)-1}个区域）"
        result["answer"] = "✅ 全屋灯光已关闭"
        save_state(state)
        return result

    # 单区关灯
    m = re.search(r'关(闭|掉)?(.+?)的?灯', cmd)
    if m:
        loc = extract_location(cmd) or "客厅"
        state["lights"][loc] = {"is_on": False, "brightness": 0}
        result["thought"] = f'用户想关闭{loc}灯光'
        result["actions"].append({"description": f'light_control(location="{loc}", action="关灯")'})
        result["observation"] = f"[LightControl] {loc}灯光已关闭"
        result["answer"] = f"✅ {loc}的灯已关闭"
        save_state(state)
        return result

    # 调亮度（上下文记忆）
    m = re.search(r'(调暗|调亮|调节|亮度|调到)', cmd)
    if m:
        loc = extract_location(cmd) or "客厅"
        prev = state["lights"].get(loc, {"brightness": 80})
        prev_b = prev.get("brightness", 80) if prev.get("is_on", False) else 80
        bm = re.search(r'(\d+)\s*%?', cmd)
        if bm:
            new_b = min(max(int(bm.group(1)), 0), 100)
        elif '调暗' in cmd:
            new_b = max(prev_b - 20, 10)
            result["thought"] = f'上下文记忆：{loc}上次亮度{prev_b}% → 调暗20%至{new_b}%'
        elif '调亮' in cmd:
            new_b = min(prev_b + 20, 100)
            result["thought"] = f'上下文记忆：{loc}上次亮度{prev_b}% → 调亮20%至{new_b}%'
        else:
            new_b = 50

        state["lights"][loc] = {"is_on": new_b > 0, "brightness": new_b}
        result["actions"].append({"description": f'light_control(location="{loc}", brightness={new_b})'})
        result["observation"] = f"[LightControl] {loc}亮度 {prev_b}%→{new_b}%"
        result["answer"] = f"✅ {loc}灯光已从{prev_b}%调至{new_b}%（基于上下文记忆）"
        save_state(state)
        return result

    # 温湿度
    if re.search(r'(温度|室温|湿度|多少度)', cmd):
        loc = extract_location(cmd) or "客厅"
        temp = round(24.5 + random.uniform(-1.5, 2.0), 1)
        hum = round(min(max(55 + random.uniform(-10, 15), 30), 90), 0)
        state["temperature"][loc] = {"temp": temp, "humidity": hum}
        feel = "舒适" if 20 <= temp <= 26 else ("偏冷" if temp < 20 else "偏热")
        result["thought"] = f'查询{loc}温湿度 → read_temperature'
        result["actions"].append({"description": f'read_temperature(location="{loc}")'})
        result["observation"] = f"[TempSensor] {loc}温度={temp}°C，湿度={hum}%"
        result["answer"] = f"🌡️ {loc}当前{temp}°C（体感{feel}），湿度{hum}%"
        save_state(state)
        return result

    # 早安场景
    if '早上好' in cmd:
        state["lights"]["客厅"] = {"is_on": True, "brightness": 40}
        state["temperature"]["客厅"] = {"temp": 25.0, "humidity": 60.0}
        result["thought"] = '早安场景Skill：读温湿度→调灯光→播报'
        result["actions"].append({"description": 'read_temperature(location="客厅")'})
        result["actions"].append({"description": 'light_control(location="客厅", brightness=40)'})
        result["observation"] = "[TempSensor] 25.0°C/60% | [Light] 柔光40%"
        result["answer"] = "☀️ 早安！室内25°C/60%，灯光已调至柔光模式。Have a nice day!"
        save_state(state)
        return result

    # 窗帘控制
    m = re.search(r'(拉开|打开|关闭|拉上)(.+?)窗帘', cmd)
    if m:
        loc = extract_location(cmd) or "客厅"
        is_open = "开" in m.group(1)
        state["curtains"][loc] = {"is_open": is_open, "position": 100 if is_open else 0}
        result["thought"] = f'用户想{("拉开" if is_open else "关闭")}{loc}窗帘'
        result["actions"].append({"description": f'curtain_control(location="{loc}", {"开" if is_open else "关"})'})
        result["answer"] = f"✅ {loc}窗帘已{'拉开' if is_open else '关闭'}"
        save_state(state)
        return result

    return None  # 交给模糊指令处理器

# ============ 辅助 ============
def extract_location(text):
    for loc in LOCATIONS:
        if loc in text:
            return loc
    aliases = {"起居室": "客厅", "主卧": "卧室", "卫生间": "浴室", "厕所": "浴室",
               "WC": "浴室", "办公室": "书房", "户外": "室外", "阳台": "室外"}
    for a, r in aliases.items():
        if a in text: return r
    return None

# ============ HTTP 服务器 ============
class BridgeHandler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        path = urlparse(self.path).path

        if path == '/' or path == '/index.html':
            self.serve_file('web_panel.html', 'text/html; charset=utf-8')
        elif path == '/api/state':
            state = load_state()
            self.send_json(state)
        elif path == '/api/patrol/log':
            self.send_json({"log": patrol_log, "running": patrol_running,
                           "last": time.strftime("%H:%M:%S", time.localtime(last_patrol_time)) if last_patrol_time else "从未"})
        elif path == '/api/patrol/trigger':
            report = run_environment_patrol()
            self.send_json({"status": "ok", "report": report})
        else:
            self.send_error(404)

    def do_POST(self):
        path = urlparse(self.path).path

        if path == '/api/command':
            body = self._read_body()
            try:
                data = json.loads(body)
                command = data.get('command', '')
            except: command = ''

            if not command:
                self.send_json({"error": "缺少 command"})
                return

            state = load_state()

            # 优先级1: 特殊场景（离家模式）
            if any(w in command for w in ["我出门了", "拜拜", "再见", "离家模式"]):
                steps, anomalies = execute_leave_home(state)
                result = {
                    "thought": "物理AI多设备协同：离家模式启动。感知环境→逐一关灯→关窗帘→安全检查→启动安防。",
                    "actions": [s for s in steps if s["type"] == "action"],
                    "observation": "\n".join([s["content"] for s in steps if s["type"] == "observe"]),
                    "answer": f"🏠 离家模式已启动！物理AI执行报告：\n✅ 全屋灯光已关闭\n✅ 全屋窗帘已拉上\n🔒 离家安防已布防\n⚠️ 门窗异常{anomalies}处\n\n🔐 您的家已进入安全守护模式。"
                }
                self.send_json(result)
                return

            # 优先级2: 模糊指令（物理AI：先感知再决策）
            fuzzy = handle_fuzzy_command(state, command)
            if fuzzy:
                self.send_json(fuzzy)
                return

            # 优先级3: 标准指令
            std = execute_command(state, command)
            if std:
                self.send_json(std)
                return

            # 未识别
            self.send_json({
                "thought": f'无法解析"{command}"。尝试物理AI模糊理解...',
                "actions": [{"description": "模糊指令匹配失败"}],
                "answer": f'🤔 抱歉，暂不理解"{command}"。试试：打开客厅的灯 | 现在室温多少度 | 有点冷 | 太暗了 | 我出门了 | 有人吗 | 空气怎么样'
            })

        elif path == '/api/light':
            body = self._read_body()
            try:
                data = json.loads(body)
                loc = data.get('location', '客厅')
                action = data.get('action', 'on')
                brightness = min(max(data.get('brightness', 100), 0), 100)
            except: loc, action, brightness = '客厅', 'on', 100

            state = load_state()
            state["lights"][loc] = {"is_on": action != 'off', "brightness": brightness if action != 'off' else 0}
            save_state(state)
            self.send_json({"status": "ok"})

        elif path == '/api/patrol/toggle':
            global patrol_running
            patrol_running = not patrol_running
            if patrol_running:
                t = threading.Thread(target=patrol_loop, args=(PATROL_INTERVAL,), daemon=True)
                t.start()
            self.send_json({"patrol_active": patrol_running})

        else:
            self.send_error(404)

    def _read_body(self):
        length = int(self.headers.get('Content-Length', 0))
        return self.rfile.read(length).decode('utf-8') if length > 0 else '{}'

    def serve_file(self, filename, content_type):
        filepath = os.path.join(SCRIPT_DIR, filename)
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', len(content.encode('utf-8')))
            self.end_headers()
            self.wfile.write(content.encode('utf-8'))
        except FileNotFoundError:
            self.send_error(404)

    def send_json(self, data):
        body = json.dumps(data, ensure_ascii=False, indent=2)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', len(body.encode('utf-8')))
        self.end_headers()
        self.wfile.write(body.encode('utf-8'))

    def log_message(self, format, *args):
        print(f"[{time.strftime('%H:%M:%S')}] {args[0]}")

def main():
    port = PORT
    patrol_sec = PATROL_INTERVAL
    for i, arg in enumerate(sys.argv):
        if arg == '--port' and i+1 < len(sys.argv): port = int(sys.argv[i+1])
        if arg == '--patrol-interval' and i+1 < len(sys.argv): patrol_sec = int(sys.argv[i+1])

    state = load_state()
    save_state(state)

    print(f"""
╔══════════════════════════════════════════════════════╗
║  openvela 物理AI — Web Dashboard 桥接服务器 v2.0     ║
╠══════════════════════════════════════════════════════╣
║  🌐 http://localhost:{port}                           ║
║                                                      ║
║  物理AI 核心特性:                                      ║
║  🧠 模糊指令理解 - "有点冷"/"太暗了"/"不透气"          ║
║  🔄 主动环境巡检 - 每{patrol_sec}s自主感知+决策         ║
║  📡 多传感器感知 - 光照/人体/门磁/PM2.5/CO2/噪音       ║
║  🤝 多设备协同   - 离家模式灯光+窗帘+安防联动           ║
║  💾 状态记忆     - 上下文感知+持久化                    ║
║                                                      ║
║  API:                                                ║
║  GET  /api/state        - 设备状态                    ║
║  POST /api/command      - 自然语言指令                 ║
║  GET  /api/patrol/log   - 主动巡检日志                 ║
║  GET  /api/patrol/trigger - 手动触发巡检               ║
╚══════════════════════════════════════════════════════╝
""")

    # 启动主动巡检线程
    if patrol_sec > 0:
        t = threading.Thread(target=patrol_loop, args=(patrol_sec,), daemon=True)
        t.start()

    server = http.server.HTTPServer(('0.0.0.0', port), BridgeHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        global patrol_running
        patrol_running = False
        print("\n服务器已停止")
        server.shutdown()

if __name__ == '__main__':
    main()
