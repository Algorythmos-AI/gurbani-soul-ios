#!/usr/bin/env bash
# Fails if a built SGGS.app carries any UI-test hook: the data vault (which wipes and restores the
# app's storage), the launch-environment switches that select it, or the launch timeline (D10). They are compiled only under
# `#if DEBUG`; this proves it on the actual bundle of a release candidate. Every file in the
# bundle is searched, not only the main executable: a Debug build keeps its Swift code in
# SGGS.debug.dylib (the negative control that caught this), and an extension has its own binary.
#   usage: ios/tools/check_no_test_hooks.sh path/to/SGGS.app
set -euo pipefail
APP="${1:?usage: $0 path/to/SGGS.app}"
[ -f "$APP/Info.plist" ] || { echo "FAIL: $APP is not an app bundle"; exit 1; }
found=0
for marker in uitest-vault SGGS_UITEST SGGS_UITEST_RELAUNCH SGGS_UITEST_COLD_VERIFY SGGS_UITEST_HOLD_VERIFY \
              SGGS_UITEST_LAUNCH_METRICS UITestVault LaunchClock launchMetrics nitnemDrawn sggs-launch-metrics; do
  # the scripture database is excluded: it is data, never code, and large
  hits=$(find "$APP" -type f ! -name '*.sqlite' -print0 | xargs -0 env LC_ALL=C grep -a -l -- "$marker" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "FAIL: '$marker' in: $(echo "$hits" | sed "s|$APP/||" | tr '\n' ' ')"; found=1
  fi
done
[ "$found" = 0 ] || exit 1
echo "OK: no UI-test hooks anywhere in $(basename "$APP")"
