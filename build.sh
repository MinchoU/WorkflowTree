#!/bin/bash
# Build & install the native WorkflowTree.app (Objective-C + WKWebView).
# Usage: ./build.sh [install-path]   (default: /Applications/WorkflowTree.app)
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-/Applications/WorkflowTree.app}"

echo "→ Compiling native wrapper…"
clang -fobjc-arc -O2 -framework Cocoa -framework WebKit \
      -o "$DIR/native/WorkflowTree" "$DIR/native/main.m"

echo "→ Assembling app bundle at: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/native/WorkflowTree" "$APP/Contents/MacOS/WorkflowTree"
cp "$DIR/index.html" "$DIR/icon.svg" "$DIR/icon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>WorkflowTree</string>
  <key>CFBundleDisplayName</key><string>WorkflowTree</string>
  <key>CFBundleIdentifier</key><string>com.minchou.workflowtree</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>WorkflowTree</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so it launches without "damaged app" warnings.
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true

echo "✓ Installed: $APP"
echo "  Open it from Finder/Spotlight. (First launch: right-click → Open if Gatekeeper warns.)"
