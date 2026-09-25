#!/bin/bash
# Builds "Regain Your Data.app" (the hub holding every app) into ./dist.noindex and, with
# --install, copies it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

# The macOS 27 SDK in Command Line Tools turns SwiftUI's @State into a macro whose plugin only
# ships with full Xcode, so build against the newest SDK where it is still a property wrapper.
if [ -z "${SDKROOT:-}" ] && ! xcode-select -p | grep -q Xcode.app; then
  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk; do export SDKROOT="$sdk"; done
fi

swift build -c release --arch arm64 --arch x86_64   # universal: Intel and Apple silicon
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/RegainHub"

NAME="Regain Your Data"
APP="dist.noindex/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RegainHub"

TMP="$(mktemp -d)"
# The hub's own icon (see scripts/make-icon.swift), and each app's, for the switcher on the left.
swift scripts/make-icon.swift iconset "$TMP"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
for pair in PhotosClone:PhotosIcon SnapchatClone:SnapchatIcon InstagramClone:InstagramIcon WhatsAppClone:WhatsAppIcon AmazonClone:AmazonIcon; do
  dir="${pair%%:*}"; icon="${pair##*:}"
  mkdir -p "$TMP/$dir"
  swift "../$dir/scripts/make-icon.swift" iconset "$TMP/$dir"
  iconutil -c icns "$TMP/$dir/AppIcon.iconset" -o "$APP/Contents/Resources/$icon.icns"
done
ICON_NAME_KEY=""
if ACTOOL="$(xcrun --find actool 2>/dev/null)"; then
  "$ACTOOL" Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
    --app-icon AppIcon --include-all-app-icons --enable-on-demand-resources NO \
    --output-partial-info-plist "$TMP/icon.plist" --development-region en \
    --target-device mac --platform macosx --minimum-deployment-target 14.0 >/dev/null
  ICON_NAME_KEY="<key>CFBundleIconName</key><string>AppIcon</string>"
  echo "Compiled the glass icon with actool"
else
  echo "actool not found (it ships with Xcode): using the flat icon"
fi

VERSION="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.regainyourdata.hub</string>
  <key>CFBundleExecutable</key><string>RegainHub</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  ${ICON_NAME_KEY}
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSRemovableVolumesUsageDescription</key><string>Regain Your Data reads your exports from external drives.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign by default; set SIGN_IDENTITY="Developer ID Application: …" to sign with your account.
codesign --force --deep --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x RegainHub || true
  rm -rf ~/Applications/"$NAME.app"
  DEST=/Applications
  [ -w "$DEST" ] || DEST=~/Applications
  mkdir -p "$DEST"
  rm -rf "$DEST/$NAME.app"
  cp -R "$APP" "$DEST/"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/$NAME.app"
  open "$DEST/$NAME.app"
  echo "Installed and started $DEST/$NAME.app"
fi
