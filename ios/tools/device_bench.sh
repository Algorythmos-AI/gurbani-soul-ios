#!/usr/bin/env bash
# device_bench.sh — build and run the test suites on the owner's iPhone, one result bundle each.
#
#   device_bench.sh check                               is the phone available?
#   device_bench.sh build     <worktree>                build-for-testing + the build stamp
#   device_bench.sh unit      <worktree> <bundle>       SGGSTests
#   device_bench.sh ui        <worktree> <bundle> [-only-testing:…]   SGGSUITests (all, or the given tests)
#   device_bench.sh checklist <worktree> <bundle>       DeviceChecklistTests (TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1)
#   device_bench.sh shots     <worktree> <bundles-dir>  testCaptureScreens light + dark
#   device_bench.sh restore                             one ordinary launch (UITestVault hands real data back)
#
# <bundle> is the full path of a NEW .xcresult, normally <run>/bundles/<name>.xcresult from
# `device_run.py begin` (docs/ios/device-evidence.md). An existing path is refused: a reused
# result folder once failed a whole batch at once.
#
# The phone and account identifiers come from an untracked file, never from this script:
#   ${SGGS_DEVICE_BENCH_ENV:-~/.config/sggs/device-bench.env}   (mode 600)
#     SGGS_DEVICE_UDID=…   SGGS_TEAM_ID=…
#     SGGS_ASC_KEY_PATH=…  SGGS_ASC_KEY_ID=…  SGGS_ASC_ISSUER_ID=…
#     SGGS_DERIVED_DATA=…  (optional; default ~/Library/Developer/Xcode/DerivedData/sggs-device)
# The App Store Connect key is passed by path only and never printed.
#
# `build` writes <derived data>/sggs-build-stamp.json (HEAD, tree, dirty, Xcode). Every test command
# refuses to run when the worktree's HEAD tree is not the stamp's tree, so the build under test is
# always the commit under test. Each test command exits with xcodebuild's own status; the full log
# is kept next to the bundle (<bundle>.log).
set -euo pipefail

die() { echo "device_bench: $*" >&2; exit 2; }

ENV_FILE=${SGGS_DEVICE_BENCH_ENV:-$HOME/.config/sggs/device-bench.env}
[ -f "$ENV_FILE" ] || die "no $ENV_FILE — create it (mode 600) with the identifiers listed in this script's header"
mode=$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %Lp "$ENV_FILE")   # GNU, else BSD/macOS
[ "$mode" = 600 ] || die "$ENV_FILE is mode $mode; make it 600 (chmod 600 \"$ENV_FILE\")"
# shellcheck source=/dev/null
. "$ENV_FILE"
for v in SGGS_DEVICE_UDID SGGS_TEAM_ID SGGS_ASC_KEY_PATH SGGS_ASC_KEY_ID SGGS_ASC_ISSUER_ID; do
  [ -n "${!v:-}" ] || die "$v is not set in $ENV_FILE"
