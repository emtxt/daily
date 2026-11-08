#!/bin/sh
set -eu

cd "$(dirname "$0")"
swift build --configuration release --product daily
bin_dir=$(swift build --configuration release --show-bin-path)

output_dir=${1:-"$PWD/.build/local"}
destination="$output_dir/Daily.app"
mkdir -p "$output_dir"
stage=$(mktemp -d "$output_dir/.daily.XXXXXX")
trap 'rm -r "$stage"' EXIT

bundle="$stage/Daily.app"
iconset="$stage/DailyIcon.iconset"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$iconset"
install -m 755 "$bin_dir/daily" "$bundle/Contents/MacOS/daily"
install -m 644 Info.plist "$bundle/Contents/Info.plist"
sips -s format png Resources/DailyIcon.svg --out "$stage/DailyIcon.png" >/dev/null
for size in 16 32 128 256 512; do
    retina=$((size * 2))
    sips -z "$size" "$size" "$stage/DailyIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$retina" "$retina" "$stage/DailyIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/DailyIcon.icns"

codesign --force --sign - --timestamp=none "$bundle"
codesign --verify --strict "$bundle"

previous="$stage/previous.app"
if [ -e "$destination" ] || [ -L "$destination" ]; then
    bundle_id=$(plutil -extract CFBundleIdentifier raw Info.plist)
    if [ -L "$destination" ] ||
        [ "$(plutil -extract CFBundleIdentifier raw "$destination/Contents/Info.plist" 2>/dev/null)" != "$bundle_id" ]; then
        printf 'Cannot replace %s with the app bundle.\n' "$destination" >&2
        exit 1
    fi
    mv "$destination" "$previous"
fi
if ! mv "$bundle" "$output_dir/"; then
    if [ -d "$previous" ] && ! mv "$previous" "$destination"; then
        trap - EXIT
        printf 'Previous app saved at %s\n' "$previous" >&2
    fi
    exit 1
fi
printf '%s\n' "$destination"
