#!/bin/bash
#
# Takes the App Store screenshots for iPhone, iPad 13" and iPhone Duo (folded
# and unfolded) in German, English and French, by running the UI test
# AppStoreScreenshots on the simulators, and sets the headline from
# docs/appstore/captions.json over each (scripts/appstore-captions.swift).
# The pictures land in docs/appstore/<version>/<device>/<language>, the plain
# screenshots in a folder roh/ next to them (not tracked by git).
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
#   DEVICES  any of "iphone", "ipad", "duo-outer", "duo-inner"
#                                                       (default: all four)
#   IPHONE   simulator for the iPhone shots, 1206×2622  (default: iPhone 17 Pro)
#   IPAD     simulator for the 13" shots, 2064×2752     (default: iPad Pro 13-inch (M5))
#   DUO      simulator for the iPhone Duo shots         (default: iPhone Duo)
#            folded 1398×2034 (outer display), unfolded 2853×2007 (inner display)
#   HINGE    the `hinge` tool that folds the Duo simulator (default: found on PATH
#            or in /opt/homebrew/bin; install with `brew install artemnovichkov/tap/hinge`)
#   APP_CHECK_DEBUG_TOKEN  the registered App Check debug token, handed to the app
#            on launch; without it the script takes the token of the first simulator
#            that has the app installed, so a new simulator (the Duo) can read the
#            recipe database without being registered in the Firebase console
#
# App Store Connect only accepts iPhone screenshots of exactly 1179×2556,
# 2556×1179, 1206×2622 or 2622×1206 pixels; "iPhone 17 Pro Max" (and the
# other *Max/Air models) render at other sizes and get rejected on upload.
# For the iPhone Duo it accepts 1398×2034 / 2034×1398 (outer display) and
# 2007×2853 / 2853×2007 (inner display).
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

VERSION="${VERSION:-2.1}"
DEVICES="${DEVICES:-iphone ipad duo-outer duo-inner}"
IPHONE="${IPHONE:-iPhone 17 Pro}"
IPAD="${IPAD:-iPad Pro 13-inch (M5)}"
DUO="${DUO:-iPhone Duo}"
HINGE="${HINGE:-$(command -v hinge || echo /opt/homebrew/bin/hinge)}"
LANGS="${LANGS:-de en fr}"
RECIPE="${RECIPE:-Kartoffelbrot mit Saaten}"
BUNDLE_ID="de.hpm64625.BackPlaner"

OUT="docs/appstore/$VERSION"
DERIVED="${DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/BackPlaner-Screenshots}"

# The simulator name, the output folder and (for the Duo) the fold for a
# DEVICES role, written into $device, $folder and $posture.
resolve_role() {
    posture=""
    caption_options=()
    case "$1" in
        iphone)    device="$IPHONE"; folder="iphone-6.9" ;;
        ipad)      device="$IPAD";   folder="ipad-13" ;;
        # Unfolded, the Duo is turned so that its inner display stands
        # upright (2007×2853): held the usual way the display is landscape,
        # captured in portrait pixel order with the picture on its side, and
        # the test's swipes went the wrong way. The captures come out a
        # pixel short of the sizes App Store Connect accepts, so the
        # headline step brings them to the exact size.
        duo-outer) device="$DUO";    folder="iphone-duo-outer"; posture="close"
                   caption_options=(--size 1398x2034) ;;
        duo-inner) device="$DUO";    folder="iphone-duo-inner"; posture="open"
                   caption_options=(--size 2007x2853) ;;
        *) echo "Unknown DEVICES entry „$1“ (use iphone, ipad, duo-outer, duo-inner)" >&2; exit 1 ;;
    esac
}

