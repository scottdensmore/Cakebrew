#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ICON="$REPO_ROOT/Cakebrew/AppIcon.icon"
OUTPUT_DIR="$REPO_ROOT/Cakebrew/Images.xcassets/AppIcon.appiconset"
ICON_COMPOSER_TOOL="$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool"

if [[ ! -x "$ICON_COMPOSER_TOOL" ]]; then
    echo "error: Icon Composer's ictool was not found; Xcode 26 or newer is required" >&2
    exit 1
fi

if [[ ! -d "$SOURCE_ICON" ]]; then
    echo "error: layered icon source not found at $SOURCE_ICON" >&2
    exit 1
fi

targets=(
    "16 1 icon_16x16.png"
    "16 2 icon_16x16@2x.png"
    "32 1 icon_32x32.png"
    "32 2 icon_32x32@2x.png"
    "128 1 icon_128x128.png"
    "128 2 icon_128x128@2x.png"
    "256 1 icon_256x256.png"
    "256 2 icon_256x256@2x.png"
    "512 1 icon_512x512.png"
    "512 2 icon_512x512@2x.png"
)

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cakebrew-appicon.XXXXXX")"
BACKUP_DIR="$TEMP_DIR/original"
INSTALL_STARTED=false

cleanup() {
    status=$?
    trap - EXIT

    if [[ "$status" -ne 0 && "$INSTALL_STARTED" == true ]]; then
        echo "error: fallback installation failed; attempting to restore the prior icon set" >&2
        set +e
        restore_failed=false
        for target in "${targets[@]}"; do
            read -r _ _ filename <<< "$target"
            if ! install -m 0644 "$BACKUP_DIR/$filename" "$OUTPUT_DIR/$filename"; then
                echo "fatal: could not restore $filename" >&2
                restore_failed=true
            fi
        done

        if [[ "$restore_failed" == true ]]; then
            echo "fatal: the complete prior icon set is retained at $BACKUP_DIR" >&2
            exit "$status"
        fi
    fi

    rm -rf "$TEMP_DIR"
    exit "$status"
}

trap cleanup EXIT

for target in "${targets[@]}"; do
    read -r points scale filename <<< "$target"
    expected_pixels=$((points * scale))
    output="$TEMP_DIR/$filename"

    "$ICON_COMPOSER_TOOL" "$SOURCE_ICON" \
        --export-image \
        --output-file "$output" \
        --platform macOS \
        --rendition Default \
        --width "$points" \
        --height "$points" \
        --scale "$scale"

    width="$(sips -g pixelWidth "$output" | awk '/pixelWidth:/ { print $2 }')"
    height="$(sips -g pixelHeight "$output" | awk '/pixelHeight:/ { print $2 }')"

    if [[ "$width" != "$expected_pixels" || "$height" != "$expected_pixels" ]]; then
        echo "error: $filename rendered at ${width}x${height}; expected ${expected_pixels}x${expected_pixels}" >&2
        exit 1
    fi
done

mkdir "$BACKUP_DIR"
for target in "${targets[@]}"; do
    read -r _ _ filename <<< "$target"
    cp -p "$OUTPUT_DIR/$filename" "$BACKUP_DIR/$filename"
done

INSTALL_STARTED=true
for target in "${targets[@]}"; do
    read -r _ _ filename <<< "$target"
    install -m 0644 "$TEMP_DIR/$filename" "$OUTPUT_DIR/$filename"
done
INSTALL_STARTED=false

echo "Exported and verified ${#targets[@]} macOS 15 fallback icons from $SOURCE_ICON"
