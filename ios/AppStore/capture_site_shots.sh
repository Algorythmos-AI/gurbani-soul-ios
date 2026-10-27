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
#   $SITE_SHOTS_RESULTS (default <out>/../site-shots-xcresult): one .xcresult per run, for diagnosis
#
# SiteShotTests is the driver: each surface group launches the app afresh, and a shot is written only
# while the element that proves its screen is up. The workflow drops the driver into older tags.
#
# Needs: db/sggs.sqlite (`make dataset`), the personal pair in ios/Resources, xcodegen, Xcode 26+.
# The public DB is copied into the BUILT .app only (never ios/Resources); the simulators are deleted.
# A failing capture test is reported and the run goes on, so the shots that did land are kept; the
# script then fails if any test failed or the self-check (check_site_shots.py) finds an expected
# name missing, identical pictures under different names, or a landscape shot that is not landscape.
# Each failure is named with its test and assertion (read from the run's result bundle), in the log,
# as an annotation and in provenance.json; the workflow uploads the bundles when anything failed.
# Used by .github/workflows/ios-site-shots.yml.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the driver's own checkout (the workflow's commit)
OUT="$(mkdir -p "${1:?usage: capture_site_shots.sh <out-dir>}" && cd "$1" && pwd)"
DD="ios/App/build/site-dd"
STAGE="ios/App/build/site-public"
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
FAILED=()
RESULTS="${SITE_SHOTS_RESULTS:-$(dirname "$OUT")/site-shots-xcresult}"
mkdir -p "$RESULTS"
FAILURES="$RESULTS/failures.tsv"                       # set <TAB> test <TAB> assertion, one per line
: > "$FAILURES"

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

# The failed assertions in a result bundle, one "test <TAB> assertion" line each (Xcode 16+).
failures_in() {
  xcrun xcresulttool get test-results summary --path "$1" --compact 2>/dev/null | python3 -c '
import json, sys
try:
    summary = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for f in summary.get("testFailures", []):
    test = f.get("testIdentifierString") or f.get("testName") or "?"
    print(test.replace("\t", " ") + "\t" + " ".join(f.get("failureText", "").split()))'
}

# One xcodebuild run into its own result bundle. Every failed assertion is named, with its test, in
# the log and as an annotation. EXTRA_ENV (an array) adds TEST_RUNNER_ variables for this run.
run_tests() {  # udid, set, appearance, tests...
  local udid="$1" set="$2" look="$3" bundle t why rc=0; shift 3
  mkdir -p "$OUT/$set"
  bundle="$RESULTS/$set.xcresult"; rm -rf "$bundle"
  local only=(); for t in "$@"; do only+=(-only-testing:"$t"); done
  # not -quiet: the per-test lines are what tell a hung test from a failed one in the raw log
  env TEST_RUNNER_SGGS_SHOT_DIR="$OUT/$set" TEST_RUNNER_SGGS_SHOT_APPEARANCE="$look" \
      TEST_RUNNER_SGGS_CLOCK_NOW=581 TEST_RUNNER_SGGS_CLOCK_MODE=fixed TEST_RUNNER_SGGS_CLOCK_NO_COORDS=1 \
      ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} \
    xcodebuild test-without-building -project ios/App/SGGS.xcodeproj -scheme SGGS -derivedDataPath "$DD" \
      -destination "id=$udid" "${only[@]}" -resultBundlePath "$bundle" CODE_SIGNING_ALLOWED=NO || rc=$?
  local named=()
  while IFS=$'\t' read -r t why; do
    [ -n "$t" ] || continue
    echo "  FAILED $set $t: $why"
    echo "::error title=site shots: $set ${t##*/}::${why//%/%25}"
    printf '%s\t%s\t%s\n' "$set" "$t" "$why" >> "$FAILURES"
    named+=("$t")
  done < <(failures_in "$bundle")
  for t in $(printf '%s\n' ${named[@]+"${named[@]}"} | sort -u); do FAILED+=("$set:${t##*/}"); done
  if [ "$rc" -ne 0 ] && [ "${#named[@]}" -eq 0 ]; then
    echo "::error title=site shots: $set::xcodebuild exit $rc and no failed assertion in $bundle (crash or hang?)"
    printf '%s\t%s\t%s\n' "$set" xcodebuild "exit $rc, no failed assertion in the result bundle" >> "$FAILURES"
    FAILED+=("$set:xcodebuild")
  fi
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
# moved into place. The request is removed last, which releases the test. A request that got no
# settled frame (the screen still moving after 12 tries) is removed with nothing written, and the
# test fails on the missing file: a frame caught mid-animation is never a shot. The pinned clock
# (SGGS_CLOCK_NOW) freezes the Raag Clock's hands, the one surface that would move for ever.
serve_frames() {  # udid, dir
  local udid="$1" dir="$2" r name tmp prev h w ht settled
  set +e                                   # a failed frame must not stop the server (its test then fails)
  while :; do
    for r in "$dir"/.request-*; do
      [ -e "$r" ] || continue
      name="${r##*/.request-}"; tmp="$dir/.frame-$name.png"; prev=""; settled=0
      for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
        xcrun simctl io "$udid" screenshot "$tmp" >/dev/null 2>&1 || { sleep 1; continue; }
        h=$(shasum -a 256 "$tmp" | cut -c1-16)
        [ "$h" = "$prev" ] && { settled=1; break; }
        prev="$h"; sleep 1
      done
      if [ "$settled" -eq 0 ]; then
        echo "::warning::ipad-landscape $name: the frame never settled, nothing written" >&2
        rm -f "$tmp"
      elif [ -s "$tmp" ]; then
        w=$(sips -g pixelWidth "$tmp" | awk '/pixelWidth/{print $2}')
        ht=$(sips -g pixelHeight "$tmp" | awk '/pixelHeight/{print $2}')
        if [ "$ht" -gt "$w" ]; then sips -r 270 "$tmp" >/dev/null; fi
        mv -f "$tmp" "$dir/$name.png"
      else
        echo "::warning::ipad-landscape $name: the settled frame is empty, nothing written" >&2
        rm -f "$tmp"
      fi
      rm -f "$r"
    done
    sleep 0.5
  done
}

