// Makes mock App Store screenshots from the design mockup (design/mockups/squawk.html).
// Each one is a phone screen with a caption, at the 6.9" iPhone size (1320 x 2868),
// written to store/screenshots/en-US/, which CI uploads to App Store Connect.
//
//   node apps/squawk/design/appstore/make-screenshots.mjs
//
// Needs Playwright (preinstalled in Claude's container). Replace with real app
// screenshots once the app is close to release.
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";
const { chromium } = createRequire(import.meta.url)("playwright");

const here = path.dirname(fileURLToPath(import.meta.url));
const mockup = pathToFileURL(path.join(here, "../mockups/squawk.html")).href;

// Screen in the mockup, caption, smaller line, page colors, and optional code run in the
// mockup before (setup) and after (tweak) the screen is drawn.
const shots = [
  { file: "1-home", screen: "home", title: "Rise and waddle", sub: "A cute alarm that's on your side", bg: ["#FFD9C2", "#F4F7FF"] },
  { file: "2-rings", screen: "edit", title: "Soft first, loud later", sub: "Add a gentle ring before and a loud one after", bg: ["#FFE7A8", "#F4F7FF"],
    setup: "S.rings.push(RING_SOFT, RING_LOUD)" },
  { file: "3-days", screen: "home", title: "Fridays can be later", sub: "One alarm, different times on different days", bg: ["#CDEFE3", "#F4F7FF"], dark: true },
  { file: "4-check", screen: "check", title: "Prove you're up", sub: "Scan a tag in another room to stop snoozing", bg: ["#FFC9CB", "#F4F7FF"],
    tweak: `document.querySelector('[data-act=scanned]').textContent = "Scan my tag"` },
  { file: "5-game", screen: "game", title: "Count the penguins", sub: "A quick game to get your brain going", bg: ["#DCE7FF", "#F4F7FF"] },
  { file: "6-morning", screen: "morning", title: "Good mornings win", sub: "Keep a streak and earn outfits for Squawk", bg: ["#FFD9C2", "#FFF4D6"],
    tweak: `document.querySelector('.screen .sub').innerHTML = "Up at 7:00, on the first ring.<br>Squawk is so proud.";
      const t = document.querySelectorAll('.week i')[3]; t.className = "y"; t.textContent = "✓";` },
];

const browser = await chromium.launch();
const out = path.join(here, "../../store/screenshots/en-US");

// 1. The phone screen alone, at 3x.
async function phoneShot(shot) {
  const page = await browser.newPage({ viewport: { width: 900, height: 1000 }, deviceScaleFactor: 3,
    colorScheme: shot.dark ? "dark" : "light", reducedMotion: shot.screen === "morning" ? "no-preference" : "reduce" });
  // Same confetti every run, so an unchanged screenshot keeps the same bytes and CI
  // doesn't upload it again.
  await page.addInitScript(() => { let seed = 7; Math.random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647); });
  await page.goto(mockup + "#welcome");
  await page.evaluate(({ setup, screen, tweak }) => { if (setup) eval(setup); go(screen); if (tweak) eval(tweak); },
    { setup: shot.setup, screen: shot.screen, tweak: shot.tweak });
  await page.addStyleTag({ content: ".phone{border-radius:0!important;box-shadow:none!important;height:844px!important} .screen{animation:none!important}" });
  await page.waitForTimeout(shot.screen === "morning" ? 900 : 300);
  const png = await page.locator("#phone").screenshot({ animations: shot.screen === "morning" ? "allow" : "disabled" });
  await page.close();
  return png.toString("base64");
}

// 2. The App Store frame: caption on top, phone below. 440 x 956 points at 3x = 1320 x 2868.
for (const shot of shots) {
  const img = await phoneShot(shot);
  const page = await browser.newPage({ viewport: { width: 440, height: 956 }, deviceScaleFactor: 3 });
  await page.setContent(`<!doctype html><html><head><style>
    *{margin:0;box-sizing:border-box}
    body{width:440px;height:956px;overflow:hidden;background:linear-gradient(180deg,${shot.bg[0]},${shot.bg[1]} 70%);
      font-family:"SF Pro Rounded",ui-rounded,"Nunito","Arial Rounded MT Bold",system-ui,sans-serif;color:#1E2945;
      display:flex;flex-direction:column;align-items:center}
    header{height:200px;padding-top:62px}
    h1{font-size:38px;font-weight:900;letter-spacing:-.5px;text-align:center;line-height:1.05;padding:0 24px}
    p{margin-top:12px;font-size:18px;font-weight:700;color:#5A6683;text-align:center;padding:0 40px;line-height:1.3}
    .device{width:360px;padding:9px;border-radius:58px;background:#172239;
      box-shadow:0 30px 60px rgba(23,34,57,.25)}
    .device img{display:block;width:342px;border-radius:49px}
  </style></head><body>
    <header><h1>${shot.title}</h1><p>${shot.sub}</p></header>
    <div class="device"><img src="data:image/png;base64,${img}"></div>
  </body></html>`);
  await page.waitForTimeout(150);
  await page.screenshot({ path: path.join(out, shot.file + ".png") });
  await page.close();
  console.log("wrote", shot.file + ".png");
}
await browser.close();
