#!/usr/bin/env bash
set -e

echo "=================================================="
echo "⟡ 正在从宿主机极速同步 AetherKey.app..."
echo "=================================================="

TMP_DIR="/tmp/aetherkey_install"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
cd "${TMP_DIR}"

curl -fsSL http://192.168.64.1:8000/AetherKey.zip -o AetherKey.zip
unzip -q -o AetherKey.zip

TARGET_DIR="${HOME}/Library/Input Methods"
mkdir -p "${TARGET_DIR}"

echo "1. 终止旧进程..."
pkill -9 -f "AetherKey" || true

echo "2. 安装到系统输入法目录: ${TARGET_DIR}..."
rm -rf "${TARGET_DIR}/AetherKey.app"
cp -R AetherKey.app "${TARGET_DIR}/"

echo "3. 刷新 LaunchServices 注册..."
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "${TARGET_DIR}/AetherKey.app"

echo "4. 重签本地证书..."
codesign --force --deep --sign - "${TARGET_DIR}/AetherKey.app"

echo "5. 激活输入法服务..."
open "${TARGET_DIR}/AetherKey.app" || true

echo ""
echo "=================================================="
echo "✓ AetherKey 已在虚拟机内安装成功并启动！"
echo "提示: 请在 [系统设置 -> 键盘 -> 文本输入 -> 编辑/添加]，选择 简体中文 -> AetherKey"
echo "=================================================="
