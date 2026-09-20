#!/usr/bin/env node
// Deterministic full-page screenshots of the landing page for PR evidence.
//
//   node scripts/capture.mjs --url http://localhost:3000 --out ../evidence/website --label before
//
// Captures three viewports (mobile 390×844, laptop 1440×900, wide 1920×1080)
// with scroll-reveal forced visible, CSS animations frozen and web fonts
// awaited, so two runs of the same commit produce identical PNGs. Uses the
// Playwright Chromium already installed for the repo's tooling; run
// `npx playwright install chromium` once if it is missing, or pass
// `--channel chrome` to use the installed Google Chrome instead.

import { chromium } from "playwright";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";

const args = Object.fromEntries(
  process.argv
    .slice(2)
    .map((a, i, all) => (a.startsWith("--") ? [a.slice(2), all[i + 1] ?? ""] : null))
    .filter(Boolean),
);
const url = args.url ?? "http://localhost:3000";
const out = resolve(args.out ?? "evidence");
const label = args.label ?? "site";
const only = args.viewports ? args.viewports.split(",") : null;

const VIEWPORTS = {
  mobile: { width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true },
  laptop: { width: 1440, height: 900, deviceScaleFactor: 1 },
  wide: { width: 1920, height: 1080, deviceScaleFactor: 1 },
};

mkdirSync(out, { recursive: true });
// Prefer Playwright's pinned Chromium; fall back to the installed Google
// Chrome (`--channel chrome`) so the script works without a browser download.
const browser = await chromium.launch({ channel: args.channel }).catch((error) => {
  if (args.channel) throw error;
  console.error("Playwright Chromium not installed; falling back to Google Chrome");
  return chromium.launch({ channel: "chrome" });
});
try {
  for (const [name, vp] of Object.entries(VIEWPORTS)) {
    if (only && !only.includes(name)) continue;
    const context = await browser.newContext({
      viewport: { width: vp.width, height: vp.height },
      deviceScaleFactor: vp.deviceScaleFactor,
      isMobile: vp.isMobile ?? false,
      hasTouch: vp.hasTouch ?? false,
      colorScheme: "dark",
      reducedMotion: "reduce",
      timezoneId: "UTC",
      locale: "en-US",
    });
    const page = await context.newPage();
    await page.addStyleTag({
      content: `
        *, *::before, *::after { animation: none !important; transition: none !important; }
        .reveal { opacity: 1 !important; transform: none !important; }
        html { scroll-behavior: auto !important; }
      `,
    }).catch(() => {});
    await page.goto(url, { waitUntil: "networkidle" });
    await page.addStyleTag({
      content: `
        *, *::before, *::after { animation: none !important; transition: none !important; }
        .reveal { opacity: 1 !important; transform: none !important; }
      `,
    });
    await page.evaluate(() => document.fonts.ready);
    // Walk the page so lazy images and IntersectionObservers have fired.
    await page.evaluate(async () => {
      const step = window.innerHeight / 2;
      for (let y = 0; y < document.body.scrollHeight; y += step) {
        window.scrollTo(0, y);
        await new Promise((r) => setTimeout(r, 40));
      }
      window.scrollTo(0, 0);
    });
    await page.waitForTimeout(250);

    const first = `${out}/${label}-${name}-01-first-viewport.png`;
    await page.screenshot({ path: first, fullPage: false });
    const full = `${out}/${label}-${name}-02-full-page.png`;
    await page.screenshot({ path: full, fullPage: true });
    console.log(`${name}\t${vp.width}×${vp.height}\t${first}\n${name}\t${vp.width}×${vp.height}\t${full}`);
    await context.close();
  }
} finally {
  await browser.close();
}
