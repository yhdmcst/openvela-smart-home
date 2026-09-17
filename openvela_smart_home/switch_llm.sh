#!/bin/bash
# ============================================================
#  LLM 后端配置切换脚本
#  支持快速切换 DeepSeek / 通义千问 的 API 配置
#  适用于 openvela AI Agent 框架
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/openvela_workspace/packages_ai_agent/config"
CONFIG_FILE="${CONFIG_DIR}/llm_config.h"
BACKUP_DIR="${CONFIG_DIR}/backups"

# ---------- 颜色 ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ---------- 确保目录存在 ----------
mkdir -p "${CONFIG_DIR}" "${BACKUP_DIR}"

# ============================================================
#  LLM 配置模板
# ============================================================

# ----- DeepSeek API 配置 -----
generate_deepseek_config() {
    cat > "${CONFIG_FILE}" << 'DEEPSEEK_EOF'
/*
 * llm_config.h - LLM 后端配置
 * 当前后端: DeepSeek
 *
 * 配置说明：
 * 1. 请将 YOUR_DEEPSEEK_API_KEY 替换为你的 API Key
 *    获取地址: https://platform.deepseek.com/api_keys
 * 2. DeepSeek 推荐模型: deepseek-chat (V3) 或 deepseek-reasoner (R1)
 * 3. 免费额度: 注册即送 500万 tokens
 */
#ifndef __LLM_CONFIG_H__
#define __LLM_CONFIG_H__

/* ===== DeepSeek API 配置 ===== */
#define LLM_BACKEND_NAME        "DeepSeek"
#define LLM_API_BASE_URL        "https://api.deepseek.com/v1"
#define LLM_API_KEY             "YOUR_DEEPSEEK_API_KEY"    /* ← 请替换为你的 API Key */
#define LLM_MODEL_NAME          "deepseek-chat"             /* 推荐: deepseek-chat / deepseek-reasoner */

/* ===== 请求参数 ===== */
#define LLM_MAX_TOKENS          2048
#define LLM_TEMPERATURE         0.7
#define LLM_TOP_P               0.9
#define LLM_TIMEOUT_MS          30000  /* 30秒超时 */

/* ===== System Prompt（智能家居场景专用） ===== */
#define LLM_SYSTEM_PROMPT \
    "你是一个智能家居控制助手。你能够：\n" \
    "1. 控制灯光：开灯、关灯、调节亮度（0-100%）\n" \
    "2. 读取温湿度：支持客厅、卧室、厨房、浴室、书房\n" \
    "3. 根据用户意图，选择合适的Tool执行操作\n" \
    "请以简洁友好的方式回应用户，中文优先。"

/* ===== ReAct 推理引擎配置 ===== */
#define REACT_MAX_ITERATIONS     10     /* 最大推理循环次数 */
#define REACT_STOP_TOKENS        "Final Answer:"

/* ===== 国内网络优化（如有代理请配置） ===== */
/* #define LLM_HTTP_PROXY        "http://127.0.0.1:7890" */
/* #define LLM_HTTPS_PROXY       "http://127.0.0.1:7890" */

#endif /* __LLM_CONFIG_H__ */
DEEPSEEK_EOF
}

