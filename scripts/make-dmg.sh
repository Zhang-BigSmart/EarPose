#!/bin/bash
# 打一份可拖进「应用程序」的 EarPose.dmg（临时签名，未公证）。
# 用法：在仓库根目录执行  ./scripts/make-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/EarPose/EarPose.xcodeproj"
SCHEME="EarPose"
VOLNAME="EarPose"
OUT_DIR="$ROOT/dist"
STAGE="$OUT_DIR/dmg-stage"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "DEVELOPER_DIR=$DEVELOPER_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build

APPDIR="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR/ {print $2; exit}')"
APP="$APPDIR/EarPose.app"
if [[ ! -d "$APP" ]]; then
  echo "找不到 $APP" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/EarPose.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me.txt" <<'TXT'
Install EarPose
1. Drag EarPose into Applications.
2. Do not double-click. In Applications, Control-click EarPose → Open → Open.
3. If macOS still blocks it: System Settings → Privacy & Security → Open Anyway.
4. System Settings → Privacy & Security → Accessibility → turn on EarPose (/Applications/EarPose.app).
5. Wear AirPods, click the menu bar icon → Start. Allow Motion & Fitness when asked.

Do not run spctl --master-disable. That turns off app checks for the whole Mac.

安装 EarPose
1. 把 EarPose 拖到 Applications（应用程序）。
2. 不要双击。在「应用程序」里 Control-点击 EarPose → 打开 → 打开。
3. 仍被拦：系统设置 → 隐私与安全性 → 仍要打开。
4. 系统设置 → 隐私与安全性 → 辅助功能 → 打开 EarPose。
5. 戴上耳机，点菜单栏图标 → 开始。允许「运动与健身」。

不要执行 spctl --master-disable，那会关掉整机的应用检查。
TXT

mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/EarPose.dmg"
rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "已生成 $DMG"
file "$APP/Contents/MacOS/EarPose"
ls -lh "$DMG"
