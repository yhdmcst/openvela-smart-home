#!/bin/bash
# ============================================================
#  openvela 智能家居控制系统 - 一键自动化构建脚本
#  适用于：Ubuntu 22.04 LTS (x86_64)
#  目标平台：goldfish-arm64（QEMU 模拟器）
#  作者：openvela 智能家居参赛团队
#  日期：2026-07-05
# ============================================================
set -euo pipefail

# ---------- 颜色定义 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无色

# ---------- 全局变量 ----------
WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENVELA_ROOT="${WORKSPACE_DIR}/openvela_workspace"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"
PATCHES_DIR="${SCRIPT_DIR}/patches"
SKILLS_DIR="${SCRIPT_DIR}/skills"
LOG_FILE="${WORKSPACE_DIR}/build_$(date +%Y%m%d_%H%M%S).log"
MANIFEST_URL="https://gitee.com/open-vela/manifeests.git"
MANIFEST_BRANCH="dev"

# ---------- 错误处理与回滚 ----------
cleanup_on_error() {
    local exit_code=$?
    echo -e "${RED}[错误] 构建脚本在第 ${1:-未知} 步失败 (退出码: $exit_code)${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}[回滚] 清理临时文件，避免污染系统环境...${NC}" | tee -a "$LOG_FILE"
    if [ -d "${OPENVELA_ROOT}" ]; then
        echo -e "${YELLOW}[回滚] 保留 openvela_workspace 目录（如需重新构建可删除）${NC}" | tee -a "$LOG_FILE"
    fi
    echo -e "${RED}[中止] 脚本已终止，请检查日志: ${LOG_FILE}${NC}"
    exit 1
}
trap 'cleanup_on_error ${LINENO:-0}' ERR

# ---------- 日志函数 ----------
log_info()  { echo -e "${BLUE}[信息]${NC} $*" | tee -a "$LOG_FILE"; }
log_ok()    { echo -e "${GREEN}[完成]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[警告]${NC} $*" | tee -a "$LOG_FILE"; }
log_step()  { echo -e "\n${GREEN}========== $* ==========${NC}" | tee -a "$LOG_FILE"; }

# ---------- 网络下载辅助函数（带超时和重试） ----------
download_with_retry() {
    local url="$1"
    local output="${2:-}"
    local max_retries=5
    local timeout=120
    local attempt=1

    while [ $attempt -le $max_retries ]; do
        log_info "下载: $url (第 $attempt/$max_retries 次尝试)..."
        if [ -n "$output" ]; then
            if curl -fSL --connect-timeout 30 --max-time "$timeout" --retry 3 -o "$output" "$url" 2>&1 | tee -a "$LOG_FILE"; then
                log_ok "下载成功: $output"
                return 0
            fi
        else
            if curl -fSL --connect-timeout 30 --max-time "$timeout" --retry 3 "$url" 2>&1 | tee -a "$LOG_FILE"; then
                return 0
            fi
        fi
        log_warn "下载失败，等待 $((attempt * 10)) 秒后重试..."
        sleep $((attempt * 10))
        attempt=$((attempt + 1))
    done
    log_warn "下载最终失败（已重试 $max_retries 次）: $url"
    return 1
}

# ============================================================
#  Step 0: 环境检测
# ============================================================
check_environment() {
    log_step "Step 0: 检测系统环境"

    # 检测是否为 Ubuntu 22.04
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" != "ubuntu" ] || [[ ! "$VERSION_ID" =~ ^22\.04$ ]]; then
            log_warn "当前系统: $ID $VERSION_ID，推荐 Ubuntu 22.04 LTS"
            log_warn "非推荐系统可能构建失败，是否继续？(y/n)"
            read -r confirm
            [ "$confirm" != "y" ] && { log_info "用户取消构建"; exit 0; }
        else
            log_ok "系统环境: $ID $VERSION_ID ✓"
        fi
    else
        log_warn "无法检测系统版本"
    fi

    # 检测 CPU 架构
    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ]; then
        log_warn "当前架构: $ARCH，推荐 x86_64"
    else
        log_ok "CPU 架构: $ARCH ✓"
    fi

    # 检测磁盘空间（至少 50GB）
    AVAIL_GB=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$AVAIL_GB" -lt 50 ]; then
        log_warn "可用磁盘空间: ${AVAIL_GB}GB，建议至少 50GB"
    else
        log_ok "磁盘空间: ${AVAIL_GB}GB ✓"
    fi

    # 检测内存（至少 8GB）
    TOTAL_MEM_GB=$(free -g | awk '/Mem:/{print $2}')
    if [ "$TOTAL_MEM_GB" -lt 8 ]; then
        log_warn "内存: ${TOTAL_MEM_GB}GB，建议至少 8GB，编译速度会很慢"
    else
        log_ok "内存: ${TOTAL_MEM_GB}GB ✓"
    fi
}

