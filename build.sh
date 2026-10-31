#!/bin/zsh
# Tuck.app'i derler.
#   ./build.sh            → build/Tuck.app
#   ./build.sh --install  → ayrıca ~/Applications altına kurar
# Kimlik ve sertifika ilk adı olan Umbrella ile kaldı; değişirse Mac izinleri yeniden ister.
# Not: anahtar zincirinde "Umbrella Yerel Imza" sertifikası yoksa imza geçici olur ve
# her yeni derlemede Erişilebilirlik ve Ekran Kaydı izinleri yeniden verilir.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.1"
MIN_MACOS="14.0"
APP="build/Tuck.app"

ICONSET="build/AppIcon.iconset"
ICON_PNG="build/AppIcon-1024.png"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
swiftc -O -target "arm64-apple-macos$MIN_MACOS" Sources/*.swift -o "$APP/Contents/MacOS/Tuck"
swift scripts/make_icon.swift "$ICON_PNG"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tuck</string>
    <key>CFBundleIdentifier</key><string>com.serbest.umbrella</string>
    <key>CFBundleExecutable</key><string>Tuck</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
# Sabit imza olursa izinler derlemeler arasında korunur; sertifika yoksa geçici imzaya düşer.
IDENTITY="Umbrella Yerel Imza"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Derlendi: $APP ($VERSION)"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf ~/Applications/Tuck.app
    cp -R "$APP" ~/Applications/
    touch ~/Applications/Tuck.app   # Finder simgeyi yenilesin
    echo "Kuruldu: ~/Applications/Tuck.app"
fi
