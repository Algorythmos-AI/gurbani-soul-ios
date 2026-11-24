#!/usr/bin/env bash
# Pick and verify the Xcode CI builds with. Kept as a script (not inline YAML) so
# ios/tests/test_select_xcode.py can run it against a fake /Applications.
#   APPS_DIR    where to look for Xcode_<version>.app (default /Applications)
#   MIN_MAJOR   floor; empty = read ios/tools/min-sdk-major
#   SELECT_XCODE_DRY_RUN=1   print the choice, do not xcode-select or verify (tests)
set -euo pipefail
err() {
  echo "::error::$1"
  ls -d "${APPS_DIR:-/Applications}"/Xcode*.app 2>/dev/null || true   # what the image does have
  exit 1
}

APPS_DIR="${APPS_DIR:-/Applications}"
if [ -z "${MIN_MAJOR:-}" ]; then
  FLOOR_FILE="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/../../.." && pwd)}/ios/tools/min-sdk-major"
  [ -f "$FLOOR_FILE" ] || err "missing $FLOOR_FILE (the minimum iOS SDK major)"
  MIN_MAJOR="$(tr -d '[:space:]' < "$FLOOR_FILE")"
fi
[[ "$MIN_MAJOR" =~ ^[0-9]+$ ]] || err "the Xcode floor must be an integer, got '$MIN_MAJOR'"

# Released Xcodes only: Xcode_<n>(.<n>)*.app. Betas / RCs (Xcode_27.1_beta.app, Xcode_27.2_RC.app)
# and the unversioned Xcode.app symlink never match. sort -V orders 27.10 after 27.2.
CHOICE=""
while IFS= read -r v; do
  if [ "${v%%.*}" -ge "$MIN_MAJOR" ]; then CHOICE="$v"; fi   # ascending, so the last match is the newest
done < <(
  for app in "$APPS_DIR"/Xcode_*.app; do
    [ -e "$app" ] || continue
    v="${app##*/Xcode_}"; v="${v%.app}"
    [[ "$v" =~ ^[0-9]+(\.[0-9]+)*$ ]] && echo "$v"
  done | sort -V
)
[ -n "$CHOICE" ] || err "no released Xcode $MIN_MAJOR+ in $APPS_DIR on this runner image — move runs-on to an image that has one (e.g. xcode-$MIN_MAJOR)"
XCODE="$APPS_DIR/Xcode_$CHOICE.app"
echo "selected $XCODE (floor $MIN_MAJOR)"
[ "${SELECT_XCODE_DRY_RUN:-0}" = 1 ] && exit 0

sudo xcode-select -s "$XCODE"
# Trust what the toolchain reports, not the folder name.
XV="$(xcodebuild -version | awk 'NR==1{print $2}')"
SDK="$(xcrun --sdk iphoneos --show-sdk-version)"
SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-version)"
for pair in "Xcode:$XV" "iOS SDK:$SDK" "iOS Simulator SDK:$SIM_SDK"; do
  name="${pair%%:*}"; ver="${pair#*:}"
  [[ "$ver" =~ ^[0-9]+ ]] && [ "${ver%%.*}" -ge "$MIN_MAJOR" ] \
    || err "$XCODE reports $name '$ver', below the floor $MIN_MAJOR"
done
echo "Xcode $XV · iOS SDK $SDK · iOS Simulator SDK $SIM_SDK"
if [ -n "${GITHUB_ENV:-}" ]; then
  { echo "SGGS_XCODE_MAJOR=${XV%%.*}"; echo "SGGS_SDK_MAJOR=${SIM_SDK%%.*}"; echo "SGGS_SIM_SDK=$SIM_SDK"; } >> "$GITHUB_ENV"
fi