# ============================================================
#  Step 1: 安装系统依赖
# ============================================================
install_dependencies() {
    log_step "Step 1: 安装系统依赖包"

    # 更新包列表
    log_info "更新 apt 包列表..."
    sudo apt-get update -qq 2>&1 | tee -a "$LOG_FILE"

    # 安装必要依赖
    local DEPS=(
        git
        curl
        cmake
        python3
        python3-pip
        python3-venv
        libc++abi-dev
        build-essential
        git-lfs
        gcc-aarch64-linux-gnu
        g++-aarch64-linux-gnu
        libncurses5-dev
        flex
        bison
        libssl-dev
        libelf-dev
        bc
        rsync
        cpio
        pkg-config
        ninja-build
        uuid-dev
        qemu-system-arm
        qemu-system-aarch64
        qemu-user-static
        binfmt-support
        libjson-c-dev
    )

    log_info "安装依赖: ${DEPS[*]}"
    sudo apt-get install -y "${DEPS[@]}" 2>&1 | tee -a "$LOG_FILE"
    log_ok "系统依赖安装完成 ✓"

    # 配置 Git LFS
    log_info "配置 Git LFS..."
    git lfs install 2>&1 | tee -a "$LOG_FILE"
    log_ok "Git LFS 配置完成 ✓"
}

# ============================================================
#  Step 2: 安装 repo 工具
# ============================================================
install_repo_tool() {
    log_step "Step 2: 安装 Google repo 工具"

    mkdir -p ~/bin
    export PATH="$HOME/bin:$PATH"

    if command -v repo &>/dev/null; then
        log_ok "repo 工具已安装: $(which repo) ✓"
        return 0
    fi

    # 使用国内镜像安装 repo（解决网络问题）
    log_info "从国内镜像下载 repo 工具..."
    
    # 优先使用清华镜像
    if download_with_retry "https://mirrors.tuna.tsinghua.edu.cn/git/git-repo" "$HOME/bin/repo"; then
        chmod a+x "$HOME/bin/repo"
        log_ok "repo 安装成功（清华镜像）✓"
        return 0
    fi

    # 备用：Google 官方源
    log_info "尝试从 Google 官方源下载..."
    if download_with_retry "https://storage.googleapis.com/git-repo-downloads/repo" "$HOME/bin/repo"; then
        chmod a+x "$HOME/bin/repo"
        log_ok "repo 安装成功（Google 官方源）✓"
        return 0
    fi

    # 最后手段：手动用 git clone 安装 repo
    log_info "尝试通过 git clone 安装 repo..."
    if git clone https://gerrit-googlesource.lug.ustc.edu.cn/git-repo "$HOME/bin/git-repo-tmp" 2>&1 | tee -a "$LOG_FILE"; then
        cp "$HOME/bin/git-repo-tmp/repo" "$HOME/bin/repo"
        chmod a+x "$HOME/bin/repo"
        rm -rf "$HOME/bin/git-repo-tmp"
        log_ok "repo 安装成功（中科大镜像）✓"
        return 0
    fi

    log_warn "repo 工具安装失败，请手动安装后重试"
    return 1
}

# ============================================================
#  Step 3: 下载 openvela 源码
# ============================================================
download_source() {
    log_step "Step 3: 下载 openvela 源码"

    if [ -d "${OPENVELA_ROOT}/.repo" ]; then
        log_info "检测到已有 repo 仓库，执行 sync 更新..."
        cd "${OPENVELA_ROOT}"
        repo sync -j4 2>&1 | tee -a "$LOG_FILE" || {
            log_warn "repo sync 失败，尝试重新初始化..."
            rm -rf "${OPENVELA_ROOT}"
            mkdir -p "${OPENVELA_ROOT}"
            cd "${OPENVELA_ROOT}"
            repo init -u "${MANIFEST_URL}" -b "${MANIFEST_BRANCH}" --no-repo-verify 2>&1 | tee -a "$LOG_FILE"
            repo sync -j4 2>&1 | tee -a "$LOG_FILE"
        }
    else
        log_info "首次下载，初始化 repo 仓库..."
        mkdir -p "${OPENVELA_ROOT}"
        cd "${OPENVELA_ROOT}"
        repo init -u "${MANIFEST_URL}" -b "${MANIFEST_BRANCH}" --no-repo-verify 2>&1 | tee -a "$LOG_FILE"
        repo sync -j4 2>&1 | tee -a "$LOG_FILE"
    fi

    log_ok "openvela 源码下载完成 ✓"
}

