#!/bin/bash
#
# Takes the App Store screenshots for iPhone and iPad 13" in German,
# English and French, by running the UI test AppStoreScreenshots on the
# simulators, and sets the headline from docs/appstore/captions.json over
# each (scripts/appstore-captions.swift). The pictures land in
# docs/appstore/<version>/<device>/<language>, the plain screenshots in a
# folder roh/ next to them (not tracked by git).
#
#   scripts/appstore-screenshots.sh              all devices and languages
#   LANGS="en" scripts/appstore-screenshots.sh    only English
#   DEVICES="iphone" scripts/appstore-screenshots.sh  only the iPhone
#   CAPTIONS_ONLY=1 scripts/appstore-screenshots.sh  no new screenshots: only set
#                                                the headlines over the roh/ pictures
#                                                again, e.g. after changing a text
#
# Settings (environment variables, all optional):
#   VERSION  folder name under docs/appstore            (default: 2.0)
#   DEVICES  "iphone", "ipad", or both                  (default: iphone ipad)
#   IPHONE   simulator for the iPhone shots, 1206×2622  (default: iPhone 17 Pro)
#   IPAD     simulator for the 13" shots, 2064×2752     (default: iPad Pro 13-inch (M5))
#
# App Store Connect only accepts iPhone screenshots of exactly 1179×2556,
# 2556×1179, 1206×2622 or 2622×1206 pixels; "iPhone 17 Pro Max" (and the
# other *Max/Air models) render at other sizes and get rejected on upload.
#   LANGS    languages                                  (default: de en fr)
#   RECIPE   public recipe to show, start of its name   (default: Kartoffelbrot mit Saaten)
#   DERIVED  build folder (default: ~/Library/Developer/Xcode/DerivedData/BackPlaner-Screenshots)
#
# The build folder stays outside the project on purpose: a project inside an
# iCloud Drive folder such as ~/Documents gets extended attributes on every
# file built there, and code signing refuses them ("resource fork, Finder
# information, or similar detritus not allowed").
#
# The test uses the simulator's own data and the live recipe database, so the
# simulator needs network access and a registered App Check debug token, as
# when the app is run from Xcode. It plans the chosen recipe, starting at
# 20:00 (StoreUITestCase.planStart) so that no step falls into the night;
# that plan stays in the simulator until the next run clears it.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-2.0}"
DEVICES="${DEVICES:-iphone ipad}"
IPHONE="${IPHONE:-iPhone 17 Pro}"
IPAD="${IPAD:-iPad Pro 13-inch (M5)}"
LANGS="${LANGS:-de en fr}"
RECIPE="${RECIPE:-Kartoffelbrot mit Saaten}"

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
        name = attachment.get("suggestedHumanReadableName", "")
        match = re.match(r"^[a-z]{2}-(\d\d-[a-z-]+)", name)
        if match:
            # The screen structure left behind by a failed run is text.
            extension = ".txt" if match.group(1).endswith("hierarchy") else ".png"
            shutil.copy(os.path.join(source, attachment["exportedFileName"]),
                        os.path.join(target, match.group(1) + extension))
PY
    fi
    rm -rf "$tmp"
}

# The manuals take their pictures from the plain iPhone screenshots in $1:
# the main menu from the App Store screens, the recipe list, the new-recipe
# form and the settings from the extra screens numbered 90 and up. Scaled to
# the 402 pt width the manual pages use; $2 is the language, $3 the manual
# image folder for it.
manual_images() {
    local raw="$1" lang="$2" target="$3"
    mkdir -p "$target"
    local pairs=("02-startbildschirm:hauptmenue" "93-rezept-datenbank:oeffentliche-rezepte"
                 "91-neues-rezept:neues-rezept" "92-einstellungen:einstellungen")
    for pair in "${pairs[@]}"; do
        local source="$raw/${pair%%:*}.png" name="${pair##*:}"
        [[ -f "$source" ]] || continue
        sips --resampleWidth 402 "$source" --out "$target/$name.png" >/dev/null
    done
}

# Sets the headlines over the plain screenshots in $1/roh and writes the
# App Store pictures to $1; $2 is the language. The extra screens for the
# manuals (numbers from 90 up) stay out of the App Store folder.
caption_pictures() {
    local dir="$1" lang="$2"
    find "$dir" -maxdepth 1 -name '*.png' -delete
    swift scripts/appstore-captions.swift docs/appstore/captions.json "$lang" "$dir/roh" "$dir"
    rm -f "$dir"/9[0-9]-*.png
}

