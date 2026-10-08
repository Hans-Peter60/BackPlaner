#!/bin/bash
#
# Takes the App Store screenshots for iPhone 6.9" and iPad 13" in German,
# English and French, by running the UI test AppStoreScreenshots on the
# simulators. The pictures land in docs/appstore/<version>/<device>/<language>.
#
#   scripts/appstore-screenshots.sh            all devices and languages
#   LANGS="en" scripts/appstore-screenshots.sh  only English
#
# Settings (environment variables, all optional):
#   VERSION  folder name under docs/appstore            (default: 1.3)
#   IPHONE   simulator for the 6.9" shots, 1320×2868    (default: iPhone 17 Pro Max)
#   IPAD     simulator for the 13" shots, 2064×2752     (default: iPad Pro 13-inch (M5))
#   LANGS    languages                                  (default: de en fr)
#   RECIPE   public recipe to show, start of its name   (default: Sauerteigbrot mit Kartoffeln und Saaten)
#   DERIVED  build folder (default: ~/Library/Developer/Xcode/DerivedData/BackPlaner-Screenshots)
#
# The build folder stays outside the project on purpose: a project inside an
# iCloud Drive folder such as ~/Documents gets extended attributes on every
# file built there, and code signing refuses them ("resource fork, Finder
# information, or similar detritus not allowed").
#
# The test uses the simulator's own data and the live recipe database, so the
# simulator needs network access and a registered App Check debug token, as
# when the app is run from Xcode. It plans the chosen recipe; that plan stays
# in the simulator.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.3}"
IPHONE="${IPHONE:-iPhone 17 Pro Max}"
IPAD="${IPAD:-iPad Pro 13-inch (M5)}"
LANGS="${LANGS:-de en fr}"
RECIPE="${RECIPE:-Sauerteigbrot mit Kartoffeln und Saaten}"

OUT="docs/appstore/$VERSION"
DERIVED="${DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/BackPlaner-Screenshots}"

region() {
    case "$1" in
        en) echo US ;;
        fr) echo FR ;;
        *)  echo DE ;;
    esac
}

# Copies the screenshots attached to the test result in $1 into the folder
# $2, named after the attachment: "de-01-startbildschirm" → 01-startbildschirm.png.
# Works for a failed run too, with the screens taken up to the failure.
export_screenshots() {
    local tmp
    tmp="$(mktemp -d)"
    if xcrun xcresulttool export attachments --path "$1" --output-path "$tmp" >/dev/null 2>&1; then
        /usr/bin/python3 - "$tmp" "$2" <<'PY'
import json, os, re, shutil, sys
source, target = sys.argv[1], sys.argv[2]
with open(os.path.join(source, "manifest.json")) as file:
    manifest = json.load(file)
for test in manifest:
    for attachment in test.get("attachments", []):
        match = re.match(r"^[a-z]{2}-(\d\d-[a-z-]+)", attachment.get("suggestedHumanReadableName", ""))
        if match:
            shutil.copy(os.path.join(source, attachment["exportedFileName"]),
                        os.path.join(target, match.group(1) + ".png"))
PY
    fi
    rm -rf "$tmp"
}

udid_of() {
    xcrun simctl list devices available \
        | grep -F "    $1 (" \
        | head -1 \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

echo "▸ Building once for all simulators …"
xcodebuild build-for-testing \
    -project BackPlaner.xcodeproj \
    -scheme BackPlaner \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$DERIVED" \
    -quiet

failed=()

for device in "$IPHONE" "$IPAD"; do
    udid="$(udid_of "$device")"
    if [[ -z "$udid" ]]; then
        echo "Simulator „$device“ not found. Available:" >&2
        xcrun simctl list devices available | grep -E "iPhone|iPad" >&2
        echo "Choose one with IPHONE=… or IPAD=…" >&2
        exit 1
    fi

    case "$device" in
        iPad*) folder="ipad-13" ;;
        *)     folder="iphone-6.9" ;;
    esac

    echo "▸ $device ($udid)"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl ui "$udid" appearance light
    xcrun simctl status_bar "$udid" override \
        --time "9:41" \
        --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 \
        --batteryState charged --batteryLevel 100

    for lang in $LANGS; do
        dir="$PWD/$OUT/$folder/$lang"
        rm -rf "$dir"
        mkdir -p "$dir"
        echo "  ▸ $lang → ${dir#$PWD/}"

        bundle="$DERIVED/results-$folder-$lang-$(date +%H%M%S).xcresult"
        if TEST_RUNNER_SCREENSHOT_LANGUAGE="$lang" \
           TEST_RUNNER_SCREENSHOT_RECIPE="$RECIPE" \
           xcodebuild test-without-building \
               -project BackPlaner.xcodeproj \
               -scheme BackPlaner \
               -destination "id=$udid" \
               -derivedDataPath "$DERIVED" \
               -only-testing:BackPlanerUITests/AppStoreScreenshots \
               -testLanguage "$lang" \
               -testRegion "$(region "$lang")" \
               -resultBundlePath "$bundle" \
               -quiet >/dev/null 2>&1
        then
            export_screenshots "$bundle" "$dir"
            ls "$dir" | sed 's/^/      /'
        else
            export_screenshots "$bundle" "$dir"
            failed+=("$folder/$lang")
            echo "      ✗ failed after: $(ls "$dir" | tr '\n' ' ')"
            # The test's own message, e.g. which screen or button was missing.
            xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null \
                | grep -E '"failureText"|"testName"' | sed 's/^ */      /' || true
            echo "      Details with the screen at the moment of failure: open \"$bundle\""
        fi
    done

    xcrun simctl status_bar "$udid" clear
done

if (( ${#failed[@]} )); then
    echo "▸ Done with failures: ${failed[*]}" >&2
    exit 1
fi
echo "▸ Done: $OUT"
