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
DERIVED="build/screenshots"

region() {
    case "$1" in
        en) echo US ;;
        fr) echo FR ;;
        *)  echo DE ;;
    esac
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

        TEST_RUNNER_SCREENSHOT_LANGUAGE="$lang" \
        TEST_RUNNER_SCREENSHOT_DIR="$dir" \
        TEST_RUNNER_SCREENSHOT_RECIPE="$RECIPE" \
        xcodebuild test-without-building \
            -project BackPlaner.xcodeproj \
            -scheme BackPlaner \
            -destination "id=$udid" \
            -derivedDataPath "$DERIVED" \
            -only-testing:BackPlanerUITests/AppStoreScreenshots \
            -testLanguage "$lang" \
            -testRegion "$(region "$lang")" \
            -resultBundlePath "$DERIVED/results-$folder-$lang-$(date +%H%M%S).xcresult" \
            -quiet

        ls "$dir" | sed 's/^/      /'
    done

    xcrun simctl status_bar "$udid" clear
done

echo "▸ Done: $OUT"
