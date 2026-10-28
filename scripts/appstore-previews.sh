#!/bin/bash
#
# Records the raw footage for the App Store previews: the UI test AppPreview
# drives the app through three scenes while the simulator's screen is
# recorded. One movie per scene, device and language, under
# docs/appstore/<version>/preview/<device>/<language>/ (git-ignored — the
# movies are large and are cut in iMovie anyway).
#
#   scripts/appstore-previews.sh                 all devices, languages, scenes
#   LANGS="de" DEVICES="iphone" scripts/appstore-previews.sh
#   SCENES="plan" scripts/appstore-previews.sh    only the first scene
#
# Settings (environment variables, all optional):
#   VERSION  folder name under docs/appstore            (default: 2.0)
#   DEVICES  "iphone", "ipad", or both                  (default: iphone ipad)
#   IPHONE   simulator for the iPhone footage           (default: iPhone 17 Pro)
#   IPAD     simulator for the 13" footage              (default: iPad Pro 13-inch (M5))
#   LANGS    languages                                  (default: de en fr)
#   SCENES   plan, calculators, shopping                (default: all three)
#   RECIPE   public recipe to show, start of its name   (default: Kartoffelbrot mit Saaten)
#   DERIVED  build folder (default: ~/Library/Developer/Xcode/DerivedData/BackPlaner-Screenshots)
#
# Each movie starts while the test runner is still being installed, so it
# opens on the home screen and the app's launch, and ends after the last
# pause of its scene; trim both ends in iMovie. The simulator records at its
# own resolution (1206×2622 on the iPhone 17 Pro, 2064×2752 on the iPad);
# iMovie's "App-Vorschau" project exports in the sizes App Store Connect
# accepts (886×1920 or 1320×2868 for the iPhone, 1200×1600 or 2064×2752 for
# the iPad) and at a variable frame rate; iMovie's export fixes that at
# 30 fps. Previews must be 15 to 30 seconds long.
#
# Like the screenshots, this needs network access and a registered App Check
# debug token in the simulator; the plan scene replaces the recipe's plan,
# which starts at 20:00 (StoreUITestCase.planStart) so that no step falls into the
# night.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-2.0}"
DEVICES="${DEVICES:-iphone ipad}"
IPHONE="${IPHONE:-iPhone 17 Pro}"
IPAD="${IPAD:-iPad Pro 13-inch (M5)}"
LANGS="${LANGS:-de en fr}"
SCENES="${SCENES:-plan calculators shopping}"
RECIPE="${RECIPE:-Kartoffelbrot mit Saaten}"

OUT="docs/appstore/$VERSION/preview"
DERIVED="${DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/BackPlaner-Screenshots}"

region() {
    case "$1" in
        en) echo US ;;
        fr) echo FR ;;
        *)  echo DE ;;
    esac
}

test_method() {
    case "$1" in
        plan)        echo testPlanScene ;;
        calculators) echo testCalculatorsScene ;;
        shopping)    echo testShoppingAndTranslationScene ;;
        *) echo "Unknown scene „$1“ (use plan, calculators, shopping)" >&2; exit 1 ;;
    esac
}

scene_number() {
    case "$1" in
        plan)        echo 1 ;;
        calculators) echo 2 ;;
        shopping)    echo 3 ;;
    esac
}

# A tiny helper that reports a movie's length, size and frame rate, built
# once per run (Spotlight's mdls knows nothing about a file just written).
build_movie_info() {
    MOVIE_INFO="$DERIVED/movie-info"
    [[ -x "$MOVIE_INFO" ]] && return
    mkdir -p "$DERIVED"
    cat > "$DERIVED/movie-info.swift" <<'SWIFT'
import AVFoundation
import Foundation

let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let seconds = CMTimeGetSeconds(asset.duration)
let track = asset.tracks(withMediaType: .video).first
let size = track?.naturalSize ?? .zero
let fps = track?.nominalFrameRate ?? 0
print("\(Int(seconds.rounded())) s, \(Int(size.width))×\(Int(size.height)), \(Int(fps.rounded())) fps")
SWIFT
    xcrun swiftc -O "$DERIVED/movie-info.swift" -o "$MOVIE_INFO" 2>/dev/null || MOVIE_INFO=""
}