done
DD=${SGGS_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/sggs-device}
case "$DD" in /tmp/*|/private/tmp/*) die "SGGS_DERIVED_DATA must not be under /tmp (it gets wiped)";; esac
STAMP="$DD/sggs-build-stamp.json"
SIGN=(GENERATE_INFOPLIST_FILE=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic
      "DEVELOPMENT_TEAM=$SGGS_TEAM_ID" -allowProvisioningUpdates
      -authenticationKeyPath "$SGGS_ASC_KEY_PATH" -authenticationKeyID "$SGGS_ASC_KEY_ID"
      -authenticationKeyIssuerID "$SGGS_ASC_ISSUER_ID")

avail() { xcrun devicectl list devices 2>/dev/null | grep -F "$SGGS_DEVICE_UDID" | grep -v unavailable | grep -qE "available|connected"; }
need() {
  for _ in $(seq 1 12); do avail && return 0; sleep 5; done
  die "the phone is not available after 60 s (plug in, unlock, Developer Mode on)"
}
in_worktree() { [ -d "${1:-}" ] || die "no worktree ${1:-(missing)}"; cd "$1"; }
tree_of_head() { git rev-parse 'HEAD^{tree}'; }

# The build under test must be the worktree's HEAD.
stamp_matches() {
  [ -f "$STAMP" ] || die "no build stamp at $STAMP — run: device_bench.sh build <worktree>"
  local want; want=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["tree"])' "$STAMP")
  [ "$want" = "$(tree_of_head)" ] || die "the build is for tree $want, but HEAD's tree is $(tree_of_head) — rebuild first"
}

fresh_bundle() {
  local b=${1:-}
  [ -n "$b" ] || die "give the full path of a new .xcresult"
  case "$b" in *.xcresult) ;; *) die "$b must end in .xcresult";; esac
  case "$b" in /tmp/*|/private/tmp/*) die "$b is under /tmp, which gets wiped — use the run folder from device_run.py begin";; esac
  [ ! -e "$b" ] || die "$b exists — every bundle gets a fresh path"
  [ -d "$(dirname "$b")" ] || die "$(dirname "$b") does not exist"
}

# Run xcodebuild test-without-building into a fresh bundle; print a short tail; exit with ITS status.
run_tests() {
  local bundle=$1; shift
  local log="${bundle%.xcresult}.log" rc=0
  xcodebuild test-without-building -project ios/App/SGGS.xcodeproj -scheme SGGS \
    -destination "id=$SGGS_DEVICE_UDID" -derivedDataPath "$DD" -test-timeouts-enabled YES \
    -resultBundlePath "$bundle" "${SIGN[@]}" "$@" > "$log" 2>&1 || rc=$?
  grep -E "error:|TEST EXECUTE|Executed [0-9]+ tests?" "$log" | tail -8 || true
  echo "xcodebuild exit $rc · $(basename "$bundle") · log: $log"
  return "$rc"
}

cmd=${1:-}; shift || true
case "$cmd" in
  check)
    xcrun devicectl list devices | grep -i iphone | sed "s/$SGGS_DEVICE_UDID/<udid>/" || true
    if avail; then echo AVAILABLE; else echo UNAVAILABLE; exit 1; fi ;;
  build)
    need; in_worktree "${1:-}"
    df -h "$HOME" | tail -1
    make -s project >/dev/null
    rc=0
    mkdir -p "$DD"
    log="$DD/build.log"
    xcodebuild build-for-testing -project ios/App/SGGS.xcodeproj -scheme SGGS \
      -destination "id=$SGGS_DEVICE_UDID" -derivedDataPath "$DD" "${SIGN[@]}" > "$log" 2>&1 || rc=$?
    grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$log" | tail -5 || true
    if [ "$rc" -ne 0 ]; then rm -f "$STAMP"; echo "build failed (xcodebuild exit $rc) · log: $log"; exit "$rc"; fi
    dirty=false
    [ -z "$(git status --porcelain --untracked-files=no)" ] || dirty=true
    python3 - "$STAMP" "$(git rev-parse HEAD)" "$(tree_of_head)" "$dirty" "$(xcodebuild -version | head -1)" <<'PY'
import json, sys
from datetime import datetime, timezone
path, head, tree, dirty, xcode = sys.argv[1:]
json.dump({"head": head, "tree": tree, "dirty": dirty == "true", "configuration": "Debug", "build": "1",
           "xcode": xcode.replace("Xcode ", ""),
           "built_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
          open(path, "w"), indent=2)
PY
    [ "$dirty" = false ] || echo "WARNING: built from a dirty worktree — device_run.py begin will refuse this stamp"
    echo "stamp: $STAMP" ;;
  unit)
    need; in_worktree "${1:-}"; fresh_bundle "${2:-}"; stamp_matches
    run_tests "$2" -only-testing:SGGSTests ;;
  ui)
    need; in_worktree "${1:-}"; fresh_bundle "${2:-}"; stamp_matches
    bundle=$2; shift 2
    only=(-only-testing:SGGSUITests)
    [ $# -eq 0 ] || only=("$@")
    run_tests "$bundle" "${only[@]}" ;;
  checklist)
    need; in_worktree "${1:-}"; fresh_bundle "${2:-}"; stamp_matches
    TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1 run_tests "$2" -only-testing:SGGSUITests/DeviceChecklistTests ;;
  shots)
    need; in_worktree "${1:-}"; dir=${2:-}; [ -d "$dir" ] || die "no bundles folder $dir"; stamp_matches
    rc=0
    for look in light dark; do
      fresh_bundle "$dir/shots-$look.xcresult"
      mkdir -p "$dir/../shots/$look"
      TEST_RUNNER_SGGS_SHOT_DIR="$dir/../shots/$look" TEST_RUNNER_SGGS_SHOT_APPEARANCE=$look \
        run_tests "$dir/shots-$look.xcresult" -only-testing:SGGSUITests/SGGSUITests/testCaptureScreens || rc=$?
    done
    exit "$rc" ;;
  restore)
    need
    xcrun devicectl device process launch --device "$SGGS_DEVICE_UDID" --terminate-existing org.sggs.app >/dev/null
    echo "ordinary launch done (UITestVault restores the real data) — record it: device_run.py record-manual <run> restore pass" ;;
  *)
    sed -n '2,9p' "$0"; exit 64 ;;
esac
