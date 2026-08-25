#!/bin/zsh
# Builds CleanPDF.app from the Swift package.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/CleanPDF.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/CleanPDF "$APP/Contents/MacOS/CleanPDF"

# App icon: assets/AppIcon.png (1024x1024) -> AppIcon.icns.
# Drop your own PNG at that path to override; regenerate the default with:
#   swift assets/generate_icon.swift assets/AppIcon.png
if [[ -f assets/AppIcon.png ]]; then
    ICONSET="build/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CleanPDF</string>
    <key>CFBundleIdentifier</key>
    <string>local.cleanpdf</string>
    <key>CFBundleName</key>
    <string>CleanPDF</string>
    <key>CFBundleDisplayName</key>
    <string>CleanPDF</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

echo ""
echo "Fertig: $PWD/$APP"
echo "Installieren mit:  cp -R $APP /Applications/"
