#!/bin/bash
# StarMate App Icon Generator
#
# This script generates all required iOS app icon sizes.
#
# Prerequisites (choose one):
#   1. ImageMagick + librsvg: brew install imagemagick librsvg
#   2. rsvg-convert: brew install librsvg
#   3. Use Xcode: Open the SVG in Xcode and export at each size
#
# Usage:
#   ./generate_icons.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG_FILE="$SCRIPT_DIR/StarMate-Icon.svg"

# Required icon sizes (filename, size)
ICONS=(
    "Icon-20.png:20"
    "Icon-29.png:29"
    "Icon-40.png:40"
    "Icon-60@2x.png:120"
    "Icon-76.png:76"
    "Icon-20@2x.png:40"
    "Icon-29@2x.png:58"
    "Icon-40@2x.png:80"
    "Icon-60@3x.png:180"
    "Icon-76@2x.png:152"
    "Icon-20@3x.png:60"
    "Icon-29@3x.png:87"
    "Icon-40@3x.png:120"
    "Icon-83.5@2x.png:167"
    "Icon-1024.png:1024"
)

# Check for conversion tool
if command -v rsvg-convert &> /dev/null; then
    CONVERTER="rsvg-convert"
elif command -v convert &> /dev/null; then
    CONVERTER="imagemagick"
else
    echo "Error: No image converter found."
    echo ""
    echo "Install one of the following:"
    echo "  brew install librsvg        # for rsvg-convert"
    echo "  brew install imagemagick    # for convert"
    echo ""
    echo "Alternative: Open StarMate-Icon.svg in Xcode and export at each size."
    exit 1
fi

echo "Generating StarMate app icons using $CONVERTER..."
echo ""

for ICON in "${ICONS[@]}"; do
    FILENAME="${ICON%%:*}"
    SIZE="${ICON##*:}"

    OUTPUT="$SCRIPT_DIR/$FILENAME"

    if [ "$CONVERTER" = "rsvg-convert" ]; then
        rsvg-convert -w "$SIZE" -h "$SIZE" "$SVG_FILE" -o "$OUTPUT"
    else
        convert -background none -resize "${SIZE}x${SIZE}" "$SVG_FILE" "$OUTPUT"
    fi

    echo "✓ $FILENAME ($SIZE x $SIZE)"
done

echo ""
echo "All icons generated successfully!"