# ----- 通义千问 API 配置 -----
generate_qwen_config() {
    cat > "${CONFIG_FILE}" << 'QWEN_EOF'
/*
 * llm_config.h - LLM 后端配置
 * 当前后端: 通义千问 (Qwen)
 *
 * 配置说明：
 * 1. 请将 YOUR_DASHSCOPE_API_KEY 替换为你的 API Key
 *    获取地址: https://dashscope.console.aliyun.com/apiKey
 * 2. 推荐模型: qwen-max / qwen-plus / qwen-turbo
 * 3. 新用户有免费试用额度 (100万 tokens)
 */
#ifndef __LLM_CONFIG_H__
#define __LLM_CONFIG_H__

/* ===== 通义千问 API 配置 ===== */
#define LLM_BACKEND_NAME        "通义千问"
#define LLM_API_BASE_URL        "https://dashscope.aliyuncs.com/compatible-mode/v1"
#define LLM_API_KEY             "YOUR_DASHSCOPE_API_KEY"    /* ← 请替换为你的 API Key */
#define LLM_MODEL_NAME          "qwen-plus"                  /* 推荐: qwen-max / qwen-plus / qwen-turbo */

/* ===== 请求参数 ===== */
#define LLM_MAX_TOKENS          2048
#define LLM_TEMPERATURE         0.7
#define LLM_TOP_P               0.9
#define LLM_TIMEOUT_MS          30000  /* 30秒超时 */

/* ===== System Prompt（智能家居场景专用） ===== */
#define LLM_SYSTEM_PROMPT \
    "你是一个智能家居控制助手，运行在 openvela 嵌入式平台上。你能够：\n" \
    "1. 控制灯光：开灯、关灯、调节亮度（0-100%）\n" \
    "2. 读取温湿度：支持客厅、卧室、厨房、浴室、书房、室外\n" \
    "3. 场景联动：支持早安模式、离家模式、晚安模式等预设场景\n" \
    "4. 根据用户自然语言意图，自动选择合适的Tool执行操作\n" \
    "请以简洁友好的方式回应用户，中文优先。"

/* ===== ReAct 推理引擎配置 ===== */
#define REACT_MAX_ITERATIONS     10     /* 最大推理循环次数 */
#define REACT_STOP_TOKENS        "Final Answer:"

/* ===== 通义千问特定配置 ===== */
#define LLM_ENABLE_SEARCH        false  /* 是否启用联网搜索（需额外申请） */

/* ===== 国内网络连接（通义千问国内可直接访问） ===== */
/* #define LLM_HTTP_PROXY        "http://127.0.0.1:7890" */

#endif /* __LLM_CONFIG_H__ */
QWEN_EOF
}

# ----- 本地 Ollama 配置（离线备用） -----
generate_ollama_config() {
    cat > "${CONFIG_FILE}" << 'OLLAMA_EOF'
/*
 * llm_config.h - LLM 后端配置
 * 当前后端: Ollama (本地模型)
 *
 * 配置说明：
 * 1. 先安装 Ollama: curl -fsSL https://ollama.com/install.sh | sh
 * 2. 拉取模型: ollama pull qwen2.5:7b
 * 3. 本地推理，无需联网，隐私安全
 */
#ifndef __LLM_CONFIG_H__
#define __LLM_CONFIG_H__

/* ===== Ollama 本地 API 配置 ===== */
#define LLM_BACKEND_NAME        "Ollama (本地)"
#define LLM_API_BASE_URL        "http://127.0.0.1:11434/v1"
#define LLM_API_KEY             "ollama"                     /* Ollama本地不需要API Key */
#define LLM_MODEL_NAME          "qwen2.5:7b"                 /* 推荐: qwen2.5:7b / llama3:8b */

/* ===== 请求参数 ===== */
#define LLM_MAX_TOKENS          2048
#define LLM_TEMPERATURE         0.7
#define LLM_TOP_P               0.9
#define LLM_TIMEOUT_MS          60000  /* 本地模型推理较慢，60秒超时 */

/* ===== System Prompt ===== */
#define LLM_SYSTEM_PROMPT \
    "你是一个智能家居控制助手。你能够控制灯光和读取温湿度。" \
    "收到用户指令后，选择最合适的Tool执行，然后返回结果。"

/* ===== ReAct 推理引擎配置 ===== */
#define REACT_MAX_ITERATIONS     8
#define REACT_STOP_TOKENS        "Final Answer:"

#endif /* __LLM_CONFIG_H__ */
OLLAMA_EOF
}

# ============================================================
#  主菜单
# ============================================================
show_menu() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  openvela 智能家居 - LLM 后端切换工具       ║"
    echo "╠══════════════════════════════════════════════╣"
    echo "║  当前后端: ${GREEN}$(grep 'LLM_BACKEND_NAME' "${CONFIG_FILE}" 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/' || echo "未配置")${NC}"
    echo "╠══════════════════════════════════════════════╣"
    echo "║  1) DeepSeek    - api.deepseek.com           ║"
    echo "║  2) 通义千问     - dashscope.aliyuncs.com     ║"
    echo "║  3) Ollama 本地  - 127.0.0.1:11434           ║"
    echo "║  4) 查看当前配置                              ║"
    echo "║  5) 测试 API 连通性                           ║"
    echo "║  0) 退出                                      ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    echo -n "请选择 [0-5]: "
}