movie_info() {
    if [[ -n "$MOVIE_INFO" ]]; then "$MOVIE_INFO" "$1"; else echo "?"; fi
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
    -testPlan AllTests \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$DERIVED" \
    -quiet
build_movie_info

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
        mkdir -p "$dir"
        echo "  ▸ $lang → ${dir#$PWD/}"

        for scene in $SCENES; do
            method="$(test_method "$scene")"
            movie="$dir/$(scene_number "$scene")-$scene.mov"
            log="$(mktemp)"

            # Clear what earlier scenes and runs left behind, without
            # recording: the plan, the shopping lists and the local copy of
            # the recipe that setting the reminders stores on the device.
            # Before every scene, not once per language — the plan scene
            # itself leaves the copy behind, and the recipe list of the
            # following scenes showed the recipe twice.
            TEST_RUNNER_PREVIEW_LANGUAGE="$lang" \
            TEST_RUNNER_SCREENSHOT_RECIPE="$RECIPE" \
            xcodebuild test-without-building \
                -project BackPlaner.xcodeproj \
                -scheme BackPlaner \
                -testPlan AllTests \
                -destination "id=$udid" \
                -derivedDataPath "$DERIVED" \
                -only-testing:"BackPlanerUITests/AppPreview/testPrepare" \
                -testLanguage "$lang" \
                -testRegion "$(region "$lang")" \
                -quiet >/dev/null 2>&1 || echo "      (clearing the old data failed; the scene may show a dialog or a doubled recipe)"

            # The test first, the recording once the test runner is up: a
            # recording that is already running while xcodebuild installs and
            # starts the runner can keep the test from ever launching. The
            # app itself is launched by the runner a moment later, so its
            # start is still on film.
            # The runner of the previous test may still be shutting down;
            # waiting for the new one below would otherwise see the old one
            # and start the recording too early (which once cost ten minutes
            # of home screen before the test got going).
            while pgrep -qf "BackPlanerUITests-Runner"; do sleep 0.5; done

            bundle="$DERIVED/preview-$folder-$lang-$scene-$(date +%H%M%S).xcresult"
            TEST_RUNNER_PREVIEW_LANGUAGE="$lang" \
            TEST_RUNNER_SCREENSHOT_RECIPE="$RECIPE" \
            xcodebuild test-without-building \
                -project BackPlaner.xcodeproj \
                -scheme BackPlaner \
                -testPlan AllTests \
                -destination "id=$udid" \
                -derivedDataPath "$DERIVED" \
                -only-testing:"BackPlanerUITests/AppPreview/$method" \
                -testLanguage "$lang" \
                -testRegion "$(region "$lang")" \
                -resultBundlePath "$bundle" \
                -quiet >/dev/null 2>&1 &
            tester=$!
            for _ in $(seq 1 600); do
                pgrep -qf "BackPlanerUITests-Runner" && break
                kill -0 "$tester" 2>/dev/null || break
                sleep 0.2
            done
            sleep 1

            xcrun simctl io "$udid" recordVideo --codec h264 --mask ignored --force "$movie" >"$log" 2>&1 &
            recorder=$!

            if wait "$tester"; then
                status="✓"
            else
                status="✗ (test failed, see \"$bundle\")"
                failed+=("$folder/$lang/$scene")
            fi

            # Stop the recording; simctl finishes writing the file on SIGINT.
            kill -INT "$recorder" 2>/dev/null || true
            wait "$recorder" 2>/dev/null || true
            rm -f "$log"

            if [[ -s "$movie" ]]; then
                echo "      $status ${movie##*/} ($(movie_info "$movie"))"
            else
                echo "      ✗ no movie written for $scene"
                failed+=("$folder/$lang/$scene")
            fi
        done
    done

    xcrun simctl status_bar "$udid" clear
done

if (( ${#failed[@]} )); then
    echo "▸ Done with failures: ${failed[*]}" >&2
    exit 1
fi
echo "▸ Done: $OUT"