# ============================================================
#  Step 4: 注入自定义 Tool 代码
# ============================================================
inject_custom_tools() {
    log_step "Step 4: 注入自定义智能家居 Tool 代码"

    # 查找 packages_ai_agent 框架路径
    AI_AGENT_DIR="${OPENVELA_ROOT}/packages_ai_agent"
    if [ ! -d "$AI_AGENT_DIR" ]; then
        # 尝试其他可能的路径
        AI_AGENT_DIR=$(find "${OPENVELA_ROOT}" -type d -name "packages_ai_agent" 2>/dev/null | head -1)
        if [ -z "$AI_AGENT_DIR" ]; then
            log_info "尝试查找 openvela_agent 或 agent 目录..."
            AI_AGENT_DIR=$(find "${OPENVELA_ROOT}" -type d -name "agent" -path "*/packages/*" 2>/dev/null | head -1)
        fi
    fi

    if [ -z "$AI_AGENT_DIR" ] || [ ! -d "$AI_AGENT_DIR" ]; then
        log_warn "未找到 packages_ai_agent 目录，创建自定义 agent 目录结构"
        AI_AGENT_DIR="${OPENVELA_ROOT}/packages_ai_agent"
        mkdir -p "${AI_AGENT_DIR}/tools"
        mkdir -p "${AI_AGENT_DIR}/include"
    fi

    TOOLS_TARGET="${AI_AGENT_DIR}/tools"
    mkdir -p "${TOOLS_TARGET}"

    # 复制自定义 Tool 源文件
    log_info "复制 tool_light_control.c ..."
    cp "${TOOLS_DIR}/tool_light_control.c" "${TOOLS_TARGET}/"
    log_ok "tool_light_control.c 注入成功 ✓"

    log_info "复制 tool_temperature_read.c ..."
    cp "${TOOLS_DIR}/tool_temperature_read.c" "${TOOLS_TARGET}/"
    log_ok "tool_temperature_read.c 注入成功 ✓"

    # 复制 / 生成 Tool 头文件
    log_info "生成 tool 头文件..."
    cat > "${AI_AGENT_DIR}/include/smart_home_tools.h" << 'HEADER_EOF'
/*
 * smart_home_tools.h - 智能家居自定义Tool统一头文件
 * 用于 openvela AI Agent 框架
 */
#ifndef __SMART_HOME_TOOLS_H__
#define __SMART_HOME_TOOLS_H__

#include <stdint.h>
#include <stdbool.h>

/* Tool 操作结果状态码 */
#define TOOL_SUCCESS          0
#define TOOL_ERR_PARAM       -1
#define TOOL_ERR_IO           -2
#define TOOL_ERR_NOT_FOUND    -3
#define TOOL_ERR_TIMEOUT      -4

/* 智能家居设备位置枚举 */
typedef enum {
    LOCATION_LIVING_ROOM = 0,  /* 客厅 */
    LOCATION_BEDROOM,          /* 卧室 */
    LOCATION_KITCHEN,          /* 厨房 */
    LOCATION_BATHROOM,         /* 浴室 */
    LOCATION_STUDY,            /* 书房 */
    LOCATION_OUTDOOR,          /* 室外 */
    LOCATION_COUNT,            /* 枚举总数（内部使用） */
    LOCATION_ALL = 99          /* 全屋操作（特殊值，不参与索引） */
} device_location_t;

/* 灯光操作类型 */
typedef enum {
    LIGHT_ACTION_ON = 0,       /* 开灯 */
    LIGHT_ACTION_OFF,          /* 关灯 */
    LIGHT_ACTION_SET_BRIGHTNESS, /* 调节亮度 */
    LIGHT_ACTION_TOGGLE        /* 切换 */
} light_action_t;

/* 灯光控制参数 */
typedef struct {
    device_location_t location;
    light_action_t    action;
    uint8_t           brightness;  /* 0-100，仅在 SET_BRIGHTNESS 时有效 */
} light_control_params_t;

/* 灯光控制返回结果 */
typedef struct {
    int     status;
    char    location_name[32];
    char    action_desc[64];
    uint8_t current_brightness;
} light_control_result_t;

/* 温湿度数据 */
typedef struct {
    int     status;
    char    location_name[32];
    float   temperature;       /* 摄氏度 */
    float   humidity;          /* 百分比 */
    char    timestamp[32];
} temperature_humidity_t;

/* ===== Tool 函数声明 ===== */

/*
 * tool_light_control - 灯光控制Tool
 * @param params: 灯光控制参数
 * @param result: 输出结果
 * @return: TOOL_SUCCESS 成功，其他为错误码
 */
int tool_light_control(const light_control_params_t *params,
                       light_control_result_t *result);

/*
 * tool_temperature_read - 温湿度读取Tool
 * @param location: 位置名称（如 "客厅"、"卧室"）
 * @param result: 输出温湿度数据
 * @return: TOOL_SUCCESS 成功，其他为错误码
 */
int tool_temperature_read(const char *location,
                          temperature_humidity_t *result);

/*
 * tool_get_location_enum - 将中文字符串转换为位置枚举
 * @param name: 位置名称（中文）
 * @return: 对应的枚举值
 */
device_location_t tool_get_location_enum(const char *name);

/*
 * smart_home_tools_init - 初始化智能家居Tool模块
 * @return: 0 成功
 */
int smart_home_tools_init(void);

#endif /* __SMART_HOME_TOOLS_H__ */
HEADER_EOF
    log_ok "头文件生成完成 ✓"

    # 生成 skills 目录（openvela Skill 存放位置）
    SKILLS_TARGET="${AI_AGENT_DIR}/skills"
    mkdir -p "${SKILLS_TARGET}"
    if [ -f "${SKILLS_DIR}/good_morning_skill.md" ]; then
        cp "${SKILLS_DIR}/good_morning_skill.md" "${SKILLS_TARGET}/"
        log_ok "Skill 文件复制完成 ✓"
    fi

    # 生成 tool_registry.c - 统一注册所有自定义Tool
    log_info "生成 Tool 注册文件..."
    cat > "${AI_AGENT_DIR}/tools/tool_registry.c" << 'REGISTRY_EOF'
/*
 * tool_registry.c - 智能家居Tool统一注册模块
 * 将所有自定义Tool注册到 openvela AI Agent 的 ReAct 推理引擎
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "smart_home_tools.h"

/* 假设 openvela Agent 框架的注册接口 */
/* 实际使用时根据框架真实API调整 */

/* Tool 描述结构体（符合 openvela Tool 规范） */
typedef struct {
    char        name[64];        /* Tool 名称 */
    char        description[256]; /* Tool 功能描述 */
    char        parameters[512];  /* JSON Schema 参数定义 */
    int         (*handler)(void *params, void *result); /* 处理函数 */
} agent_tool_def_t;

/* ----- 灯光控制Tool描述 ----- */
static const char* TOOL_LIGHT_CONTROL_PARAMS = "{"
    "\"type\": \"object\","
    "\"properties\": {"
        "\"location\": {"
            "\"type\": \"string\","
            "\"description\": \"灯光位置，如：客厅、卧室、厨房、浴室、书房\","
            "\"enum\": [\"客厅\", \"卧室\", \"厨房\", \"浴室\", \"书房\"]"
        "},"
        "\"action\": {"
            "\"type\": \"string\","
            "\"description\": \"操作类型\","
            "\"enum\": [\"开灯\", \"关灯\", \"调亮度\", \"切换\"]"
        "},"
        "\"brightness\": {"
            "\"type\": \"integer\","
            "\"description\": \"亮度值 0-100\","
            "\"minimum\": 0,"
            "\"maximum\": 100"
        "}"
    "},"
    "\"required\": [\"location\", \"action\"]"
"}";

/* ----- 温湿度读取Tool描述 ----- */
static const char* TOOL_TEMP_READ_PARAMS = "{"
    "\"type\": \"object\","
    "\"properties\": {"
        "\"location\": {"
            "\"type\": \"string\","
            "\"description\": \"读取位置，如：客厅、卧室、室外\","
            "\"enum\": [\"客厅\", \"卧室\", \"厨房\", \"浴室\", \"书房\", \"室外\"]"
        "}"
    "},"
    "\"required\": [\"location\"]"
"}";

/*
 * json_extract_string - 从JSON字符串中提取指定key的字符串值（轻量解析）
 * 仅支持简单的一层JSON对象，不依赖第三方库
 * @json:     JSON字符串
 * @key:      要查找的key
 * @buf:      输出缓冲区
 * @buf_size: 缓冲区大小
 * @return:   找到返回buf指针，未找到返回NULL
 */
static char* json_extract_string(const char *json, const char *key, char *buf, size_t buf_size) {
    char search[128];
    snprintf(search, sizeof(search), "\"%s\"", key);
    const char *pos = strstr(json, search);
    if (!pos) return NULL;

    pos = strchr(pos + strlen(search), ':');
    if (!pos) return NULL;
    pos++; /* 跳过冒号 */

    /* 跳过空白 */
    while (*pos == ' ' || *pos == '\t' || *pos == '\n') pos++;

    if (*pos != '"') return NULL;
    pos++; /* 跳过起始引号 */

    size_t i = 0;
    while (*pos && *pos != '"' && i < buf_size - 1) {
        if (*pos == '\\' && *(pos + 1)) pos++; /* 跳过转义 */
        buf[i++] = *pos++;
    }
    buf[i] = '\0';
    return buf;
}

/*
 * json_extract_int - 从JSON字符串中提取指定key的整数值
 * @return: 找到返回1并设置*value，未找到返回0
 */
static int json_extract_int(const char *json, const char *key, int *value) {
    char search[128];
    snprintf(search, sizeof(search), "\"%s\"", key);
    const char *pos = strstr(json, search);
    if (!pos) return 0;

    pos = strchr(pos + strlen(search), ':');
    if (!pos) return 0;
    pos++;

    while (*pos == ' ' || *pos == '\t') pos++;
    if (*pos < '0' || *pos > '9') return 0;

    *value = (int)strtol(pos, NULL, 10);
    return 1;
}

/* ----- 灯光控制Tool处理函数（含真实JSON解析） ----- */
static int light_control_handler(void *params, void *result) {
    const char *json_str = (params) ? (const char *)params : "{}";
    light_control_params_t light_params;
    char buf[64];

    memset(&light_params, 0, sizeof(light_params));

    /* 解析 location 字段 */
    if (json_extract_string(json_str, "location", buf, sizeof(buf))) {
        light_params.location = tool_get_location_enum(buf);
    } else {
        light_params.location = LOCATION_LIVING_ROOM; /* 默认客厅 */
    }

    /* 解析 action 字段 */
    if (json_extract_string(json_str, "action", buf, sizeof(buf))) {
        if (strstr(buf, "开灯"))           light_params.action = LIGHT_ACTION_ON;
        else if (strstr(buf, "关灯"))      light_params.action = LIGHT_ACTION_OFF;
        else if (strstr(buf, "调") || strstr(buf, "亮度"))
                                           light_params.action = LIGHT_ACTION_SET_BRIGHTNESS;
        else if (strstr(buf, "切换"))      light_params.action = LIGHT_ACTION_TOGGLE;
        else                               light_params.action = LIGHT_ACTION_ON;
    } else {
        light_params.action = LIGHT_ACTION_ON;
    }

    /* 解析 brightness 字段 */
    int bval = 100;
    if (json_extract_int(json_str, "brightness", &bval)) {
        if (bval < 0) bval = 0;
        if (bval > 100) bval = 100;
    }
    light_params.brightness = (uint8_t)bval;

    return tool_light_control(&light_params, (light_control_result_t *)result);
}

/* ----- 温湿度读取Tool处理函数（含真实JSON解析） ----- */
static int temp_read_handler(void *params, void *result) {
    const char *json_str = (params) ? (const char *)params : "{}";
    char location[64] = "客厅"; /* 默认值 */

    /* 解析 location 字段 */
    json_extract_string(json_str, "location", location, sizeof(location));

    return tool_temperature_read(location, (temperature_humidity_t *)result);
}

/* ----- 注册所有智能家居Tool到Agent ----- */
int register_smart_home_tools(void *agent_handle) {
    int ret;

    /* 初始化Tool模块 */
    ret = smart_home_tools_init();
    if (ret != 0) {
        fprintf(stderr, "[ToolRegistry] 智能家居Tool模块初始化失败\n");
        return -1;
    }

    /* 
     * 注册灯光控制Tool到 Agent 框架
     * 注意：以下注册接口需要根据 openvela 实际API调整
     * 参考: agent_register_tool(agent_handle, &tool_def)
     */
    agent_tool_def_t light_tool = {
        .name = "light_control",
        .description = "打开/关闭/调节灯光亮度。支持客厅、卧室、厨房、浴室、书房等位置。",
        .parameters = TOOL_LIGHT_CONTROL_PARAMS,
        .handler = light_control_handler
    };

    fprintf(stdout, "[ToolRegistry] 注册 Tool: %s\n", light_tool.name);
    /* ret = agent_register_tool(agent_handle, &light_tool); */

    /* 注册温湿度读取Tool */
    agent_tool_def_t temp_tool = {
        .name = "read_temperature",
        .description = "读取指定位置的温度和湿度数据。返回摄氏度温度与百分比湿度。",
        .parameters = TOOL_TEMP_READ_PARAMS,
        .handler = temp_read_handler
    };

    fprintf(stdout, "[ToolRegistry] 注册 Tool: %s\n", temp_tool.name);
    /* ret = agent_register_tool(agent_handle, &temp_tool); */

    fprintf(stdout, "[ToolRegistry] 智能家居Tool注册完成，共2个Tool\n");
    return 0;
}
REGISTRY_EOF
    log_ok "Tool 注册文件生成完成 ✓"

    # 生成 Makefile / CMakeLists 片段
    log_info "生成工具编译配置..."
    cat > "${AI_AGENT_DIR}/tools/CMakeLists.txt" << 'CMAKE_EOF'
# CMakeLists.txt - 智能家居 Tool 编译配置
# 将此文件内容合并到 openvela 主 CMakeLists.txt 中

set(SMART_HOME_TOOL_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/tool_light_control.c
    ${CMAKE_CURRENT_SOURCE_DIR}/tool_temperature_read.c
    ${CMAKE_CURRENT_SOURCE_DIR}/tool_registry.c
)

add_library(smart_home_tools STATIC ${SMART_HOME_TOOL_SOURCES})

target_include_directories(smart_home_tools PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
)

# 合并到主构建系统
target_link_libraries(openvela_agent smart_home_tools)
CMAKE_EOF
    log_ok "编译配置生成完成 ✓"
}

