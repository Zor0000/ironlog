import { test } from "@e2e-dev/web";
import { expect } from "e2e";

test.beforeEach(async ({ app, screen }) => {
  await app.open();
  await expect(screen.getByRole("heading", { level: 1 })).toBeVisible();
});

test("navigation links reach each advertised product section", async ({ screen, browser }) => {
  for (const [label, hash] of [["Features", "features"], ["Screens", "screens"], ["Live Activity", "live-activity"]]) {
    await screen.getByRole("link", label).first().tap();
    await expect(browser).toHaveURL(new RegExp(`#${hash}$`));
    await expect(browser.locator(`#${hash}`)).toBeVisible();
  }
  await screen.getByRole("link", "Setzo home").tap();
  await expect(browser).toHaveURL(/#top$/);
});

test("screenshots load as actual images with accessible descriptions", async ({ browser }) => {
  const images = browser.locator('img[alt*="Setzo"]');
  await expect(images).toHaveCount(5);
  await expect.poll(() => browser.evaluate(() => [...document.querySelectorAll('img[alt*="Setzo"]')].every(image => image instanceof HTMLImageElement && image.complete && image.naturalWidth > 0))).toBe(true);
});

test("source, support, and privacy links have real destinations and safe external targets", async ({ screen, browser }) => {
  await expect(screen.getByRole("link", "View source")).toHaveAttribute("href", "https://github.com/Zor0000/setzo");
  await expect(screen.getByRole("link", "Support")).toHaveAttribute("href", "https://www.neeraj.works/setzo/support.html");
  await expect(screen.getByRole("link", "Privacy")).toHaveAttribute("href", "https://www.neeraj.works/setzo/privacy.html");
  expect(await browser.evaluate(() => [...document.querySelectorAll('a[target="_blank"]')].every(link => link.getAttribute('rel')?.includes('noreferrer')))).toBe(true);
});

test("compact screens retain readable navigation and have no horizontal page overflow", async ({ app, screen, browser }) => {
  for (const width of [320, 375, 768]) {
    await browser.setViewport({ width, height: 812 });
    await expect(screen.getByRole("link", "Setzo home")).toBeVisible();
    const download = screen.getByRole("button", "Download on the App Store — coming soon");
    await expect(download.first()).toBeVisible();
    await expect(download.first()).toHaveAttribute("disabled", "");
    expect(await browser.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBe(0);
    await expect(screen.getByRole("link", "View source")).toBeVisible();
    expect(await browser.evaluate(() => {
      const section = document.querySelector('#get');
      section?.scrollIntoView();
      return section !== null;
    })).toBe(true);
    await expect(browser.locator('#get button')).toBeVisible();
    await expect(browser.locator('#get button')).toHaveAttribute("disabled", "");
  }
  await app.screenshot("compact-get-setzo");
});

test("the accessible document has one main and one top-level heading", async ({ screen, browser }) => {
  await expect(screen.getByRole("main")).toHaveCount(1);
  await expect(screen.getByRole("heading", { level: 1 })).toHaveCount(1);
  expect(await browser.evaluate(() => [...document.querySelectorAll('img')].every(image => image.hasAttribute('alt')))).toBe(true);
  expect(await browser.evaluate(() => document.documentElement.lang)).toBe("en");
});

test("an unknown route returns 404 and browser back recovers the landing page", async ({ app, screen, browser }) => {
  const response = await fetch(new URL("/not-a-setzo-route", app.baseUrl));
  expect(response.status).toBe(404);
  await browser.goto("/not-a-setzo-route");
  await expect(screen.getByRole("heading", "404")).toBeVisible();
  await browser.back();
  await expect(screen.getByRole("heading", { level: 1 })).toBeVisible();
});

test("platform and privacy claims match the shipped native app", async ({ screen, browser }) => {
  await expect(screen.getByText("Coming soon to the App Store · free & open source")).toBeVisible();
  expect(await browser.evaluate(() => document.body.textContent)).not.toMatch(/web PWA|No third-party SDKs/i);
  await expect(screen.getByRole("button", "Download on the App Store — coming soon")).toHaveCount(3);
  expect(await browser.evaluate(() => [...document.querySelectorAll('button')].every(button => button.disabled))).toBe(true);
  await expect(browser.locator('#live-activity button')).toHaveCount(0);
});
