#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
case "$MODE" in
    run|--verify|--logs|--telemetry|--debug) ;;
    *) echo "Usage: $0 [--verify|--logs|--telemetry|--debug]" >&2; exit 2 ;;
esac
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/.build/bundles/debug/AudoCaptureApp.app"
# Use the app's safe Quit path; never kill a recording or a pending export.
if pgrep -x AudoCaptureApp >/dev/null; then
    osascript -e 'tell application id "dev.codex.AudoCapture" to quit'
    while pgrep -x AudoCaptureApp >/dev/null; do sleep 1; done
fi
"$PROJECT_ROOT/Scripts/build-app-bundle.sh"
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
    --verify)
        sleep 1
        pgrep -x AudoCaptureApp >/dev/null
        ;;
    --logs|--telemetry)
        /usr/bin/log stream --info --style compact --predicate 'process == "AudoCaptureApp"'
        ;;
    --debug)
        sleep 1
        lldb -n AudoCaptureApp
        ;;
esac
