// Renders the app icon's three appearances and the keyboard's grey mark from
// render.html (Playwright's Chromium): node render.cjs
const { chromium } = require('playwright');
const { writeFileSync } = require('node:fs');
const path = require('node:path');

(async () => {
const here = __dirname;
const ios = path.join(here, '../../ios');
const page = await (await chromium.launch()).newPage();
async function save(query, file) {
  await page.goto('file://' + path.join(here, 'render.html') + '?' + query);
  const data = await page.evaluate(() => document.getElementById('out').toDataURL('image/png'));
  writeFileSync(file, Buffer.from(data.split(',')[1], 'base64'));
  console.log(file);
}
const icons = path.join(ios, 'Astrotype/Assets.xcassets/AppIcon.appiconset');
await save('v=light', path.join(icons, 'AppIcon.png'));
await save('v=dark', path.join(icons, 'AppIcon-Dark.png'));
await save('v=tinted', path.join(icons, 'AppIcon-Tinted.png'));
const mark = path.join(ios, 'AstrotypeKit/Sources/AstrotypeUI/Media.xcassets/AstrotypeMark.imageset');
for (const s of [1, 2, 3]) await save(`v=mark&w=30&s=${s}`, path.join(mark, `AstrotypeMark${s > 1 ? '@' + s + 'x' : ''}.png`));
process.exit(0);
})();
