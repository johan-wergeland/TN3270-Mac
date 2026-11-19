#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift build --package-path "$ROOT" --configuration release --product TN3270Mac
BIN_DIR="$(swift build --package-path "$ROOT" --configuration release --show-bin-path)"
APP="$BIN_DIR/TN3270Mac.app"
ICONSET="$BIN_DIR/AppIcon.iconset"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp "$BIN_DIR/TN3270Mac" "$APP/Contents/MacOS/TN3270Mac"

for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT/Resources/AppIcon.png" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}.png" > /dev/null
    RETINA_SIZE=$((SIZE * 2))
    sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$ROOT/Resources/AppIcon.png" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" > /dev/null
done
iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TN3270Mac</string>
    <key>CFBundleIdentifier</key>
    <string>com.mradrianhh.TN3270Mac</string>
    <key>CFBundleName</key>
    <string>TN3270Mac</string>
    <key>CFBundleDisplayName</key>
    <string>TN3270Mac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

printf '\nBuilt app: %s\nDrag TN3270Mac.app into Applications to install it.\n' "$APP"
