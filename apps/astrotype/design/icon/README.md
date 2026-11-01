# The app icon

`icon.svg`, `icon-dark.svg` and `icon-tinted.svg` are the sources of the three
appearances in `ios/Astrotype/Assets.xcassets/AppIcon.appiconset`. One 1024 pt image
per appearance, as Xcode 16 wants: light is opaque, dark is opaque on deep navy, and
tinted is grayscale on a transparent background (iOS tints it with the user's color).

To regenerate the PNGs, render each SVG at 1024 by 1024 (any browser or `rsvg-convert`
will do), then flatten light and dark to RGB and convert tinted to grayscale while
keeping its alpha. The colors are the thumb colors and navy from `DESIGN.md`.
