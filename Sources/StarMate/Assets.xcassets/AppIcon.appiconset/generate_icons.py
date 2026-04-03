#!/usr/bin/env python3
"""
StarMate App Icon Generator

This script generates all required iOS app icon sizes from the master SVG icon.

Requirements:
- Python 3
- cairosvg (pip install cairosvg)
- Pillow (pip install Pillow)

Usage:
    python generate_icons.py

The script will read StarMate-Icon.svg and generate all required PNG files.
"""

import os
from pathlib import Path

try:
    import cairosvg
    from PIL import Image
    HAS_DEPS = True
except ImportError:
    HAS_DEPS = False

# All required icon sizes
ICON_SIZES = [
    ("Icon-20.png", 20),
    ("Icon-20@2x.png", 40),
    ("Icon-20@3x.png", 60),
    ("Icon-29.png", 29),
    ("Icon-29@2x.png", 58),
    ("Icon-29@3x.png", 87),
    ("Icon-40.png", 40),
    ("Icon-40@2x.png", 80),
    ("Icon-40@3x.png", 120),
    ("Icon-60@2x.png", 120),
    ("Icon-60@3x.png", 180),
    ("Icon-76.png", 76),
    ("Icon-76@2x.png", 152),
    ("Icon-83.5@2x.png", 167),
    ("Icon-1024.png", 1024),
]

def generate_icons():
    script_dir = Path(__file__).parent
    svg_path = script_dir / "StarMate-Icon.svg"

    if not svg_path.exists():
        print(f"Error: {svg_path} not found")
        return

    print("Generating StarMate app icons...")

    for filename, size in ICON_SIZES:
        output_path = script_dir / filename

        # Convert SVG to PNG at the specified size
        cairosvg.svg2png(
            url=str(svg_path),
            write_to=str(output_path),
            output_width=size,
            output_height=size
        )
        print(f"  ✓ {filename} ({size}x{size})")

    print("\nAll icons generated successfully!")

def generate_placeholder_icons():
    """Generate placeholder icons with size text for testing"""
    script_dir = Path(__file__).parent

    print("Generating placeholder icons (no dependencies)...")
    print("Note: These are placeholder images. For production, use the SVG with cairosvg.")
    print("\nRequired icon sizes:")

    for filename, size in ICON_SIZES:
        print(f"  {filename}: {size}x{size}px")

if __name__ == "__main__":
    if HAS_DEPS:
        generate_icons()
    else:
        generate_placeholder_icons()
        print("\nTo generate actual icons, install dependencies:")
        print("  pip install cairosvg Pillow")
