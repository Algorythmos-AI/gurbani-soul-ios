#!/usr/bin/env bash
# Capture the App Store screenshot sources from the app at HEAD — the release candidate — with the
# PUBLIC (Gurmukhi-only) database, on fresh simulators, light mode, 9:41 status bar, Raag Clock pinned.
#
#   bash ios/AppStore/capture_store_shots.sh <out-dir>
#
# Writes <out-dir>/iphone-6.9/*.png and <out-dir>/ipad-13/*.png (portrait), plus the
# sensitivity-review pair <out-dir>/review/ang1400_saroop_{on,off}.png. Then frame them:
#   uv run --with pillow python3 ios/AppStore/compose_store_shots.py --captures <out-dir>
#
# The public DB is built into ios/App/build/ and copied into the BUILT .app (a copy in DerivedData),
# never into ios/Resources. The simulators are created for this run and deleted afterwards.
# Needs: `make dataset` done, `make ios-db-repair` (the personal pair the project builds with), Xcode 26.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT="$(mkdir -p "${1:?usage: capture_store_shots.sh <out-dir>}" && cd "$1" && pwd)"
DD="ios/App/build/shots-dd"
STAGE="ios/App/build/shots-public"
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c "
import json,sys
rs=[r for r in json.load(sys.stdin)['runtimes'] if r['platform']=='iOS' and r['isAvailable']]
print(sorted(rs, key=lambda r: [int(x) for x in r['version'].split('.')])[-1]['identifier'])")
say "runtime $RUNTIME · app sources $(git rev-parse --short HEAD) ($(git describe --tags --always))"

say "1/4 public DB (Gurmukhi-only) into $STAGE — scripture checksum proven by the builder"
mkdir -p "$STAGE"
python3 pipeline/build_ios_db.py --profile public db/sggs.sqlite "$STAGE/sggs-ios.sqlite"
test -s "$STAGE/sggs-ios.manifest.json" || { echo "public manifest missing" >&2; exit 1; }

say "2/4 build for testing (Debug, simulator, unsigned — as CI)"
make project >/dev/null
xcodebuild build-for-testing -project ios/App/SGGS.xcodeproj -scheme SGGS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO -quiet
APP=$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' ! -name '*Runner.app' | head -1)
cp "$STAGE/sggs-ios.sqlite" "$STAGE/sggs-ios.manifest.json" "$APP/"
echo "  public DB swapped into $(basename "$APP") (built copy only)"

run_on() {  # device-type, set-name, extra-env...
  local type="$1" set="$2"; shift 2
  local udid
  udid=$(xcrun simctl create "store-shots-$set" "$type" "$RUNTIME")
  trap 'xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true' RETURN
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance light
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  mkdir -p "$OUT/$set"
  for pass in "$@"; do
    # shellcheck disable=SC2086
    env TEST_RUNNER_SGGS_SHOT_DIR="$OUT/$set" TEST_RUNNER_SGGS_CLOCK_NOW=581 TEST_RUNNER_SGGS_CLOCK_MODE=fixed \
        TEST_RUNNER_SGGS_CLOCK_NO_COORDS=1 $pass \
      xcodebuild test-without-building -project ios/App/SGGS.xcodeproj -scheme SGGS -derivedDataPath "$DD" \
        -destination "id=$udid" -only-testing:SGGSUITests/SGGSUITests/testCaptureScreens CODE_SIGNING_ALLOWED=NO -quiet \
      || { echo "capture failed on $set ($pass)" >&2; return 1; }
  done
}

say "3/4 iPhone 6.9\" (iPhone 17 Pro Max)"
run_on com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max iphone-6.9 "SGGS_NOOP=1"

say "4/4 iPad 13\" (iPad Pro 13-inch M5) — portrait, and the saroop review pair"
# Portrait only: an XCUITest screenshot taken after rotating to landscape comes back rotated and
# not filling the frame (seen 2026-09-26), so the store set uses portrait on iPad too.
IPAD=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
run_on "$IPAD" ipad-13 "SGGS_NOOP=1"
udid=$(xcrun simctl create store-shots-review "$IPAD" "$RUNTIME")
xcrun simctl boot "$udid"; xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl ui "$udid" appearance light
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100
mkdir -p "$OUT/review"
TEST_RUNNER_SGGS_SHOT_DIR="$OUT/review" xcodebuild test-without-building -project ios/App/SGGS.xcodeproj \
  -scheme SGGS -derivedDataPath "$DD" -destination "id=$udid" \
  -only-testing:SGGSUITests/SGGSUITests/testCaptureSaroopReview CODE_SIGNING_ALLOWED=NO -quiet || echo "saroop review capture failed" >&2
xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true

echo
find "$OUT" -name '*.png' | sort | sed "s#^$OUT/#  #"
echo "OK  captured from $(git rev-parse --short HEAD) — frame them with compose_store_shots.py; delete $DD when done"
