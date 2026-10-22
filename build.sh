#!/bin/bash
# Builds SessionNotifier.app. Usage:
#   ./build.sh            -> build/SessionNotifier.app
#   ./build.sh --install  -> installs to /Applications/SessionNotifier.app and launches it
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SessionNotifier"
BUNDLE_ID="com.erenoz.sessionnotifier"
APP="build/$APP_NAME.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# AppIcons/AppIcon.appiconset -> Assets.car + AppIcon.icns
# On macOS 26, notifications take the icon from the asset catalog (CFBundleIconName); an .icns alone isn't enough.
XCASSETS="build/Assets.xcassets"
rm -rf "$XCASSETS"
mkdir -p "$XCASSETS"
cp -R AppIcons/AppIcon.appiconset "$XCASSETS/"
echo '{"info":{"author":"xcode","version":1}}' > "$XCASSETS/Contents.json"
xcrun actool "$XCASSETS" --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist build/icon-partial.plist >/dev/null
rm -rf "$XCASSETS" build/icon-partial.plist

# Menu bar icons (1x + @2x; NSImage(named:) combines them)
cp AppIcons/MenuBarIcon*.imageset/*.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M%S)</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature unless SIGN_IDENTITY is set.
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --sign "$IDENTITY" "$APP"
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    # If the build/ copy stays registered with the same bundle id, a second SessionNotifier shows up
    # in Spotlight and login items, and notifications may pick up the wrong copy's icon.
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
    rm -rf "$APP"
    "$LSREGISTER" -f "/Applications/$APP_NAME.app" >/dev/null 2>&1 || true
    # Notification Center caches the app icon; refresh it.
    killall usernoted NotificationCenter 2>/dev/null || true
    open "/Applications/$APP_NAME.app"
    echo "Installed and launched: /Applications/$APP_NAME.app"
fi
