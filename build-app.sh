#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
APP_PATH="$PROJECT_DIR/dist/YingxiaRemote.app"
BUILD_DIR="$PROJECT_DIR/.build"

if [[ ! "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "APP_VERSION 需要是 0.1.0 这样的版本号"
  exit 1
fi

mkdir -p "$BUILD_DIR" "$PROJECT_DIR/dist"
if [[ -d "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
fi
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Helpers" "$APP_PATH/Contents/Resources/icons"

for source in MacRemoteApp ax_remote highlight; do
  for arch in arm64 x86_64; do
    swiftc -target "$arch-apple-macos13.0" "$PROJECT_DIR/$source.swift" -o "$BUILD_DIR/$source-$arch"
  done
  destination="$APP_PATH/Contents/Helpers/$source"
  if [[ "$source" == "MacRemoteApp" ]]; then
    destination="$APP_PATH/Contents/MacOS/YingxiaRemote"
  fi
  lipo -create "$BUILD_DIR/$source-arm64" "$BUILD_DIR/$source-x86_64" -output "$destination"
done

cp "$PROJECT_DIR/index.html" "$APP_PATH/Contents/Resources/index.html"
cp "$PROJECT_DIR/LICENSE" "$APP_PATH/Contents/Resources/LICENSE"
cp "$PROJECT_DIR/icons/"*.svg "$APP_PATH/Contents/Resources/icons/"
cp "$PROJECT_DIR/icons/LUCIDE-LICENSE" "$APP_PATH/Contents/Resources/icons/"
swift "$PROJECT_DIR/AppIcon.swift" "$BUILD_DIR/AppIcon.png"
iconset="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$BUILD_DIR/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -s format png -z "$double" "$double" "$BUILD_DIR/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Yingxia Remote</string>
  <key>CFBundleDisplayName</key><string>映匣遥控器</string>
  <key>CFBundleIdentifier</key><string>io.github.joisun.yingxiaremote</string>
  <key>CFBundleExecutable</key><string>YingxiaRemote</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSAppleEventsUsageDescription</key><string>向映匣发送播放快捷键，并调整 Mac 音量。</string>
  <key>NSLocalNetworkUsageDescription</key><string>让同一 Wi-Fi 下的手机连接映匣遥控器。</string>
</dict></plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  signing=(--force --options runtime --timestamp --sign "$CODESIGN_IDENTITY")
else
  signing=(--force --sign -)
fi
cat > "$BUILD_DIR/App.entitlements" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.automation.apple-events</key><true/>
</dict></plist>
ENTITLEMENTS
codesign "${signing[@]}" "$APP_PATH/Contents/Helpers/ax_remote"
codesign "${signing[@]}" "$APP_PATH/Contents/Helpers/highlight"
codesign "${signing[@]}" --entitlements "$BUILD_DIR/App.entitlements" "$APP_PATH/Contents/MacOS/YingxiaRemote"
codesign "${signing[@]}" --entitlements "$BUILD_DIR/App.entitlements" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
print "$APP_PATH"