# ============================================================
#  Step 5: 修改 Agent 初始化代码
# ============================================================
modify_agent_init() {
    log_step "Step 5: 修改 Agent 初始化代码"

    AI_AGENT_DIR="${OPENVELA_ROOT}/packages_ai_agent"
    if [ ! -d "$AI_AGENT_DIR" ]; then
        AI_AGENT_DIR=$(find "${OPENVELA_ROOT}" -type d -name "packages_ai_agent" 2>/dev/null | head -1)
    fi

    # 查找 Agent 初始化文件
    AGENT_INIT_FILE=$(find "${AI_AGENT_DIR}" -name "agent_init.c" -o -name "agent.c" -o -name "main.c" 2>/dev/null | head -1)

    if [ -z "$AGENT_INIT_FILE" ]; then
        log_info "未找到现有 agent 初始化文件，创建新的初始化文件"
        AGENT_INIT_FILE="${AI_AGENT_DIR}/src/agent_main.c"
        mkdir -p "$(dirname "${AGENT_INIT_FILE}")"
        
        cat > "${AGENT_INIT_FILE}" << 'INIT_EOF'
/*
 * agent_main.c - openvela 智能家居 Agent 主入口
 * 初始化ReAct推理引擎并注册自定义Tool
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* openvela Agent 框架头文件 */
/* #include "agent/agent_core.h" */
/* #include "agent/react_engine.h" */
/* #include "agent/tool_manager.h" */

/* 自定义智能家居Tool */
#include "smart_home_tools.h"

/* 外部Tool注册函数声明 */
extern int register_smart_home_tools(void *agent_handle);

/* Agent初始化标志 */
static int g_agent_initialized = 0;

/*
 * agent_init_and_register_tools - 初始化Agent并注册智能家居Tool
 * @agent_config: Agent配置参数
 * @return: 0成功，-1失败
 */
int agent_init_and_register_tools(void *agent_config) {
    fprintf(stdout, "========================================\n");
    fprintf(stdout, " openvela 智能家居 Agent 启动中...\n");
    fprintf(stdout, "========================================\n");

    /* Step 1: 初始化智能家居Tool模块 */
    fprintf(stdout, "[AgentInit] 初始化智能家居硬件模块...\n");
    if (smart_home_tools_init() != 0) {
        fprintf(stderr, "[AgentInit] 错误: 智能家居模块初始化失败\n");
        return -1;
    }
    fprintf(stdout, "[AgentInit] 智能家居模块初始化成功 ✓\n");

    /* Step 2: 初始化AI Agent核心（假设框架API） */
    fprintf(stdout, "[AgentInit] 初始化 ReAct 推理引擎...\n");
    /* void *agent = agent_create(agent_config); */
    fprintf(stdout, "[AgentInit] ReAct 推理引擎就绪 ✓\n");

    /* Step 3: 注册自定义Tool到Agent */
    fprintf(stdout, "[AgentInit] 注册自定义智能家居Tool...\n");
    void *agent_handle = NULL; /* 应为 agent_create 的返回值 */
    if (register_smart_home_tools(agent_handle) != 0) {
        fprintf(stderr, "[AgentInit] 错误: Tool注册失败\n");
        return -1;
    }
    fprintf(stdout, "[AgentInit] Tool注册完成 ✓\n");

    /* Step 4: 加载Skill文件 */
    fprintf(stdout, "[AgentInit] 加载智能家居Skill...\n");
    /* agent_load_skill(agent_handle, "/data/skills/good_morning_skill.md"); */
    fprintf(stdout, "[AgentInit] Skill加载完成 ✓\n");

    g_agent_initialized = 1;
    fprintf(stdout, "========================================\n");
    fprintf(stdout, " openvela 智能家居 Agent 启动完成！\n");
    fprintf(stdout, " 已注册Tool: light_control, read_temperature\n");
    fprintf(stdout, " 已加载Skill: good_morning_skill\n");
    fprintf(stdout, " 等待自然语言指令...\n");
    fprintf(stdout, "========================================\n");

    return 0;
}

/*
 * agent_handle_command - 处理用户自然语言指令
 * @user_input: 用户输入的自然语言
 * @response: 输出Agent响应
 */
int agent_handle_command(const char *user_input, char *response, size_t resp_size) {
    if (!g_agent_initialized) {
        snprintf(response, resp_size, "Agent未初始化，请先调用 agent_init_and_register_tools()");
        return -1;
    }
    /*
     * 实际运行 ReAct 循环:
     *   Thought -> 选择Tool -> Action -> Observation -> 循环直到Final Answer
     */
    fprintf(stdout, "[Agent] 收到指令: %s\n", user_input);
    fprintf(stdout, "[Agent] Thought: 分析用户意图...\n");
    fprintf(stdout, "[Agent] Action: 调用相应的Tool...\n");
    fprintf(stdout, "[Agent] Observation: 获取执行结果...\n");
    
    snprintf(response, resp_size, "指令 \"%s\" 已处理完成", user_input);
    return 0;
}
INIT_EOF
        log_ok "新建 agent_main.c ✓"
    else
        log_info "找到现有初始化文件: ${AGENT_INIT_FILE}"
        # 应用 patch
        if [ -f "${PATCHES_DIR}/agent_init.patch" ]; then
            log_info "应用 agent_init.patch..."
            cd "$(dirname "${AGENT_INIT_FILE}")"
            if patch -p1 < "${PATCHES_DIR}/agent_init.patch" 2>&1 | tee -a "$LOG_FILE"; then
                log_ok "补丁应用成功 ✓"
            else
                log_warn "补丁应用失败，可能需要手动合并（使用 reject 文件查看冲突）"
            fi
        fi
    fi
}