# ============================================================
#  备份与切换
# ============================================================
switch_backend() {
    local backend="$1"

    # 备份当前配置
    if [ -f "${CONFIG_FILE}" ]; then
        local backup_name="llm_config_$(date +%Y%m%d_%H%M%S).h"
        cp "${CONFIG_FILE}" "${BACKUP_DIR}/${backup_name}"
        echo -e "${YELLOW}[备份] 当前配置已保存至: ${backup_name}${NC}"
    fi

    # 生成新配置
    case "$backend" in
        1|deepseek)
            generate_deepseek_config
            echo -e "${GREEN}[切换] LLM 后端已切换为: DeepSeek${NC}"
            ;;
        2|qwen)
            generate_qwen_config
            echo -e "${GREEN}[切换] LLM 后端已切换为: 通义千问${NC}"
            ;;
        3|ollama)
            generate_ollama_config
            echo -e "${GREEN}[切换] LLM 后端已切换为: Ollama 本地${NC}"
            ;;
        *)
            echo -e "${RED}[错误] 未知后端: $backend${NC}"
            return 1
            ;;
    esac

    echo ""
    echo -e "${YELLOW}⚠️  重要提醒：${NC}"
    echo -e "  请编辑 ${CONFIG_FILE}"
    echo -e "  将 YOUR_XXX_API_KEY 替换为你的真实 API Key"
    echo ""
}

# ============================================================
#  API 连通性测试
# ============================================================
test_api_connection() {
    echo ""
    echo -e "${BLUE}[测试] 开始测试 API 连通性...${NC}"

    local api_base=$(grep 'LLM_API_BASE_URL' "${CONFIG_FILE}" 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')
    local api_key=$(grep 'LLM_API_KEY' "${CONFIG_FILE}" 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')
    local model=$(grep 'LLM_MODEL_NAME' "${CONFIG_FILE}" 2>/dev/null | head -1 | sed 's/.*"\(.*\)"/\1/')

    if [ -z "$api_base" ]; then
        echo -e "${RED}[错误] 配置文件不存在或格式错误${NC}"
        return 1
    fi

    echo -e "  API 地址: ${api_base}"
    echo -e "  模型名称: ${model}"

    # 发送测试请求
    local response
    response=$(curl -s --connect-timeout 10 --max-time 30 \
        -X POST "${api_base}/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${api_key}" \
        -d "{
            \"model\": \"${model}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"你好，请回复'连接成功'\"}],
            \"max_tokens\": 50
        }" 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "  HTTP 响应: $(echo "$response" | head -c 200)"
        echo -e "${GREEN}[测试] API 连通性测试完成${NC}"
    else
        echo -e "${RED}[测试] API 连接失败，请检查网络和 API Key${NC}"
    fi
}

# ============================================================
#  查看当前配置
# ============================================================
view_config() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  当前 LLM 配置${NC}"
    echo -e "${BLUE}========================================${NC}"

    if [ -f "${CONFIG_FILE}" ]; then
        cat "${CONFIG_FILE}"
    else
        echo -e "${RED}配置文件不存在，请先选择 LLM 后端${NC}"
    fi

    echo -e "${BLUE}========================================${NC}"
}

# ============================================================
#  命令行模式（非交互式）
# ============================================================
if [ $# -gt 0 ]; then
    case "$1" in
        deepseek|ds)
            switch_backend 1
            ;;
        qwen|qw)
            switch_backend 2
            ;;
        ollama|local)
            switch_backend 3
            ;;
        test)
            test_api_connection
            ;;
        view)
            view_config
            ;;
        *)
            echo "用法: $0 [deepseek|qwen|ollama|test|view]"
            echo "  deepseek  - 切换到 DeepSeek"
            echo "  qwen      - 切换到 通义千问"
            echo "  ollama    - 切换到 Ollama 本地"
            echo "  test      - 测试 API 连通性"
            echo "  view      - 查看当前配置"
            ;;
    esac
    exit 0
fi

# ============================================================
#  交互式模式
# ============================================================
while true; do
    show_menu
    read -r choice

    case "$choice" in
        1) switch_backend 1 ;;
        2) switch_backend 2 ;;
        3) switch_backend 3 ;;
        4) view_config ;;
        5) test_api_connection ;;
        0)
            echo "再见！"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新选择${NC}"
            ;;
    esac
done
