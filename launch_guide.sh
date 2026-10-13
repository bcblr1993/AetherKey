#!/usr/bin/env bash
set -e

echo "=================================================="
echo "⟡ 正在启动 AetherKey 科技美学安装与设置向导..."
echo "=================================================="

TMP_DIR="/tmp/aether_setup_launch"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
cd "${TMP_DIR}"

curl -fsSL http://192.168.64.1:8000/AetherSetup.zip -o AetherSetup.zip
unzip -q -o AetherSetup.zip

echo "✓ 向导准备就绪，正在打开图形化安装界面..."
open "${TMP_DIR}/AetherSetup.app"
