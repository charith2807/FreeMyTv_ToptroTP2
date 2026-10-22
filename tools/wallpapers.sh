#!/usr/bin/env bash
# Turns your photos into home screen wallpapers: center-cropped to 16:9, resized, saved as JPEG in app/assets/wallpapers
# (wall1.jpg, wall2.jpg...), replacing the ones there. Rebuild afterwards (./build.sh).
#
#   tools/wallpapers.sh ~/Pictures/a.jpg ~/Pictures/b.png ...     # 1280×720 (720p projectors and 1 GB TVs)
#   tools/wallpapers.sh --size 1920x1080 ~/Pictures/*.jpg         # 1080p screens (uses more memory: 4 MB vs 1.8 MB)
#
# Uses sips on a Mac, ImageMagick (magick or convert) elsewhere. Keep 3 to 8 photos: each adds ~200 KB to the APK.
set -euo pipefail
cd "$(dirname "$0")/.."

W=1280; H=720
if [ "${1:-}" = "--size" ]; then
  [[ "${2:-}" =~ ^([0-9]+)x([0-9]+)$ ]] || { echo "--size needs WIDTHxHEIGHT, like 1920x1080" >&2; exit 1; }
  W="${BASH_REMATCH[1]}"; H="${BASH_REMATCH[2]}"; shift 2
fi
[ $# -gt 0 ] || { sed -n '2,8p' "$0"; exit 1; }

OUT=app/assets/wallpapers
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if command -v sips >/dev/null; then TOOL=sips
elif command -v magick >/dev/null; then TOOL=magick
elif command -v convert >/dev/null; then TOOL=convert
else echo "Needs sips (macOS) or ImageMagick." >&2; exit 1; fi

i=1
for f in "$@"; do
  [ -f "$f" ] || { echo "skipped (not a file): $f" >&2; continue; }
  out="$TMP/wall$i.jpg"
  if [ "$TOOL" = sips ]; then
    read -r sw sh < <(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')
    # Scale so both sides cover the target, then crop the middle.
    if [ $((sw * H)) -ge $((sh * W)) ]; then sips -s format jpeg --resampleHeight "$H" "$f" --out "$TMP/s.jpg" >/dev/null
    else sips -s format jpeg --resampleWidth "$W" "$f" --out "$TMP/s.jpg" >/dev/null; fi
    sips -s format jpeg -s formatOptions 82 --cropToHeightWidth "$H" "$W" "$TMP/s.jpg" --out "$out" >/dev/null
  else
    "$TOOL" "$f" -auto-orient -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" -quality 82 "$out"
  fi
  echo "wall$i.jpg  ← $(basename "$f")"
  i=$((i + 1))
done
[ "$i" -gt 1 ] || { echo "No photos converted; $OUT left as it was." >&2; exit 1; }

rm -f "$OUT"/*.jpg
mkdir -p "$OUT"
mv "$TMP"/wall*.jpg "$OUT/"
echo "$((i - 1)) wallpapers in $OUT ($(du -sh "$OUT" | cut -f1)). Now run ./build.sh and install the APK."
