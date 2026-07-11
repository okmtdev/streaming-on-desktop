#!/bin/bash
# Icon/icon.png (1024x1024) から AppIcon.icns を生成する（macOS 専用: sips / iconutil）。
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Icon/icon.png"
ICONSET="Icon/AppIcon.iconset"

if [ ! -f "$SRC" ]; then
    echo "$SRC が見つかりません。1024x1024 の PNG を置いてください。" >&2
    echo "（プレースホルダーなら: python3 Icon/generate_icon.py）" >&2
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Icon/AppIcon.icns
rm -rf "$ICONSET"
echo "wrote Icon/AppIcon.icns"
