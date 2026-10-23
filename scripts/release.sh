#!/bin/bash
# Build, sign, notarize and staple the installer and its nested input method.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
OUT="${RELEASE_OUT:-${ROOT}/output/releases/${VERSION}}"
DERIVED="${ROOT}/.build/FormalRelease"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: YanNan Chen (5984KQD4D7)}"
PROFILE="${NOTARY_PROFILE:-AetherRoute-Notary}"
STAGE="$OUT/stage"
SETUP="$STAGE/安装 AetherKey.app"
PAYLOAD="$SETUP/Contents/Resources/AetherKey.app"
DMG="$OUT/AetherKey-${VERSION}-arm64.dmg"
mkdir -p "$STAGE"
if [ -e "$SETUP" ] || [ -e "$DMG" ]; then
    echo 'Release output already exists. Choose a new version/output before rebuilding.' >&2
    exit 1
fi
for SCHEME in AetherKey AetherSetup; do
    xcodebuild -project "$ROOT/AetherKey.xcodeproj" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" build > "$OUT/${SCHEME}-build.log" 2>&1
done
ditto "$DERIVED/Build/Products/Release/AetherSetup.app" "$SETUP"
mkdir -p "$SETUP/Contents/Resources"
ditto "$DERIVED/Build/Products/Release/AetherKey.app" "$PAYLOAD"
cp "$ROOT/Resources/AppIcon.icns" "$SETUP/Contents/Resources/AppIcon.icns"
for LOCALIZATION in zh-Hans zh_CN en; do
    plutil -convert binary1 "$PAYLOAD/Contents/Resources/${LOCALIZATION}.lproj/InfoPlist.strings"
done
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon.icns' "$SETUP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string 安装 AetherKey' "$SETUP/Contents/Info.plist"
for APP in "$PAYLOAD" "$SETUP"; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
done
codesign --verify --deep --strict "$SETUP"
ditto -c -k --keepParent "$SETUP" "$OUT/AetherKey-notary.zip"
xcrun notarytool submit "$OUT/AetherKey-notary.zip" --keychain-profile "$PROFILE" --no-s3-acceleration --wait --output-format json > "$OUT/app-notary.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"]=="Accepted"' "$OUT/app-notary.json"
xcrun stapler staple "$PAYLOAD"
# The payload lives under Resources: stapling it changes the outer resource seal.
# Seal the final payload, then notarize the final outer app again.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SETUP"
ditto -c -k --keepParent "$SETUP" "$OUT/AetherKey-setup-notary.zip"
xcrun notarytool submit "$OUT/AetherKey-setup-notary.zip" --keychain-profile "$PROFILE" --no-s3-acceleration --wait --output-format json > "$OUT/setup-notary.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"]=="Accepted"' "$OUT/setup-notary.json"
xcrun stapler staple "$SETUP"
codesign --verify --deep --strict "$SETUP"
cat > "$STAGE/安装说明.txt" <<'GUIDE'
AetherKey 1.0.0 — 原生 macOS 中文拼音输入法

要求：Apple 芯片（M 系列），macOS 14 或更新版本。
1. 双击「安装 AetherKey.app」，无需拖入 Applications。
2. 按向导安装，然后到系统设置 → 键盘 → 文本输入 → 编辑，添加「AetherKey 拼音」。
3. 从菜单栏选择 AetherKey，或按 Control + 空格切换。
4. 在向导测试框或文本编辑输入 nihao，按空格写入「你好」。
若系统未立即列出输入法，请注销并重新登录，再打开向导继续。

输入法安装在 ~/Library/Input Methods/AetherKey.app。
词库和偏好保存在本机，更新安装会保留；无需注册账号。
更新请从 https://aethernative.com/apps/aetherkey/ 下载并重新运行安装向导。
完整帮助与卸载说明见官网。此版本暂不包含自动更新和云端词库同步。
GUIDE
hdiutil create -fs HFS+ -volname 'AetherKey 1.0.0' -srcfolder "$STAGE" -format UDZO "$DMG" > "$OUT/dmg.log"
codesign --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --no-s3-acceleration --wait --output-format json > "$OUT/dmg-notary.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"]=="Accepted"' "$OUT/dmg-notary.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG" >> "$OUT/dmg.log"
(cd "$OUT" && shasum -a 256 "AetherKey-${VERSION}-arm64.dmg" > SHA256SUMS)
printf '%s\n' "$DMG"
