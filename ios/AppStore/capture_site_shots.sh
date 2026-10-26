#!/usr/bin/env bash
# Capture the gurbanisoul.com screenshot set from the app sources in the current checkout, with the
# PUBLIC (Gurmukhi-only) database, on fresh simulators with a 9:41 status bar and the Raag Clock pinned.
#
#   bash ios/AppStore/capture_site_shots.sh <out-dir>
#
# Writes, each from its own fresh simulator:
#   <out>/iphone-light/   iPhone 17 Pro, light: SiteShotTests (every surface) + testVaarsWeave
#   <out>/iphone-dark/    the same in dark
#   <out>/ipad-portrait/  iPad Pro 13" (M5), light: SiteShotTests' surfaces
#   <out>/ipad-landscape/ the same, rotated after launch (SGGS_SHOT_LANDSCAPE=1); each frame is the
#                         simulator's own, taken by this script when the test asks for it
#   <out>/widgets/        Raag Now, Hukam and Nitnem widget renders (unit tests, ImageRenderer)
#   <out>/SHA256SUMS, <out>/provenance.json
#
# SiteShotTests is the driver: each surface group launches the app afresh, and a shot is written only
# while the element that proves its screen is up. The workflow drops the driver into older tags.
#
# Needs: db/sggs.sqlite (`make dataset`), the personal pair in ios/Resources, xcodegen, Xcode 26+.
# The public DB is copied into the BUILT .app only (never ios/Resources); the simulators are deleted.
# A failing capture test is reported and the run goes on, so the shots that did land are kept; the
# script then fails if any test failed or the self-check (check_site_shots.py) finds identical
# pictures under different names or a landscape shot that is not landscape.
# Used by .github/workflows/ios-site-shots.yml.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the driver's own checkout (the workflow's commit)
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

run_tests() {  # udid, set, appearance, extra-env, tests... (one xcodebuild run; each failed test is named)
  local udid="$1" set="$2" look="$3" extra="$4" log t rc=0; shift 4
  mkdir -p "$OUT/$set"
  log="$(mktemp)"
  local only=(); for t in "$@"; do only+=(-only-testing:"$t"); done
  # shellcheck disable=SC2086
  env TEST_RUNNER_SGGS_SHOT_DIR="$OUT/$set" TEST_RUNNER_SGGS_SHOT_APPEARANCE="$look" \
      TEST_RUNNER_SGGS_CLOCK_NOW=581 TEST_RUNNER_SGGS_CLOCK_MODE=fixed TEST_RUNNER_SGGS_CLOCK_NO_COORDS=1 $extra \
    xcodebuild test-without-building -project ios/App/SGGS.xcodeproj -scheme SGGS -derivedDataPath "$DD" \
      -destination "id=$udid" "${only[@]}" CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | tee "$log" || rc=$?
  # a failure names its test: "error: -[SGGSUITests.SiteShotTests testCaptureThemes] : …" and
  # "Test Case '-[SGGSUITests.SiteShotTests testCaptureThemes]' failed"
  while read -r t; do
    echo "::warning::capture test failed: $set $t"; FAILED+=("$set:$t")
  done < <(grep -E 'error|failed' "$log" | grep -oE '\[[A-Za-z0-9_]+\.[A-Za-z0-9_]+ test[A-Za-z0-9_]+\]' \
             | sed -E 's/.* (test[A-Za-z0-9_]+)\]/\1/' | sort -u)
  if [ "$rc" -ne 0 ] && ! printf '%s\n' "${FAILED[@]:-}" | grep -q "^$set:"; then
    echo "::warning::capture run failed: $set (xcodebuild exit $rc)"; FAILED+=("$set:xcodebuild")
  fi
  rm -f "$log"
}

# Every surface group, each its own launch (SiteShotTests); the iPhone adds Verify, About and the Vaars.
SITE_TESTS=()
for t in SearchAndReader Clock Nitnem Index Themes Constellation Insights Lineage More; do
  SITE_TESTS+=("SGGSUITests/SiteShotTests/testCapture$t")
done
IPHONE_TESTS=("${SITE_TESTS[@]}" SGGSUITests/SiteShotTests/testCaptureVerify SGGSUITests/SiteShotTests/testCaptureAbout
              SGGSUITests/SGGSUITests/testVaarsWeave)

# The landscape set's frames: SiteShotTests (SGGS_SHOT_HOST_FRAMES=1) leaves <dir>/.request-<name>
# and waits. An XCUITest screenshot after a rotation stores the pixels one way and an EXIF
# orientation (8) that turns them (the v1.4.9 run), so the frame comes from the simulator instead:
# taken until two in a row agree (settled), turned to landscape when simctl wrote it portrait, then
# moved into place. The request is removed last, which releases the test.
serve_frames() {  # udid, dir
  local udid="$1" dir="$2" r name tmp prev h w ht
  set +e                                   # a failed frame must not stop the server (its test then fails)
  while :; do
    for r in "$dir"/.request-*; do
      [ -e "$r" ] || continue
      name="${r##*/.request-}"; tmp="$dir/.frame-$name.png"; prev=""
      for _ in 1 2 3 4 5 6 7 8; do
        xcrun simctl io "$udid" screenshot "$tmp" >/dev/null 2>&1 || { sleep 1; continue; }
        h=$(shasum -a 256 "$tmp" | cut -c1-16)
        [ "$h" = "$prev" ] && break
        prev="$h"; sleep 1
      done
      if [ -s "$tmp" ]; then
        w=$(sips -g pixelWidth "$tmp" | awk '/pixelWidth/{print $2}')
        ht=$(sips -g pixelHeight "$tmp" | awk '/pixelHeight/{print $2}')
        if [ "$ht" -gt "$w" ]; then sips -r 270 "$tmp" >/dev/null; fi
        mv -f "$tmp" "$dir/$name.png"
      fi
      rm -f "$r"
    done
    sleep 0.5
  done
}

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
run_tests "$udid" ipad-portrait light "SGGS_NOOP=1" "${SITE_TESTS[@]}"
drop_sim "$udid"
udid=$(new_sim "$IPAD" ipad-landscape light)
mkdir -p "$OUT/ipad-landscape"
serve_frames "$udid" "$OUT/ipad-landscape" & SERVER=$!
run_tests "$udid" ipad-landscape light "TEST_RUNNER_SGGS_SHOT_LANDSCAPE=1 TEST_RUNNER_SGGS_SHOT_HOST_FRAMES=1" \
  "${SITE_TESTS[@]}"
kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true
find "$OUT/ipad-landscape" -name '.*' -type f -delete
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
# Shots only: never a hidden file (a request or a frame in flight), which upload-artifact skips too.
(cd "$OUT" && find . -name '*.png' ! -name '.*' ! -path '*/.*/*' | sort | xargs shasum -a 256 > SHA256SUMS)
echo; sed "s#  \./#  #" "$OUT/SHA256SUMS" | awk '{print "  "$2}'

say "self-check"
CHECK=0; python3 "$HERE/check_site_shots.py" "$OUT" || CHECK=1
echo "$(grep -c png "$OUT/SHA256SUMS") shots from $(git rev-parse --short HEAD); failed: ${FAILED[*]:-none}"
if [ "${#FAILED[@]}" -gt 0 ] || [ "$CHECK" -ne 0 ]; then
  echo "::error::the site-shot set is not clean: review the failed tests and the self-check above"; exit 1
fi
echo OK
