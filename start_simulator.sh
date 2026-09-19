#!/bin/bash
# ============================================================
#  openvela 智能家居 - 模拟器启动脚本
#  自动链接编译产物并启动 QEMU 模拟器
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/out/goldfish-arm64-v8a-ap"
NUTTX_DIR="${SCRIPT_DIR}/nuttx"

echo "========================================="
echo " openvela 智能家居 - QEMU 模拟器"
echo "========================================="

# 1. 检查编译产物
if [ ! -f "${OUT_DIR}/nuttx" ]; then
    echo "[错误] 未找到编译产物！请先运行:"
    echo "  ./build.sh vendor/openvela/boards/vela/configs/goldfish-arm64-v8a-ap"
    exit 1
fi

# 2. 链接编译产物到 nuttx 目录
echo "[信息] 链接编译产物..."
cp -f "${OUT_DIR}/nuttx"       "${NUTTX_DIR}/nuttx" 2>/dev/null || true
cp -f "${OUT_DIR}/nuttx.bin"    "${NUTTX_DIR}/nuttx.bin" 2>/dev/null || true
cp -f "${OUT_DIR}/vela_data.bin"  "${NUTTX_DIR}/vela_data.bin" 2>/dev/null || true
cp -f "${OUT_DIR}/vela_system.bin" "${NUTTX_DIR}/vela_system.bin" 2>/dev/null || true
cp -f "${OUT_DIR}/vela_ap.bin"     "${NUTTX_DIR}/vela_ap.bin" 2>/dev/null || true
cp -f "${OUT_DIR}/vela_ap.elf"     "${NUTTX_DIR}/vela_ap.elf" 2>/dev/null || true

# 3. 启动模拟器
echo "[信息] 启动模拟器..."
echo ""
exec "${SCRIPT_DIR}/emulator.sh" vela "$@"
