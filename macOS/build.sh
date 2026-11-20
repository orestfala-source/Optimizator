#!/bin/bash
# =====================================================================
#  Optimizator для macOS 13+: збирає програму, інсталер .pkg і образ .dmg
#  Потрібно: Xcode або Command Line Tools (xcode-select --install)
#  Результат: macOS/dist/Optimizator-<версія>.dmg  (усередині — інсталер .pkg)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < ../VERSION)"
BUILD="build"
DIST="dist"
APP="$BUILD/Optimizator.app"
rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST"

echo "▸ [1/5] Компіляція (Optimizator $VERSION)…"
# Universal (Apple Silicon + Intel) потребує повного Xcode; якщо його немає — збираємо під свій Mac
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    echo "  universal: arm64 + x86_64"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)"
    echo "  тільки $(uname -m) (для universal встанови повний Xcode)"
fi

echo "▸ [2/5] Іконка…"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s           Assets/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
    sips -z $((s*2)) $((s*2)) Assets/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

echo "▸ [3/5] Пакування Optimizator.app…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Optimizator"     "$APP/Contents/MacOS/Optimizator"
cp "$BIN/optimizator-smc" "$APP/Contents/Resources/optimizator-smc"
cp "$BUILD/AppIcon.icns"  "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Optimizator</string>
  <key>CFBundleDisplayName</key><string>Optimizator</string>
  <key>CFBundleIdentifier</key><string>com.optimizator.app</string>
  <key>CFBundleExecutable</key><string>Optimizator</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>uk</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Optimizator</string>
  <key>NSAppleEventsUsageDescription</key><string>Optimizator використовує це, щоб один раз встановити системного помічника.</string>
</dict>
</plist>
PLIST

# Ad-hoc підпис (для розповсюдження без попереджень потрібен Apple Developer ID — див. README)
SIGN_ID="${SIGN_ID:--}"
SIGN_OPTS=()
[ "$SIGN_ID" != "-" ] && SIGN_OPTS=(--options runtime --timestamp)
codesign --force "${SIGN_OPTS[@]+"${SIGN_OPTS[@]}"}" --sign "$SIGN_ID" "$APP/Contents/Resources/optimizator-smc"
codesign --force "${SIGN_OPTS[@]+"${SIGN_OPTS[@]}"}" --sign "$SIGN_ID" "$APP"

echo "▸ [4/5] Інсталер .pkg…"
STAGE="$BUILD/pkgroot"
mkdir -p "$STAGE/Applications"
cp -R "$APP" "$STAGE/Applications/"
chmod +x packaging/scripts/preinstall packaging/scripts/postinstall

# Забороняємо «переміщення» пакета: програма завжди ставиться в /Applications
pkgbuild --analyze --root "$STAGE" "$BUILD/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$BUILD/component.plist"

pkgbuild --root "$STAGE" \
         --component-plist "$BUILD/component.plist" \
         --scripts packaging/scripts \
         --identifier com.optimizator.app \
         --version "$VERSION" \
         --install-location / \
         "$BUILD/Optimizator-component.pkg" >/dev/null

sed "s/__VERSION__/$VERSION/" packaging/distribution.xml > "$BUILD/distribution.xml"
productbuild --distribution "$BUILD/distribution.xml" \
             --resources packaging/resources \
             --package-path "$BUILD" \
             "$DIST/Optimizator-$VERSION.pkg" >/dev/null

echo "▸ [5/5] Образ .dmg…"
DMGROOT="$BUILD/dmg"
mkdir -p "$DMGROOT"
cp "$DIST/Optimizator-$VERSION.pkg" "$DMGROOT/Встановити Optimizator.pkg"
cp packaging/uninstall.command "$DMGROOT/Видалити Optimizator.command"
chmod +x "$DMGROOT/Видалити Optimizator.command"
hdiutil create -volname "Optimizator $VERSION" -srcfolder "$DMGROOT" -ov -format UDZO \
        "$DIST/Optimizator-$VERSION.dmg" >/dev/null

echo
echo "✅ Готово:"
echo "   $PWD/$DIST/Optimizator-$VERSION.dmg   ← роздавай цей файл"
echo "   $PWD/$DIST/Optimizator-$VERSION.pkg"
open "$DIST" 2>/dev/null || true
