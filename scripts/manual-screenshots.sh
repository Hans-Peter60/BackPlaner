#!/bin/bash
#
# Takes the manuals' pictures that need a device with own recipes and a
# baking history — the list of own recipes and the photo cloud — by running
# the UI test ManualScreenshots on a simulator that holds such data, in
# German, English and French, and scales them to the 402 pt width of the
# manual pages: docs/images/ (de), docs/images/en/ and docs/images/fr/.
# The store run (appstore-screenshots.sh) cannot take them: it clears the
# simulator's data before each language.
#
#   scripts/manual-screenshots.sh               de, en and fr
#   LANGS="fr" scripts/manual-screenshots.sh    only French
#   SKIP_BUILD=1 scripts/manual-screenshots.sh  reuse the build of a store run
#
# Settings (environment variables, all optional):
#   SIM      the simulator's UDID (default: the newest "iPhone 17", which is
#            402 pt wide like the other manual pictures)
#   LANGS    languages (default: de en fr)
#   DERIVED  build folder (default: ~/Library/Developer/Xcode/DerivedData/BackPlaner-Screenshots)
#
# The simulator keeps its data; the test only reads it. It should hold a
# good number of own recipes with pictures and a baking history of several
# recipes (see docs/AppStore-Screenshots.md for a data file that does).

set -euo pipefail

cd "$(dirname "$0")/.."

LANGS="${LANGS:-de en fr}"
DERIVED="${DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/BackPlaner-Screenshots}"
SIM="${SIM:-$(xcrun simctl list devices available | grep -E '^ +iPhone 17 \(' | tail -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')}"
if [[ -z "$SIM" ]]; then
    echo "No iPhone 17 simulator found; choose one with SIM=<udid>" >&2
    exit 1
fi

region() {
    case "$1" in
        en) echo US ;;
        fr) echo FR ;;
        *)  echo DE ;;
    esac
}

# Copies the pictures attached to the test result in $1 into the manual
# folder $2 under their manual names, scaled to 402 pt.
export_pictures() {
    local tmp
    tmp="$(mktemp -d)"
    xcrun xcresulttool export attachments --path "$1" --output-path "$tmp" >/dev/null
    /usr/bin/python3 - "$tmp" "$2" <<'PY'
import json, os, re, subprocess, sys
source, target = sys.argv[1], sys.argv[2]
names = {"95-eigene-rezepte": "eigene-rezepte", "96-backhistorie-fotowolke": "backhistorie-fotowolke"}
os.makedirs(target, exist_ok=True)
with open(os.path.join(source, "manifest.json")) as file:
    manifest = json.load(file)
for test in manifest:
    for attachment in test.get("attachments", []):
        match = re.match(r"^[a-z]{2}-(\d\d-[a-z-]+)", attachment.get("suggestedHumanReadableName", ""))
        if match and match.group(1) in names:
            out = os.path.join(target, names[match.group(1)] + ".png")
            subprocess.run(["sips", "--resampleWidth", "402", os.path.join(source, attachment["exportedFileName"]),
                            "--out", out], check=True, stdout=subprocess.DEVNULL)
            print(f"      {os.path.relpath(out)}")
PY
    rm -rf "$tmp"
}

if [[ -z "${SKIP_BUILD:-}" ]]; then
    echo "▸ Building …"
    xcodebuild build-for-testing \
        -project BackPlaner.xcodeproj \
        -scheme BackPlaner \
        -testPlan AllTests \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$DERIVED" \
        -quiet
fi

echo "▸ Simulator $SIM"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl ui "$SIM" appearance light
xcrun simctl status_bar "$SIM" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100

failed=()
for lang in $LANGS; do
    case "$lang" in
        de) target="docs/images" ;;
        *)  target="docs/images/$lang" ;;
    esac
    echo "  ▸ $lang → $target"
    bundle="$DERIVED/results-manual-$lang-$(date +%H%M%S).xcresult"
    if TEST_RUNNER_MANUAL_SCREENSHOT_LANGUAGE="$lang" \
       xcodebuild test-without-building \
           -project BackPlaner.xcodeproj \
           -scheme BackPlaner \
           -testPlan AllTests \
           -destination "id=$SIM" \
           -derivedDataPath "$DERIVED" \
           -only-testing:BackPlanerUITests/ManualScreenshots \
           -testLanguage "$lang" \
           -testRegion "$(region "$lang")" \
           -resultBundlePath "$bundle" \
           -quiet >/dev/null 2>&1
    then
        export_pictures "$bundle" "$target"
    else
        failed+=("$lang")
        echo "      ✗ failed; details: open \"$bundle\""
    fi
done

xcrun simctl status_bar "$SIM" clear
xcrun simctl shutdown "$SIM" 2>/dev/null || true

if (( ${#failed[@]} )); then
    echo "▸ Failed: ${failed[*]}" >&2
    exit 1
fi
echo "▸ Done. Now run: python3 docs/build-manual-html.py"
