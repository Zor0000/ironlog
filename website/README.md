# IronLog — Demo Website

A single-page marketing site for **IronLog**, built with Next.js 16, React 19 and
Tailwind v4. Dark + lime aesthetic that mirrors the app (`IronLog/Theme.swift`).

## Run it

```bash
cd website
npm install
npm run dev      # http://localhost:3001  (see ../.claude/launch.json)
npm run build    # production build
```

## What's inside

- `src/app/page.tsx` — assembles the page.
- `src/components/` — `Nav`, `Hero`, `Showcase`, `Features`, `LiveActivity`,
  `Why`, `CTA`, `Footer`, plus reusable `PhoneFrame` (CSS device bezel) and
  `Reveal` (scroll-in animation).
- `src/lib/site.ts` — copy, links and the screenshot deck.
- `public/screenshots/` — real iOS screenshots captured from the app on the
  iPhone 17 Pro simulator (seeded demo data). The `Showcase` section renders them
  in device frames as App Store–style slides; the `LiveActivity` section is a
  faithful CSS recreation of `IronLogWidget/WorkoutLiveActivity.swift`.

## Where the screenshots come from

Raw screenshots were captured from the native app using a DEBUG-only seed
(`AppState.applyDemoSeedIfRequested`, gated behind launch args), e.g.:

```bash
xcrun simctl launch booted com.parthjadhav.ironlog -seedDemo YES -seedActive YES -seedTab log
xcrun simctl io booted screenshot 02-log.png
```

App Store / Google Play framed exports can be produced from the sibling
`../screenshot-studio` project (scaffolded with the
[`app-store-screenshots`](https://github.com/ParthJadhav/app-store-screenshots)
skill and pre-filled with IronLog content): run `npm run dev` there and click
**Export bundle** in a desktop browser.

## Deploy

Vercel-ready. `vercel` (or import the repo) and set the project root to `website/`.