# The App Check debug token the app on one of the simulators already uses
# (the Firebase debug provider keeps it in the app's defaults); empty when
# the app is installed nowhere.
stored_app_check_token() {
    /usr/bin/python3 - "$BUNDLE_ID" <<'PY'
import glob, os, plistlib, sys
bundle = sys.argv[1]
root = os.path.expanduser("~/Library/Developer/CoreSimulator/Devices")
for meta in glob.glob(f"{root}/*/data/Containers/Data/Application/*/.com.apple.mobile_container_manager.metadata.plist"):
    try:
        if plistlib.load(open(meta, "rb")).get("MCMMetadataIdentifier") != bundle:
            continue
        prefs = os.path.join(os.path.dirname(meta), "Library/Preferences", bundle + ".plist")
        token = plistlib.load(open(prefs, "rb")).get("GACAppCheckDebugToken")
    except Exception:
        continue
    if token:
        print(token)
        break
PY
}

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
# the main menu and the timeline from the App Store screens, the recipe
# list, the new-recipe form and the settings from the extra screens
# numbered 90 and up. Scaled to
# the 402 pt width the manual pages use; $2 is the language, $3 the manual
# image folder for it.
manual_images() {
    local raw="$1" lang="$2" target="$3"
    mkdir -p "$target"
    local pairs=("02-startbildschirm:hauptmenue" "04-timeline:geplante-schritte-timeline"
                 "93-rezept-datenbank:oeffentliche-rezepte"
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
    swift scripts/appstore-captions.swift docs/appstore/captions.json "$lang" "$dir/roh" "$dir" ${caption_options[@]+"${caption_options[@]}"}
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
        resolve_role "$role"
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
    -testPlan AllTests \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$DERIVED" \
    -quiet

failed=()

for role in $DEVICES; do resolve_role "$role"; done   # reject unknown roles before the first run

APP_CHECK_DEBUG_TOKEN="${APP_CHECK_DEBUG_TOKEN:-$(stored_app_check_token)}"
if [[ -z "$APP_CHECK_DEBUG_TOKEN" ]]; then
    echo "▸ No App Check debug token found; a simulator that has never run the app will see an empty recipe database" >&2
fi

for role in $DEVICES; do
    resolve_role "$role"
    udid="$(udid_of "$device")"
    if [[ -z "$udid" ]]; then
        echo "Simulator „$device“ not found. Available:" >&2
        xcrun simctl list devices available | grep -E "iPhone|iPad" >&2
        echo "Choose one with IPHONE=…, IPAD=… or DUO=…" >&2
        exit 1
    fi
    if [[ -n "$posture" && ! -x "$HINGE" ]]; then
        echo "The iPhone Duo pictures need the hinge tool to fold the simulator: brew install artemnovichkov/tap/hinge" >&2
        exit 1
    fi

    echo "▸ $device ($udid)${posture:+, hinge $posture}"

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
        if [[ -n "$posture" ]]; then
            # Folded (outer display) or unfolded flat (inner display). A
            # fresh boot starts folded, so the fold is set after every boot;
            # the orientation survives a reboot and is set explicitly too.
            # (Folded, the status bar stands beside the camera cutout at the
            # right edge; that is the outer display's layout, Settings and
            # the home screen look the same, not a wrong orientation.)
            "$HINGE" -d "$udid" "$posture" >/dev/null
            sleep 2
            if [[ "$posture" == "open" ]]; then
                "$HINGE" -d "$udid" orient landscape-left >/dev/null
            else
                "$HINGE" -d "$udid" orient portrait >/dev/null
            fi
            sleep 2
        fi

        # Clear what earlier runs left behind, as the previews do before each
        # scene: the plan, the shopping lists and the local copy of the
        # recipe that planning it stores on the device — otherwise the
        # recipe list shows the recipe twice and the baking tab asks
        # whether to replace the existing plan.
        TEST_RUNNER_PREVIEW_LANGUAGE="$lang" \
        TEST_RUNNER_SCREENSHOT_RECIPE="$RECIPE" \
        TEST_RUNNER_APP_CHECK_DEBUG_TOKEN="$APP_CHECK_DEBUG_TOKEN" \
        xcodebuild test-without-building \
            -project BackPlaner.xcodeproj \
            -scheme BackPlaner \
            -testPlan AllTests \
            -destination "id=$udid" \
            -derivedDataPath "$DERIVED" \
            -only-testing:"BackPlanerUITests/AppPreview/testPrepare" \
            -testLanguage "$lang" \
            -testRegion "$(region "$lang")" \
            -quiet >/dev/null 2>&1 || echo "      (clearing the old data failed; the pictures may show a dialog or a doubled recipe)"

        bundle="$DERIVED/results-$folder-$lang-$(date +%H%M%S).xcresult"
        if TEST_RUNNER_SCREENSHOT_LANGUAGE="$lang" \
           TEST_RUNNER_SCREENSHOT_RECIPE="$RECIPE" \
           TEST_RUNNER_APP_CHECK_DEBUG_TOKEN="$APP_CHECK_DEBUG_TOKEN" \
           xcodebuild test-without-building \
               -project BackPlaner.xcodeproj \
               -scheme BackPlaner \
               -testPlan AllTests \
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