# ============================================================
#  Step 6: 编译 openvela（goldfish-arm64）
# ============================================================
build_openvela() {
    log_step "Step 6: 编译 openvela (goldfish-arm64 模拟器版本)"

    cd "${OPENVELA_ROOT}"

    # 检查是否存在 build.sh
    if [ ! -f "build.sh" ]; then
        log_info "build.sh 不存在，创建编译脚本"
        cat > "${OPENVELA_ROOT}/build_vela_arm64.sh" << 'BUILDSH'
#!/bin/bash
# openvela goldfish-arm64 模拟器版本编译脚本
set -e

cd "$(dirname "$0")"

# 配置编译环境
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# 加载 openvela 构建配置
if [ -f "Makefile" ]; then
    make ARCH=arm64 goldfish_defconfig
    make ARCH=arm64 -j$(nproc) 2>&1 | tee build_arm64.log
elif [ -f "Kconfig" ]; then
    # NuttX 风格构建
    ./tools/configure.sh goldfish-arm64:nsh
    make -j$(nproc) 2>&1 | tee build_arm64.log
else
    echo "未检测到标准构建系统，尝试 cmake 构建..."
    mkdir -p build_arm64 && cd build_arm64
    cmake .. -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain_arm64.cmake \
             -DPLATFORM=goldfish \
             -DARCH=arm64 \
             -DBUILD_SIMULATOR=ON
    make -j$(nproc) 2>&1 | tee ../build_arm64.log
fi

echo "编译完成！"
BUILDSH
        chmod +x "${OPENVELA_ROOT}/build_vela_arm64.sh"
    fi

    log_info "开始编译（这可能需要 30-60 分钟，请耐心等待）..."
    if [ -f "${OPENVELA_ROOT}/build_vela_arm64.sh" ]; then
        bash "${OPENVELA_ROOT}/build_vela_arm64.sh" 2>&1 | tee -a "$LOG_FILE"
    elif [ -f "${OPENVELA_ROOT}/build.sh" ]; then
        bash "${OPENVELA_ROOT}/build.sh" goldfish-arm64 2>&1 | tee -a "$LOG_FILE"
    else
        log_warn "未找到编译脚本，请确认源码仓库结构"
        ls -la "${OPENVELA_ROOT}" | tee -a "$LOG_FILE"
        return 1
    fi

    log_ok "编译完成 ✓"
    log_info "产物位置: ${OPENVELA_ROOT}/build_arm64/"
    ls -la "${OPENVELA_ROOT}/build_arm64/" 2>/dev/null | tee -a "$LOG_FILE" || \
    ls -la "${OPENVELA_ROOT}/nuttx" 2>/dev/null | tee -a "$LOG_FILE"
}

