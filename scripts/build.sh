#!/usr/bin/env bash
# Builds Inkling.app: Rust engine (Harper) → Swift app → signed bundle.
#   scripts/build.sh            build into ./build/Inkling.app
#   scripts/build.sh --install  also copy to /Applications and launch
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Inkling.app"
mkdir -p "$ROOT/build"

# Target the macOS 26 SDK (the newest SDK turns SwiftUI's @State into a macro
# whose plugin only ships with full Xcode).
if [[ -z "${SDKROOT:-}" ]]; then
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk "$(xcrun --show-sdk-path 2>/dev/null)"; do
        [[ -d "$sdk" ]] && export SDKROOT="$sdk" && break
    done
fi

echo "▸ Engine (Rust + Harper)"
(cd "$ROOT/engine" && cargo build --release --lib --quiet)

echo "▸ App (Swift)"
if ! swift build --package-path "$ROOT/App" -c release --arch arm64 > "$ROOT/build/swift-build.log" 2>&1; then
    grep -E "error" "$ROOT/build/swift-build.log" | sed 's/\x1b\[[0-9;]*m//g' | sort -u
    echo "✗ Swift build failed (full log: build/swift-build.log)"
    exit 1
fi
BIN_DIR="$(swift build --package-path "$ROOT/App" -c release --arch arm64 --show-bin-path)"
test -x "$BIN_DIR/Inkling"

echo "▸ Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Inkling" "$APP/Contents/MacOS/Inkling"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/Inkling" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Sign"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')}"
codesign --force --options runtime --timestamp=none --sign "${IDENTITY:--}" "$APP"
echo "✓ Built $APP (signed: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Inkling 2>/dev/null || true
    sleep 0.5
    rm -rf /Applications/Inkling.app
    cp -R "$APP" /Applications/Inkling.app
    open /Applications/Inkling.app
    echo "✓ Installed to /Applications and launched"
fi
