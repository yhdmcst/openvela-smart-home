# ============================================================
#  Makefile - openvela 智能家居 Tool 独立编译 & 测试
#
#  用法:
#    make              — 编译所有 Tool + 测试程序
#    make test         — 运行自动化测试
#    make clean        — 清理编译产物
#    make arm64        — ARM64 交叉编译
# ============================================================

CC      ?= gcc
CFLAGS  ?= -Wall -Wextra -O2 -std=c99 -g
LDFLAGS ?= -lm

# 交叉编译（ARM64 嵌入式目标）
CROSS_CC ?= aarch64-linux-gnu-gcc

TOOLS_DIR    = tools
SKILLS_DIR   = skills
SECURITY_DIR = security
BUILD_DIR    = .build

# ---- 所有 Tool 源文件（含新增） ----
TOOL_SRCS = $(TOOLS_DIR)/tool_light_control.c \
            $(TOOLS_DIR)/tool_temperature_read.c \
            $(TOOLS_DIR)/device_state.c \
            $(TOOLS_DIR)/tool_curtain_control.c \
            $(TOOLS_DIR)/tool_environment_monitor.c \
            $(TOOLS_DIR)/tool_security_control.c

TOOL_OBJS = $(patsubst $(TOOLS_DIR)/%.c,$(BUILD_DIR)/%.o,$(TOOL_SRCS))

SEC_SRCS  = $(SECURITY_DIR)/command_whitelist.c
SEC_OBJS  = $(BUILD_DIR)/command_whitelist.o

# ---- 综合测试源文件（完整集成测试） ----
TEST_SRC  = test_smart_home.c

# ---- 默认目标 ----
.PHONY: all test clean help arm64
all: $(BUILD_DIR)/libsmart_home.a $(BUILD_DIR)/test_smart_home
	@echo ""
	@echo "+=========================================+"
	@echo "|  openvela Smart Home Build Complete    |"
	@echo "|  Run 'make test' for functional test   |"
	@echo "+=========================================+"
	@echo ""

# ---- 静态库 ----
$(BUILD_DIR)/libsmart_home.a: $(TOOL_OBJS)
	@mkdir -p $(BUILD_DIR)
	$(AR) rcs $@ $^
	@echo "  AR   $@"

# ---- 通用编译规则（所有 .c → .o） ----
$(BUILD_DIR)/%.o: $(TOOLS_DIR)/%.c $(TOOLS_DIR)/smart_home_tools.h
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(TOOLS_DIR) -c $< -o $@
	@echo "  CC   $@"

$(BUILD_DIR)/%.o: $(SECURITY_DIR)/%.c
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@
	@echo "  CC   $@"

# ---- 编译综合测试程序（测试所有 Tool） ----
$(BUILD_DIR)/test_smart_home: $(TEST_SRC) $(TOOL_OBJS)
	$(CC) $(CFLAGS) -I$(TOOLS_DIR) -o $@ $(TEST_SRC) $(TOOL_OBJS) $(LDFLAGS)
	@echo "  LD   $@"

# ---- 测试入口 ----
test: $(BUILD_DIR)/test_smart_home
	@echo ""
	@$(BUILD_DIR)/test_smart_home
	@echo ""

# ---- 交叉编译 (ARM64) ----
arm64: CFLAGS += -mcpu=cortex-a57 -march=armv8-a
arm64: CC = $(CROSS_CC)
arm64: $(BUILD_DIR)/libsmart_home.a
	@echo "✓ ARM64 交叉编译完成"

# ---- 清理 ----
clean:
	rm -rf $(BUILD_DIR) device_state.json
	@echo "✓ 清理完成"

# ---- 帮助 ----
help:
	@echo "openvela 智能家居 Tool 编译系统 v2.0"
	@echo ""
	@echo "用法："
	@echo "  make         编译所有 Tool + 综合测试程序"
	@echo "  make test    运行全部 9 大模块功能测试"
	@echo "  make arm64   ARM64 交叉编译"
	@echo "  make clean   清理编译产物"
	@echo ""
	@echo "已注册 Tool (6个)："
	@echo "  tool_light_control      灯光控制"
	@echo "  tool_temperature_read   温湿度读取"
	@echo "  tool_curtain_control    窗帘控制"
	@echo "  tool_security_control   安防控制"
	@echo "  tool_sensor_read        多传感器读取"
	@echo "  tool_environment_patrol 主动环境巡检"
	@echo ""
	@echo "新增能力 (v2.0)："
	@echo "  tool_fuzzy_command_parse 模糊指令解析"
	@echo "  device_state_save/load   设备状态持久化"
