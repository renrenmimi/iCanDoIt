#!/bin/zsh
# 编译 iCanDoIt 并打包成 .app
set -e
cd "$(dirname "$0")"

echo "▸ 编译 (release)…"
swift build -c release

echo "▸ 打包 .app…"
APP="build/iCanDoIt.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/iCanDoIt "$APP/Contents/MacOS/iCanDoIt"
cp AppResources/Info.plist "$APP/Contents/Info.plist"
if [ -f AppResources/AppIcon.icns ]; then
  cp AppResources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ 签名 (ad-hoc)…"
codesign --force --sign - "$APP"

echo "✓ 完成:$APP"
