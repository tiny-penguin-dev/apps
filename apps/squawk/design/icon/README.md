# Squawk app icons

`make-icons.js` draws the standard icon and the Pro icons (Night, Mint, Ice) as SVG and renders
them to 1024 px PNGs with Playwright, plus `all.png`, a side-by-side preview at home screen sizes.

```bash
mkdir -p out && node make-icons.js
```

Then copy `out/<name>.png` into `ios/Squawk/Assets.xcassets/<name>.appiconset/` (as RGB, no alpha)
and a 180 px copy into the matching `IconPreview-*.imageset`.
