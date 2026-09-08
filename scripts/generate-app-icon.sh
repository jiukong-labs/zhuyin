#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
assets="$repository_root/Resources/Assets"
source_image="$assets/JiukongZhuyin.png"
temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT
iconset="$temporary_root/JiukongZhuyin.iconset"
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_image" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$source_image" \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$iconset" -o "$assets/JiukongZhuyin.icns"
sips -z 128 128 -s format tiff "$source_image" \
    --out "$assets/JiukongZhuyin.tiff" >/dev/null
