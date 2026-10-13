#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="macos27"

echo "=================================================="
echo "⟡ 启动 Tart macOS 虚拟机进行 AetherKey 原生测试"
echo "  挂载共享目录: ${SCRIPT_DIR} -> /Volumes/AetherKey"
echo "=================================================="

# Check if tart is available
if ! command -v tart &>/dev/null; then
    echo "❌ 未检测到 tart 命令，请先安装: brew install cirruslabs/cli/tart"
    exit 1
fi

# Check if VM is running
if tart list | grep -q "${VM_NAME}.*running"; then
    echo "⚠️  虚拟机 ${VM_NAME} 已经在运行中。"
else
    echo "正在启动虚拟机 ${VM_NAME}..."
    tart run --dir="AetherKey:${SCRIPT_DIR}" "${VM_NAME}" &
fi

echo ""
echo "=================================================="
echo "✓ 虚拟机已启动！"
echo "虚拟机内测试步骤:"
echo "1. 在虚拟机桌面打开终端 (Terminal)"
echo "2. 执行: bash /Volumes/AetherKey/install.sh"
echo "3. 打开 [系统设置 -> 键盘 -> 文本输入 -> 编辑 -> 简体中文]，勾选 AetherKey"
echo "4. 切换到 AetherKey 开始极致打字体验！"
echo "=================================================="
