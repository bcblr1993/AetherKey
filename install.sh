#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${SCRIPT_DIR}/build/AetherKey.app"
TARGET_DIR="${HOME}/Library/Input Methods"

echo "=================================================="
echo "⟡ AetherKey: Apple Silicon macOS 原生极速输入法安装"
echo "  设计语言: AetherNative (Liquid Glass / 微光胶囊)"
echo "=================================================="

if [ ! -d "${APP_PATH}" ]; then
    echo "❌ 未找到构建产物: ${APP_PATH}"
    echo "正在重新构建 Release 版本..."
    cd "${SCRIPT_DIR}"
    xcodebuild -project AetherKey.xcodeproj -scheme AetherKey -configuration Release build
    mkdir -p build
    cp -R /Users/chenxu/Library/Developer/Xcode/DerivedData/AetherKey-*/Build/Products/Release/AetherKey.app build/
fi

echo "1. 创建目标目录: ${TARGET_DIR}..."
mkdir -p "${TARGET_DIR}"

echo "2. 终止现有 AetherKey 进程..."
pkill -9 -f "AetherKey" || true

echo "3. 安装 AetherKey.app 到输入法系统目录..."
rm -rf "${TARGET_DIR}/AetherKey.app"
cp -R "${APP_PATH}" "${TARGET_DIR}/"

echo "4. 重置 LaunchServices 注册表与信任链..."
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "${TARGET_DIR}/AetherKey.app"

echo "5. 重签本地 Ad-Hoc 签名..."
codesign --force --deep --sign - "${TARGET_DIR}/AetherKey.app"

echo "6. 激活输入法服务..."
open "${TARGET_DIR}/AetherKey.app" || true

echo ""
echo "=================================================="
echo "✓ AetherKey 部署完成！"
echo "提示: 请在 [系统设置 -> 键盘 -> 文本输入 -> 输入法] 中添加 AetherKey (简体中文)"
echo "=================================================="