udid_of() {
    xcrun simctl list devices available \
        | grep -F "    $1 (" \
        | head -1 \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

if [[ -n "${CAPTIONS_ONLY:-}" ]]; then
    for role in $DEVICES; do
        case "$role" in
            iphone) folder="iphone-6.9" ;;
            ipad)   folder="ipad-13" ;;
            *) echo "Unknown DEVICES entry „$role“ (use iphone and/or ipad)" >&2; exit 1 ;;
        esac
        for lang in $LANGS; do
            dir="$PWD/$OUT/$folder/$lang"
            if [[ ! -d "$dir/roh" ]]; then
                echo "▸ $folder/$lang: no roh/ folder with plain screenshots; run without CAPTIONS_ONLY first" >&2
                continue
            fi
            echo "▸ $folder/$lang"
            caption_pictures "$dir" "$lang"
            ls "$dir" | grep -v '^roh$' | sed 's/^/      /'
        done
    done
    exit 0
fi

echo "▸ Building once for all simulators …"
xcodebuild build-for-testing \
    -project BackPlaner.xcodeproj \
    -scheme BackPlaner \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$DERIVED" \
    -quiet

failed=()

devices=()
for role in $DEVICES; do
    case "$role" in
        iphone) devices+=("$IPHONE") ;;
        ipad)   devices+=("$IPAD") ;;
        *) echo "Unknown DEVICES entry „$role“ (use iphone and/or ipad)" >&2; exit 1 ;;
    esac
done

for device in "${devices[@]}"; do
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

    for lang in $LANGS; do
        dir="$PWD/$OUT/$folder/$lang"
        rm -rf "$dir"
        mkdir -p "$dir/roh"
        echo "  ▸ $lang → ${dir#$PWD/}"

        # A fresh boot for every language: on a simulator that had already
        # run the test once, the next run now and then never came back
        # after its last picture (xcodebuild sat there with the app gone
        # from the screen), while a rebooted simulator ran through.
        xcrun simctl shutdown "$udid" 2>/dev/null || true
        xcrun simctl boot "$udid" 2>/dev/null || true
        xcrun simctl bootstatus "$udid" -b >/dev/null
        xcrun simctl ui "$udid" appearance light
        xcrun simctl status_bar "$udid" override \
            --time "9:41" \
            --dataNetwork wifi --wifiMode active --wifiBars 3 \
            --cellularMode active --cellularBars 4 \
            --batteryState charged --batteryLevel 100

        # Clear what earlier runs left behind, as the previews do before each
        # scene: the plan, the shopping lists and the local copy of the
        # recipe that planning it stores on the device — otherwise the
        # recipe list shows the recipe twice and the baking tab asks
        # whether to replace the existing plan.
        TEST_RUNNER_PREVIEW_LANGUAGE="$lang" \
        TEST_RUNNER_SCREENSHOT_RECIPE="$RECIPE" \
        xcodebuild test-without-building \
            -project BackPlaner.xcodeproj \
            -scheme BackPlaner \
            -destination "id=$udid" \
            -derivedDataPath "$DERIVED" \
            -only-testing:"BackPlanerUITests/AppPreview/testPrepare" \
            -testLanguage "$lang" \
            -testRegion "$(region "$lang")" \
            -quiet >/dev/null 2>&1 || echo "      (clearing the old data failed; the pictures may show a dialog or a doubled recipe)"

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
            export_screenshots "$bundle" "$dir/roh"
            if [[ "$folder" == "iphone-6.9" ]]; then
                case "$lang" in
                    de) manual_images "$dir/roh" "$lang" "docs/images" ;;
                    *)  manual_images "$dir/roh" "$lang" "docs/images/$lang" ;;
                esac
            fi
            caption_pictures "$dir" "$lang"
            ls "$dir" | grep -v '^roh$' | sed 's/^/      /'
        else
            export_screenshots "$bundle" "$dir/roh"
            failed+=("$folder/$lang")
            echo "      ✗ failed after: $(ls "$dir/roh" | tr '\n' ' ')"
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