say "3/4 iPhone 17 Pro — light, then dark; widgets"
for look in light dark; do
  udid=$(new_sim "$IPHONE" "iphone-$look" "$look")
  EXTRA_ENV=()
  run_tests "$udid" "iphone-$look" "$look" "${IPHONE_TESTS[@]}"
  if [ "$look" = light ]; then
    EXTRA_ENV=(TEST_RUNNER_SGGS_WIDGET_SNAPSHOT_DIR="$OUT/widgets")
    run_tests "$udid" widgets "$look" SGGSTests/WidgetRenderTests SGGSTests/HukamWidgetRenderTests \
      SGGSTests/NitnemWidgetRenderTests
  fi
  drop_sim "$udid"
done

say "4/4 iPad Pro 13\" — portrait, then landscape (light)"
udid=$(new_sim "$IPAD" ipad-portrait light)
EXTRA_ENV=()
run_tests "$udid" ipad-portrait light "${SITE_TESTS[@]}"
drop_sim "$udid"
udid=$(new_sim "$IPAD" ipad-landscape light)
mkdir -p "$OUT/ipad-landscape"
serve_frames "$udid" "$OUT/ipad-landscape" & SERVER=$!
EXTRA_ENV=(TEST_RUNNER_SGGS_SHOT_LANDSCAPE=1 TEST_RUNNER_SGGS_SHOT_HOST_FRAMES=1)
run_tests "$udid" ipad-landscape light "${SITE_TESTS[@]}"
kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true
find "$OUT/ipad-landscape" -name '.*' -type f -delete
drop_sim "$udid"

say "provenance"
XCODE=$(xcodebuild -version | tr '\n' ' ')
python3 - "$OUT" "$(git rev-parse HEAD)" "$(git describe --tags --always)" "$RUNTIME" "$IPHONE" "$IPAD" \
  "$DB_SHA" "$XCODE" "$FAILURES" "${FAILED[*]:-}" <<'PY'
import json, sys
out, sha, ref, runtime, iphone, ipad, db, xcode, failures, failed = sys.argv[1:]
rows = [line.rstrip("\n").split("\t", 2) for line in open(failures, encoding="utf-8") if line.strip()]
json.dump({"sources_commit": sha, "describe": ref, "runtime": runtime, "iphone": iphone, "ipad": ipad,
           "public_db_sha256": db, "xcode": xcode.strip(), "status_bar": "9:41, wifi 3, cell 4, 100% charged",
           "clock": "SGGS_CLOCK_NOW=581 (09:41), fixed mode, no coordinates",
           "failed_tests": failed.split() if failed else [],
           "failures": [dict(zip(("set", "test", "assertion"), r)) for r in rows]},
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
