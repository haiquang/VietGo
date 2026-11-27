#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

SKIP_BROWSER=0
FILTER_TERM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-browser)
            SKIP_BROWSER=1
            shift
            ;;
        --filter)
            if [[ $# -lt 2 ]]; then
                echo "Error: --filter requires a value" >&2
                exit 2
            fi
            FILTER_TERM="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: bash scripts/qa/run_regression_qa.sh [--skip-browser] [--filter <substring>]" >&2
            exit 2
            ;;
    esac
done

echo "==> [1/3] Running VietGoEngine unit regression suite (swift test)..."
swift test

if [[ "$SKIP_BROWSER" -eq 1 ]]; then
    echo "==> Skipping Browser HID QA (--skip-browser)."
    exit 0
fi

QA_BUILD_DIR="$ROOT_DIR/scripts/qa/.build"
QA_APP="$QA_BUILD_DIR/BrowserHostQA.app"
QA_APP_CONTENTS="$QA_APP/Contents"
QA_APP_MACOS="$QA_APP_CONTENTS/MacOS"
RESULTS_JSON="$ROOT_DIR/test-results/qa/latest-browser-qa.json"

mkdir -p "$QA_BUILD_DIR" "$QA_APP_MACOS" "$ROOT_DIR/test-results/qa"

echo "==> [2/3] Compiling fresh VietGoEngine, IME worker, and BrowserHostQA.app..."
swiftc -O -emit-library -emit-module \
    -emit-module-path "$QA_BUILD_DIR/VietGoEngine.swiftmodule" \
    -module-name VietGoEngine -parse-as-library \
    Sources/VietGoEngine/*.swift \
    -framework AppKit -framework Foundation \
    -o "$QA_BUILD_DIR/libVietGoEngine.dylib"

swiftc -O -parse-as-library \
    -I "$QA_BUILD_DIR" -L "$QA_BUILD_DIR" -Xlinker -rpath -Xlinker "$QA_BUILD_DIR" \
    -lVietGoEngine \
    Sources/VietGoApp/AppSettings.swift \
    Sources/VietGoApp/EventTapManager.swift \
    scripts/validate_fast_chat_e2e.swift \
    -framework AppKit -framework ApplicationServices -framework Carbon -framework Combine -framework ServiceManagement -framework WebKit \
    -o "$QA_BUILD_DIR/validate_fast_chat_e2e"

cat > "$QA_APP_CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BrowserHostQA</string>
    <key>CFBundleIdentifier</key>
    <string>net.imput.helium</string>
    <key>CFBundleName</key>
    <string>BrowserHostQA</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

swiftc -O -parse-as-library \
    scripts/qa/run_browser_host_qa.swift \
    -framework AppKit -framework ApplicationServices -framework Carbon -framework WebKit \
    -o "$QA_APP_MACOS/BrowserHostQA"

codesign --force --deep --sign - "$QA_APP" >/dev/null 2>&1

WAS_VIETGO_RUNNING=0
if pgrep -x VietGo >/dev/null 2>&1; then
    WAS_VIETGO_RUNNING=1
    pkill -x VietGo || true
fi

SERVER_PID=""
cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
        kill "$SERVER_PID" >/dev/null 2>&1 || true
    fi
    if [[ "$WAS_VIETGO_RUNNING" -eq 1 && -d "$ROOT_DIR/dist/VietGo.app" ]]; then
        open "$ROOT_DIR/dist/VietGo.app" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if ! python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/api/results', timeout=1)" >/dev/null 2>&1; then
    echo "==> Starting local Browser QA Lab server on http://127.0.0.1:8765..."
    python3 scripts/qa/browser_qa_server.py --port 8765 >/dev/null 2>&1 &
    SERVER_PID="$!"
    sleep 0.6
fi

echo "==> [3/3] Executing Cumulative Browser HID QA suite..."
QA_ARGS=(
    --ime-worker-bin "$QA_BUILD_DIR/validate_fast_chat_e2e"
    --json-out "$RESULTS_JSON"
)
if [[ -n "$FILTER_TERM" ]]; then
    QA_ARGS+=(--filter "$FILTER_TERM")
fi

"$QA_APP_MACOS/BrowserHostQA" "${QA_ARGS[@]}"
QA_STATUS=$?

if [[ "$WAS_VIETGO_RUNNING" -eq 1 ]]; then
    bash "$ROOT_DIR/scripts/build_app.sh" >/dev/null
fi

echo "==> Browser QA JSON report saved at: $RESULTS_JSON"
exit "$QA_STATUS"
