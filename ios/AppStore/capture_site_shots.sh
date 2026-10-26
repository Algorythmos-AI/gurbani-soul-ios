#!/usr/bin/env bash
# Capture the gurbanisoul.com screenshot set from the app sources in the current checkout, with the
# PUBLIC (Gurmukhi-only) database, on fresh simulators with a 9:41 status bar and the Raag Clock pinned.
#
#   bash ios/AppStore/capture_site_shots.sh <out-dir>
#
# Writes, each from its own fresh simulator:
#   <out>/iphone-light/   iPhone 17 Pro, light: testCaptureScreens + testVaarsWeave + SiteShotTests
#   <out>/iphone-dark/    the same in dark
#   <out>/ipad-portrait/  iPad Pro 13" (M5), light: testCaptureScreens
#   <out>/ipad-landscape/ the same, rotated after launch (SGGS_SHOT_LANDSCAPE=1)
#   <out>/widgets/        Raag Now, Hukam and Nitnem widget renders (unit tests, ImageRenderer)
#   <out>/SHA256SUMS, <out>/provenance.json
#
# Needs: db/sggs.sqlite (`make dataset`), the personal pair in ios/Resources, xcodegen, Xcode 26+.
# The public DB is copied into the BUILT .app only (never ios/Resources); the simulators are deleted.
# A failing capture test is reported and the run goes on: the shots it did write still land, and a
# reviewer checks the set. Used by .github/workflows/ios-site-shots.yml.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT="$(mkdir -p "${1:?usage: capture_site_shots.sh <out-dir>}" && cd "$1" && pwd)"
DD="ios/App/build/site-dd"
STAGE="ios/App/build/site-public"
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
FAILED=()

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c "
import json,sys
rs=[r for r in json.load(sys.stdin)['runtimes'] if r['platform']=='iOS' and r['isAvailable']]
print(sorted(rs, key=lambda r: [int(x) for x in r['version'].split('.')])[-1]['identifier'])")
IPHONE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
IPAD=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
say "runtime $RUNTIME · $IPHONE · $IPAD · sources $(git rev-parse HEAD) ($(git describe --tags --always))"

say "1/4 public DB (Gurmukhi-only) into $STAGE"
mkdir -p "$STAGE"
python3 pipeline/build_ios_db.py --profile public db/sggs.sqlite "$STAGE/sggs-ios.sqlite"
test -s "$STAGE/sggs-ios.manifest.json" || { echo "public manifest missing" >&2; exit 1; }

say "2/4 build for testing (Debug, simulator, unsigned — as CI)"
xcodegen generate --spec ios/App/project.yml --project ios/App >/dev/null
xcodebuild build-for-testing -project ios/App/SGGS.xcodeproj -scheme SGGS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO -quiet
APP=$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' ! -name '*Runner.app' | head -1)
cp "$STAGE/sggs-ios.sqlite" "$STAGE/sggs-ios.manifest.json" "$APP/"
# Prove the swap: the bundled DB is the public one, and it carries no English layer.
DB_SHA=$(shasum -a 256 "$APP/sggs-ios.sqlite" | cut -d' ' -f1)
WANT=$(python3 -c "import json;print(json.load(open('$STAGE/sggs-ios.manifest.json'))['db_sha256'])")
test "$DB_SHA" = "$WANT" || { echo "public DB swap failed ($DB_SHA != $WANT)" >&2; exit 1; }
EN=$(sqlite3 "$APP/sggs-ios.sqlite" "select count(*) from sqlite_master where name in ('translations','fts_en')")
test "$EN" = "0" || { echo "the public DB still carries the English layer" >&2; exit 1; }
echo "  public DB $DB_SHA in $(basename "$APP") (built copy only); English tables: none"

new_sim() {  # device-type, name, appearance → udid (booted, status bar overridden)
  local udid
  udid=$(xcrun simctl create "site-shots-$2" "$1" "$RUNTIME")
  {
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b
    xcrun simctl ui "$udid" appearance "$3"
    xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  } >&2
  echo "$udid"
}
drop_sim() { xcrun simctl shutdown "$1" >/dev/null 2>&1 || true; xcrun simctl delete "$1" >/dev/null 2>&1 || true; }

