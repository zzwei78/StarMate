# StarMate App Icon Assets

This folder contains the app icon assets for the StarMate iOS application.

## Files

- `StarMate-Icon.svg` - Master SVG icon (scalable)
- `Contents.json` - Xcode asset catalog configuration
- `generate_icons.sh` - Shell script to generate PNG icons (requires ImageMagick or librsvg)
- `generate_icons.py` - Python script to generate PNG icons (requires cairosvg and Pillow)

## Required Icon Sizes

| Filename | Size | Device/Usage |
|----------|------|--------------|
| Icon-20.png | 20x20 | iPad Notification |
| Icon-20@2x.png | 40x40 | iPhone/iPad Notification |
| Icon-20@3x.png | 60x60 | iPhone Notification |
| Icon-29.png | 29x29 | iPad Settings |
| Icon-29@2x.png | 58x58 | iPhone/iPad Settings |
| Icon-29@3x.png | 87x87 | iPhone Settings |
| Icon-40.png | 40x40 | iPad Spotlight |
| Icon-40@2x.png | 80x80 | iPhone/iPad Spotlight |
| Icon-40@3x.png | 120x120 | iPhone Spotlight |
| Icon-60@2x.png | 120x120 | iPhone App |
| Icon-60@3x.png | 180x180 | iPhone App |
| Icon-76.png | 76x76 | iPad App |
| Icon-76@2x.png | 152x152 | iPad App |
| Icon-83.5@2x.png | 167x167 | iPad Pro App |
| Icon-1024.png | 1024x1024 | App Store |

## Generating Icons

### Option 1: Using the shell script (macOS/Linux)

```bash
# Install dependencies
brew install librsvg

# Run the script
cd Assets.xcassets/AppIcon.appiconset
chmod +x generate_icons.sh
./generate_icons.sh
```

### Option 2: Using Python

```bash
# Install dependencies
pip install cairosvg Pillow

# Run the script
cd Assets.xcassets/AppIcon.appiconset
python generate_icons.py
```

### Option 3: Using Xcode

1. Open `StarMate-Icon.svg` in Xcode
2. For each size in the table above:
   - Select the SVG
   - Choose File > Export
   - Set the export size
   - Save with the appropriate filename

### Option 4: Using SwiftUI (In-App)

1. Open the project in Xcode
2. Run the app in the simulator
3. Navigate to `IconGeneratorScreen` view
4. Take screenshots of each icon size
5. Use Xcode's asset catalog to add the images

## Icon Design

The StarMate icon features:
- **Background**: Blue gradient (#007AFF to #0055CC)
- **Main Element**: Satellite dish pointing upward
- **Accent**: Signal waves emanating from the dish
- **Decoration**: Gold stars representing satellite/space theme

## Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| Primary Blue | #007AFF | Background gradient start |
| Dark Blue | #0055CC | Background gradient end |
| White | #FFFFFF | Satellite dish |
| Light Gray | #E0E0E0 | Dish shading |
| Gold | #FFD700 | Star accents |
| Dark Gray | #333333 | LNB element |
