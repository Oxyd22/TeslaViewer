#!/usr/bin/env bash
#
# bundle.sh — baut aus dem SwiftPM-Executable ein echtes TeslaViewer.app.
#
# Hintergrund: `swift run` startet das Programm direkt, ohne App-Bundle.
# Für ein verteilbares .app (Name, Dock-Icon, Ablage in /Applications)
# braucht es eine Info.plist und die übliche Bundle-Struktur. Genau das
# erzeugt dieses Skript.
#
# Aufruf:  ./bundle.sh        -> baut Release nach ./TeslaViewer.app
#
set -euo pipefail

APP_NAME="TeslaViewer"
BUNDLE_ID="de.danielriewe.TeslaViewer"
MIN_OS="14.0"
CONFIG="release"

cd "$(dirname "$0")"

echo "› Baue Release-Binary …"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP="${APP_NAME}.app"

echo "› Erzeuge ${APP} …"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"

# Von SwiftPM erzeugtes Ressourcen-Bundle (Assets) mitnehmen, falls vorhanden.
RES_BUNDLE="${BIN_PATH}/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "${APP}/Contents/Resources/"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>${MIN_OS}</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc-Signatur, damit macOS das Bundle ohne Gatekeeper-Meckern startet.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ Fertig: ${PWD}/${APP}"
echo "  Start mit:  open ${APP}"