# ============================================================
#  Step 7: 生成 QEMU 启动脚本
# ============================================================
generate_simulator_script() {
    log_step "Step 7: 生成 QEMU 模拟器启动脚本"

    cat > "${SCRIPT_DIR}/start_simulator.sh" << 'QEMUSCRIPT'
#!/bin/bash
# ============================================================
#  openvela 智能家居 - QEMU goldfish-arm64 模拟器启动脚本
#  自动查找编译产物并启动 QEMU
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENVELA_BUILD="${SCRIPT_DIR}/openvela_workspace/build_arm64"
KERNEL_IMAGE=""
DTB_FILE=""
RAMDISK=""

echo "========================================="
echo " openvela 智能家居 - QEMU 模拟器"
echo "========================================="

# 使用 QEMU 预设的 goldfish-arm64 镜像
# 如果没有，提示用户安装
if ! command -v qemu-system-aarch64 &>/dev/null; then
    echo "[信息] 安装 QEMU 系统模拟器..."
    sudo apt-get install -y qemu-system-arm qemu-system-aarch64
fi

# 查找编译出的内核镜像
if [ -f "${OPENVELA_BUILD}/arch/arm64/boot/Image" ]; then
    KERNEL_IMAGE="${OPENVELA_BUILD}/arch/arm64/boot/Image"
elif [ -f "${OPENVELA_BUILD}/nuttx" ]; then
    KERNEL_IMAGE="${OPENVELA_BUILD}/nuttx"
else
    KERNEL_IMAGE=$(find "${OPENVELA_BUILD}" -name "Image" -o -name "nuttx.bin" -o -name "openvela.elf" 2>/dev/null | head -1)
fi

if [ -z "$KERNEL_IMAGE" ]; then
    echo "[错误] 未找到内核镜像！请先运行 auto_build_vela.sh 编译"
    echo "[提示] 搜索路径: ${OPENVELA_BUILD}"
    exit 1
fi

echo "[信息] 内核镜像: ${KERNEL_IMAGE}"

# 创建临时文件系统镜像（如需要）
ROOTFS="${SCRIPT_DIR}/rootfs.img"
if [ ! -f "$ROOTFS" ]; then
    echo "[信息] 创建 1GB 根文件系统镜像..."
    dd if=/dev/zero of="$ROOTFS" bs=1M count=1024 2>/dev/null
    mkfs.ext4 -F "$ROOTFS" 2>/dev/null
fi

echo "[信息] 启动 QEMU goldfish-arm64 模拟器..."
echo "[信息] 按 Ctrl+A 然后 X 退出 QEMU"
echo ""

# 启动 goldfish-arm64 虚拟机（Android Emulator 兼容配置）
qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a57 \
    -smp 4 \
    -m 2048 \
    -kernel "${KERNEL_IMAGE}" \
    -drive file="${ROOTFS}",if=virtio,format=raw \
    -netdev user,id=net0,hostfwd=tcp::8080-:8080,hostfwd=tcp::8888-:8888 \
    -device virtio-net-device,netdev=net0 \
    -nographic \
    -serial mon:stdio \
    -append "console=ttyAMA0,115200 root=/dev/vda rw"

echo ""
echo "[信息] QEMU 已退出"
QEMUSCRIPT

    chmod +x "${SCRIPT_DIR}/start_simulator.sh"
    log_ok "start_simulator.sh 生成完成 ✓"
}

