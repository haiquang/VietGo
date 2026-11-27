#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

QA_BUILD_DIR="$ROOT_DIR/scripts/qa/.build"
WORD_BIN="$QA_BUILD_DIR/WordHostQA"
RESULTS_JSON="$ROOT_DIR/test-results/qa/latest-word-qa.json"

mkdir -p "$QA_BUILD_DIR" "$ROOT_DIR/test-results/qa"

echo "==> [1/2] Compiling VietGoEngine, IME worker, and WordHostQA..."
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

swiftc -O -parse-as-library \
    scripts/qa/run_word_qa.swift \
    -framework AppKit -framework ApplicationServices -framework Carbon \
    -o "$WORD_BIN"

WAS_VIETGO_RUNNING=0
if pgrep -x VietGo >/dev/null 2>&1; then
    WAS_VIETGO_RUNNING=1
    pkill -x VietGo || true
fi

cleanup() {
    if [[ "$WAS_VIETGO_RUNNING" -eq 1 && -d "$ROOT_DIR/dist/VietGo.app" ]]; then
        open "$ROOT_DIR/dist/VietGo.app" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "==> [2/2] Running real Microsoft Word QA suite..."
"$WORD_BIN" \
    --ime-worker-bin "$QA_BUILD_DIR/validate_fast_chat_e2e" \
    --json-out "$RESULTS_JSON"
WORD_STATUS=$?

echo "==> Word QA JSON report saved at: $RESULTS_JSON"
exit "$WORD_STATUS"
