# The app icon and the keyboard's mark

`render.html` draws the app icon's three appearances (light, dark and tinted) and the
grey Astrotype mark the keyboard shows in its top bar. They are drawn on a canvas so each
orbit can be a trail that fades back round to its dot (Gabriel, 9 Nov 2026): solid in
front of the key and fading behind it in the icon, fading all the way round in the mark.
Open it in a browser to see all four.

To regenerate the images, run `node render.cjs` here (it uses Playwright's Chromium),
then flatten the light and dark icons to RGB and turn the tinted one grey while keeping
its alpha:

```
python3 -c "from PIL import Image as I; d='../../ios/Astrotype/Assets.xcassets/AppIcon.appiconset/'
[I.open(d+f).convert('RGB').save(d+f) for f in ('AppIcon.png','AppIcon-Dark.png')]
t=I.open(d+'AppIcon-Tinted.png').convert('RGBA'); I.merge('LA',(t.convert('L'),t.getchannel('A'))).convert('RGBA').save(d+'AppIcon-Tinted.png')"
```

It writes:

- `ios/Astrotype/Assets.xcassets/AppIcon.appiconset/AppIcon*.png`: one 1024 px image
  per appearance, as Xcode wants. Light is opaque, dark is opaque on deep navy, and
  tinted is grey on a transparent background (iOS tints it with the person's colour).
- `ios/AstrotypeKit/Sources/AstrotypeUI/Media.xcassets/AstrotypeMark.imageset`: the mark,
  30 pt wide at 1x, 2x and 3x, black on clear; the keyboard uses it as a template image
  (`AstrotypeMark`).

The colours are the thumb colours and navy from `DESIGN.md`.
