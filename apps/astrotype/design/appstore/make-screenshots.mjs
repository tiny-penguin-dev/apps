// Makes App Store screenshots from the design mockup (design/mockups/astrotype.html):
// a phone screen under a caption, at the 6.9" iPhone size (1320 x 2868), written to
// store/screenshots/en-US/, which CI uploads to App Store Connect (app-store.yml). Also
// the App Review screenshot for the Pro plans, store/pro-review.png (the Pro screen
// alone, 1170 x 2532), which subscriptions.json points at.
//
//   node apps/astrotype/design/appstore/make-screenshots.mjs
//
// Needs Playwright (preinstalled in Claude's container) and the network, for the
// mockup's Nunito. Replace with real screenshots once the app is close to release;
// the captions and order stay.
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";
const { chromium } = createRequire(import.meta.url)("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const mockup = pathToFileURL(path.join(here, "../mockups/astrotype.html")).href;
const palette = { glacier: "#F3F8FA", ice: "#D9EDF3", coral: "#FFE1E7", sun: "#FFEFC9", mint: "#CFF2E8", deep: "#111A24", water: "#1A2634" };

// Screen in the mockup, caption, smaller line, page colours; `setup` runs in the mockup
// before the screen is drawn, `wait` lets an animation (the Try it replay) draw first.
const shots = [
  { file: "1-messages", screen: "messages", title: "Both thumbs, one word",
    sub: "Tap and swipe with both thumbs at once. Astrotype puts the pieces together.", bg: [palette.ice, palette.glacier] },
  { file: "2-try", screen: "try", title: "Learn it in five words",
    sub: "A short tour shows what each thumb does. Then it's yours.", bg: [palette.coral, palette.glacier], wait: 2200, motion: true },
  { file: "3-result", screen: "result", title: "Race Apple's keyboard",
    sub: "Three sentences, your words per minute, your best and your streak.", bg: [palette.sun, palette.glacier] },
  { file: "4-drill", screen: "drill", title: "Drills for your thumbs",
    sub: "Keys light up in each thumb's colour until the moves are yours.", bg: [palette.ice, palette.glacier] },
  { file: "5-home", screen: "home", title: "Your words, your pace",
    sub: "A speed test, drills and a week of practice on one page.", bg: [palette.mint, palette.glacier], setup: "S.on=true" },
  { file: "6-dark", screen: "messages", title: "At home in every app",
    sub: "Light or dark, it follows the app you're in. Nothing you type leaves your phone.", bg: [palette.deep, palette.water], dark: true },
];

const browser = await chromium.launch();
const out = path.join(here, "../../store/screenshots/en-US");

// 1. The phone screen alone, at 3x (390 x 844 points).
async function phoneShot(shot) {
  const page = await browser.newPage({ viewport: { width: 900, height: 1000 }, deviceScaleFactor: 3,
    colorScheme: shot.dark ? "dark" : "light", reducedMotion: shot.motion ? "no-preference" : "reduce" });
  // Same confetti every run, so an unchanged screenshot keeps the same bytes and CI
  // doesn't upload it again.
  await page.addInitScript(() => { let seed = 7; Math.random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647); });
  await page.goto(mockup + "#welcome");
  await page.waitForLoadState("networkidle");
  await page.evaluate(({ setup, screen, dark }) => {
    if (dark) document.documentElement.setAttribute("data-theme", "dark");
    if (setup) eval(setup);
    go(screen);
  }, { setup: shot.setup, screen: shot.screen, dark: shot.dark });
  await page.addStyleTag({ content: ".phone{border-radius:0!important;box-shadow:none!important;height:844px!important} .screen{animation:none!important} .fish{display:none!important}" });
  await page.waitForTimeout(shot.wait ?? 300);
  const png = await page.locator("#phone").screenshot({ animations: shot.motion ? "allow" : "disabled" });
  await page.close();
  return png;
}

// 2. The App Store frame: caption on top, phone below. 440 x 956 points at 3x = 1320 x 2868.
for (const shot of shots) {
  const img = (await phoneShot(shot)).toString("base64");
  const page = await browser.newPage({ viewport: { width: 440, height: 956 }, deviceScaleFactor: 3 });
  const ink = shot.dark ? "#EEF4F8" : "#1E2945";
  const muted = shot.dark ? "#97A6B8" : "#67748F";
  await page.setContent(`<!doctype html><html><head>
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Nunito:wght@700;900&display=swap">
    <style>
    *{margin:0;box-sizing:border-box}
    body{width:440px;height:956px;overflow:hidden;background:linear-gradient(180deg,${shot.bg[0]},${shot.bg[1]} 70%);
      font-family:"SF Pro Rounded",ui-rounded,"Nunito","Arial Rounded MT Bold",system-ui,sans-serif;color:${ink};
      display:flex;flex-direction:column;align-items:center}
    header{min-height:200px;padding:62px 0 28px}
    h1{font-size:36px;font-weight:900;letter-spacing:-.5px;text-align:center;line-height:1.05;padding:0 24px}
    p{margin-top:12px;font-size:18px;font-weight:700;color:${muted};text-align:center;padding:0 40px;line-height:1.3}
    .device{width:360px;padding:9px;border-radius:58px;background:#1E2945;box-shadow:0 30px 60px rgba(30,41,69,.25)}
    .device img{display:block;width:342px;border-radius:49px}
  </style></head><body>
    <header><h1>${shot.title}</h1><p>${shot.sub}</p></header>
    <div class="device"><img src="data:image/png;base64,${img}"></div>
  </body></html>`);
  await page.waitForLoadState("networkidle");
  await page.waitForTimeout(150);
  await page.screenshot({ path: path.join(out, shot.file + ".png") });
  await page.close();
  console.log("wrote", shot.file + ".png");
}

// 3. The Pro screen alone, for App Review's look at the subscriptions.
const pro = await phoneShot({ screen: "pro" });
const { writeFileSync } = await import("node:fs");
writeFileSync(path.join(here, "../../store/pro-review.png"), pro);
console.log("wrote pro-review.png");
await browser.close();