run_tests() {  # udid, set, appearance, extra-env, tests...
  local udid="$1" set="$2" look="$3" extra="$4"; shift 4
  mkdir -p "$OUT/$set"
  for t in "$@"; do
    # shellcheck disable=SC2086
    env TEST_RUNNER_SGGS_SHOT_DIR="$OUT/$set" TEST_RUNNER_SGGS_SHOT_APPEARANCE="$look" \
        TEST_RUNNER_SGGS_CLOCK_NOW=581 TEST_RUNNER_SGGS_CLOCK_MODE=fixed TEST_RUNNER_SGGS_CLOCK_NO_COORDS=1 $extra \
      xcodebuild test-without-building -project ios/App/SGGS.xcodeproj -scheme SGGS -derivedDataPath "$DD" \
        -destination "id=$udid" -only-testing:"$t" CODE_SIGNING_ALLOWED=NO -quiet \
      || { echo "::warning::capture test failed: $set $t"; FAILED+=("$set:$t"); }
  done
}

IPHONE_TESTS=(SGGSUITests/SGGSUITests/testCaptureScreens SGGSUITests/SGGSUITests/testVaarsWeave
              SGGSUITests/SiteShotTests/testCaptureVerify SGGSUITests/SiteShotTests/testCaptureAbout)

say "3/4 iPhone 17 Pro — light, then dark; widgets"
for look in light dark; do
  udid=$(new_sim "$IPHONE" "iphone-$look" "$look")
  run_tests "$udid" "iphone-$look" "$look" "SGGS_NOOP=1" "${IPHONE_TESTS[@]}"
  if [ "$look" = light ]; then
    mkdir -p "$OUT/widgets"
    TEST_RUNNER_SGGS_WIDGET_SNAPSHOT_DIR="$OUT/widgets" xcodebuild test-without-building \
      -project ios/App/SGGS.xcodeproj -scheme SGGS -derivedDataPath "$DD" -destination "id=$udid" \
      -only-testing:SGGSTests/WidgetRenderTests -only-testing:SGGSTests/HukamWidgetRenderTests \
      -only-testing:SGGSTests/NitnemWidgetRenderTests CODE_SIGNING_ALLOWED=NO -quiet \
      || { echo "::warning::widget renders failed"; FAILED+=("widgets"); }
  fi
  drop_sim "$udid"
done

say "4/4 iPad Pro 13\" — portrait, then landscape (light)"
udid=$(new_sim "$IPAD" ipad-portrait light)
run_tests "$udid" ipad-portrait light "SGGS_NOOP=1" SGGSUITests/SGGSUITests/testCaptureScreens
drop_sim "$udid"
udid=$(new_sim "$IPAD" ipad-landscape light)
run_tests "$udid" ipad-landscape light "TEST_RUNNER_SGGS_SHOT_LANDSCAPE=1" SGGSUITests/SGGSUITests/testCaptureScreens
drop_sim "$udid"

say "provenance"
XCODE=$(xcodebuild -version | tr '\n' ' ')
python3 - "$OUT" "$(git rev-parse HEAD)" "$(git describe --tags --always)" "$RUNTIME" "$IPHONE" "$IPAD" \
  "$DB_SHA" "$XCODE" "${FAILED[*]:-}" <<'PY'
import json, sys
out, sha, ref, runtime, iphone, ipad, db, xcode, failed = sys.argv[1:]
json.dump({"sources_commit": sha, "describe": ref, "runtime": runtime, "iphone": iphone, "ipad": ipad,
           "public_db_sha256": db, "xcode": xcode.strip(), "status_bar": "9:41, wifi 3, cell 4, 100% charged",
           "clock": "SGGS_CLOCK_NOW=581 (09:41), fixed mode, no coordinates",
           "failed_tests": failed.split() if failed else []},
          open(f"{out}/provenance.json", "w"), indent=2)
PY
(cd "$OUT" && find . -name '*.png' | sort | xargs shasum -a 256 > SHA256SUMS)
echo; sed "s#  \./#  #" "$OUT/SHA256SUMS" | awk '{print "  "$2}'
echo "OK  $(grep -c png "$OUT/SHA256SUMS") shots from $(git rev-parse --short HEAD); failed: ${FAILED[*]:-none}"