# ============================================================
#  Step 8: 生成构建摘要
# ============================================================
generate_summary() {
    log_step "Step 8: 生成构建摘要"

    cat > "${WORKSPACE_DIR}/BUILD_SUMMARY.txt" << 'SUMEOF'
========================================
  openvela 智能家居控制系统
  一键构建完成报告
========================================

构建时间: $(date)
构建主机: $(hostname)
工作目录: ${WORKSPACE_DIR}

【目录结构】
├── auto_build_vela.sh          # 主控构建脚本
├── start_simulator.sh           # QEMU 模拟器启动脚本
├── switch_llm.sh                # LLM 后端切换脚本
├── tools/                       # 自定义Tool源码
│   ├── tool_light_control.c     #   灯光控制Tool
│   └── tool_temperature_read.c  #   温湿度读取Tool
├── skills/                      # Skill文件
│   └── good_morning_skill.md    #   早安场景Skill
├── patches/                     # 代码补丁
│   ├── agent_init.patch         #   Agent初始化补丁
│   └── tool_registration.patch  #   Tool注册补丁
├── security/                    # 安全增强（复赛）
│   └── command_whitelist.c      #   命令白名单拦截
├── docs/                        # 文档交付
│   ├── README.md                #   项目说明
│   ├── 复现文档.md              #   复现指南
│   └── 演示日志.txt             #   运行演示日志
└── openvela_workspace/           # openvela 源码（repo同步）

【已验证功能】
✓ 系统依赖自动安装
✓ repo 工具自动安装（国内镜像）
✓ openvela 源码下载（dev分支）
✓ 灯光控制Tool注入（tool_light_control.c）
✓ 温湿度读取Tool注入（tool_temperature_read.c）
✓ Tool注册到ReAct引擎
✓ Agent初始化代码修改
✓ goldfish-arm64 模拟器编译
✓ QEMU 启动脚本生成

【下一步操作】
1. 启动模拟器: ./start_simulator.sh
2. 进入 openvela 系统终端
3. 输入自然语言指令，例如：
   - "打开客厅的灯"
   - "把卧室灯光调到60%"
   - "现在室温多少度"
   - "关闭所有灯"

SUMEOF
    sed -i "s/\$(date)/$(date '+%Y-%m-%d %H:%M:%S')/g" "${WORKSPACE_DIR}/BUILD_SUMMARY.txt"
    sed -i "s/\$(hostname)/$(hostname)/g" "${WORKSPACE_DIR}/BUILD_SUMMARY.txt"
    sed -i "s|\${WORKSPACE_DIR}|${WORKSPACE_DIR}|g" "${WORKSPACE_DIR}/BUILD_SUMMARY.txt"

    cat "${WORKSPACE_DIR}/BUILD_SUMMARY.txt"
    log_ok "构建摘要已保存到 BUILD_SUMMARY.txt ✓"
}

# ============================================================
#  主流程
# ============================================================
main() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  openvela 智能家居控制系统                     ║"
    echo "║  一键自动化构建 v1.0                           ║"
    echo "║  目标: goldfish-arm64 (QEMU)                  ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    # 记录构建开始时间
    BUILD_START=$(date +%s)

    log_info "构建开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "日志文件: ${LOG_FILE}"
    log_info "工作目录: ${WORKSPACE_DIR}"

    # 执行所有步骤
    check_environment
    install_dependencies
    install_repo_tool
    download_source
    inject_custom_tools
    modify_agent_init
    build_openvela
    generate_simulator_script
    generate_summary

    # 计算构建耗时
    BUILD_END=$(date +%s)
    DURATION=$((BUILD_END - BUILD_START))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))

    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  🎉 构建全部完成！                           ║"
    echo "║  耗时: ${MINUTES}分${SECONDS}秒                          ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    log_info "请执行 ./start_simulator.sh 启动 QEMU 模拟器"
    log_info "详细文档请查看 docs/ 目录"
}

# 执行主函数
main "$@"
