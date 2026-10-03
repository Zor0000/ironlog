import { test, type Device } from "@e2e-dev/mobile";
import { expect, type Locator, type Screen } from "e2e";

const bundle = "com.parthjadhav.ironlog";

// SwiftUI's TabView exposes an outer collection view before the actual vertical
// ScrollView. Scroll at the content edge so focused numeric/multiline fields do
// not capture the pan; bounded gestures still require the real target to appear.
async function reveal(screen: Screen, target: Locator, options: { direction?: "up" | "down" } = {}) {
  for (let attempt = 0; attempt < 8; attempt++) {
    if (await target.isVisible()) return;
    const up = options.direction === "up";
    await screen.swipe({ from: { x: 24, y: up ? 240 : 550 }, to: { x: 24, y: up ? 550 : 240 } });
  }
  await expect(target).toBeVisible();
}

async function replaceNumber(screen: Screen, device: Device, input: Locator, value: string) {
  await input.tap();
  await expect(screen.getByRole("button", "Done", { exact: true })).toBeVisible();
  // Numeric values are one word; double-tap selection and actual soft keys
  // avoid the driver's caret-based fill replacement on a centered input.
  await input.doubleTap();
  for (const digit of value) await device.locator(`role=Key label="${digit}"`).tap();
  await expect(input).toHaveValue(value);
}

async function customExercise(screen: Screen, name: string) {
  await screen.getByTestId("main-tab-today").tap();
  await screen.getByTestId("start-free-workout-button").tap();
  await screen.getByTestId("add-exercise-mode-custom").tap();
  await screen.getByTestId("new-exercise-name-field").fill(name);
  // The app supplies a Done key which commits this custom exercise.
  await screen.getByTestId("Done").tap();
  await expect(screen.getByTestId("set-reps-input").first()).toBeVisible();
}

test.beforeEach(async ({ device, app }) => {
  await device.installApp();
  await app.open();
});

test("a completed custom workout survives relaunch and history editing", async ({ screen, device, app }) => {
  await customExercise(screen, "Army Push Ups");
  await screen.getByTestId("set-reps-input").first().fill("12");
  await screen.getByRole("button", "Done", { exact: true }).tap();
  await expect(screen.getByRole("button", "Done", { exact: true })).toHaveCount(0);
  await screen.getByTestId("set-done-button").first().tap();
  await reveal(screen, screen.getByTestId("finish-workout-button"));
  await screen.getByTestId("finish-workout-button").tap();
  await expect(screen.getByText("1 set · Free Workout · local")).toBeVisible();
  await device.openApp(bundle, { relaunch: true, launchArguments: ["UITest_Seed", "7"] });
  // ResetStore suppresses the first intro without marking it complete.
  // Complete the real guest onboarding on the first persistence relaunch.
  await screen.getByTestId("onboarding-skip-button").tap();
  await screen.getByTestId("main-tab-progress").tap();
  await screen.getByRole("tab", "History").tap();
  await screen.getByTestId("history-card-toggle").first().tap();
  await expect(screen.getByText("Army Push Ups")).toBeVisible();
  await screen.getByTestId("edit-session-button").first().tap();
  await replaceNumber(screen, device, screen.getByTestId("edit-reps-input").first(), "15");
  await screen.getByRole("button", "Done", { exact: true }).tap();
  await reveal(screen, screen.getByTestId("save-session-edits-button"));
  await screen.getByTestId("save-session-edits-button").tap();
  await expect(screen.getByText(/BW x 15/).first()).toBeVisible();
  await app.screenshot("saved-edited-workout");
});

test("draft exercises and reps survive app termination without creating history", async ({ screen, device }) => {
  await customExercise(screen, "Army Draft");
  await screen.getByTestId("set-reps-input").first().fill("9");
  await screen.getByRole("button", "Done", { exact: true }).tap();
  await device.openApp(bundle, { relaunch: true, launchArguments: ["UITest_Seed", "7"] });
  // ResetStore suppresses the first intro without marking it complete.
  // Complete the real guest onboarding on the first persistence relaunch.
  await screen.getByTestId("onboarding-skip-button").tap();
  await screen.getByTestId("main-tab-today").tap();
  await expect(screen.getByText("Army Draft")).toBeVisible();
  await expect(screen.getByTestId("set-reps-input").first()).toHaveValue("9");
  // Refresh the keyboard/focus state after relaunch while its field still exists.
  await screen.getByTestId("set-reps-input").first().tap();
  await screen.getByRole("button", "Done", { exact: true }).tap();
  await expect(screen.getByRole("button", "Done", { exact: true })).toHaveCount(0);
  await expect(screen.getByTestId("set-reps-input").first()).toHaveValue("9");
  await screen.getByRole("button", "Discard workout").tap();
  const discard = screen.getByRole("button", "Discard Workout", { exact: true });
  await expect(discard).toBeVisible();
  const box = await discard.boundingBox();
  if (!box) throw new Error("Discard confirmation has no tappable bounds");
  // This action immediately removes its XCUI element. Dispatch at freshly
  // observed bounds to avoid XCTest revalidating the vanished modal afterwards.
  await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
  await expect(screen.getByTestId("split-free-workout-button")).toBeVisible();
  await screen.getByTestId("main-tab-today").tap();
  await expect(screen.getByTestId("start-free-workout-button")).toBeVisible();
  await expect(screen.getByText("Army Draft")).toHaveCount(0);
});

test("set deletion protects entered work and cancelling exercise deletion preserves it", async ({ screen, device }) => {
  await customExercise(screen, "Army Safety");
  await screen.getByRole("button", "Add Set", { exact: true }).tap();
  await expect(screen.getByTestId("set-reps-input")).toHaveCount(2);
  await screen.getByTestId("remove-set-button").nth(1).tap();
  await expect(screen.getByTestId("set-reps-input")).toHaveCount(1);
  await screen.getByRole("button", "Add Set", { exact: true }).tap();
  await screen.getByTestId("set-reps-input").nth(1).fill("8");
  await screen.getByRole("button", "Done", { exact: true }).tap();
  await screen.getByTestId("remove-set-button").nth(1).tap();
  await expect(screen.getByText("Remove set?", { exact: true })).toBeVisible();
  await screen.getByRole("button", "Keep It").tap();
  await screen.getByTestId("remove-exercise-button").first().tap();
  await expect(screen.getByText("Remove exercise?", { exact: true })).toBeVisible();
  await screen.getByRole("button", "Keep It").tap();
  await expect(screen.getByTestId("set-reps-input").nth(1)).toHaveValue("8");
});

test("rest timer supports start pause and reset during a workout", async ({ screen }) => {
  await customExercise(screen, "Army Rest");
  await reveal(screen, screen.getByRole("button", "Start rest timer"), { direction: "up" });
  await screen.getByRole("button", "Start rest timer").tap();
  await expect(screen.getByRole("button", "Pause rest timer")).toBeVisible();
  await screen.getByRole("button", "Pause rest timer").tap();
  await expect(screen.getByRole("button", "Start rest timer")).toBeVisible();
  await screen.getByRole("button", "Reset rest timer").tap();
  await expect(screen.getByRole("button", "Start rest timer")).toBeVisible();
});

test("run validation rejects huge durations then saves a valid walk into history", async ({ screen, device }) => {
  await screen.getByTestId("main-tab-run").tap();
  await screen.getByTestId("run-minutes-field").fill("999999999999999");
  await screen.getByRole("button", "Done", { exact: true }).tap();
  await reveal(screen, screen.getByText("Enter 0.1–1,440 minutes."));
  await expect(screen.getByText("Enter 0.1–1,440 minutes.")).toBeVisible();
  await reveal(screen, screen.getByTestId("save-manual-cardio-button"));
  await expect(screen.getByTestId("save-manual-cardio-button")).toBeDisabled();
  await reveal(screen, screen.getByTestId("run-kind-walk"), { direction: "up" });
  await screen.getByTestId("run-kind-walk").tap();
  await screen.getByTestId("run-minutes-field").fill("30");
  await screen.getByRole("button", "Done", { exact: true }).tap();
  await reveal(screen, screen.getByTestId("run-distance-field"));
  await screen.getByTestId("run-distance-field").fill("2.5");
  await screen.getByRole("button", "Done", { exact: true }).tap();
  await reveal(screen, screen.getByTestId("save-manual-cardio-button"));
  await screen.getByTestId("save-manual-cardio-button").tap();
  await expect(screen.getByRole("button", /, Walk, expand$/)).toBeVisible();
  await expect(screen.getByText(/2\.50 km/)).toBeVisible();
});

test("body weight and unit preferences survive relaunch", async ({ screen, device }) => {
  await screen.getByTestId("settings-button").tap();
  await screen.getByRole("tab", "Kilograms (kg)").tap();
  await screen.getByTestId("body-weight-field").fill("70");
  await screen.getByRole("button", "Done", { exact: true }).tap();
  await screen.getByRole("tab", "Pounds (lb)").tap();
  await screen.getByRole("button", "Close settings").tap();
  await device.openApp(bundle, { relaunch: true, launchArguments: ["UITest_Seed", "7"] });
  // ResetStore suppresses the first intro without marking it complete.
  // Complete the real guest onboarding on the first persistence relaunch.
  await screen.getByTestId("onboarding-skip-button").tap();
  await screen.getByTestId("settings-button").tap();
  await expect(screen.getByTestId("body-weight-field")).toHaveValue("154.5");
  await expect(screen.getByText("Local — saved on this iPhone")).toBeVisible();
});

test("auth is age gated and exposes password reset without contacting providers", async ({ screen, device }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: ["UITest_ResetStore", "UITest_ShowAuth"] });
  await expect(screen.getByTestId("auth-privacy-link")).toBeVisible();
  await expect(screen.getByTestId("auth-terms-link")).toBeVisible();
  await expect(screen.getByTestId("google-sign-in-button")).toBeDisabled();
  await expect(screen.getByTestId("apple-sign-in-button")).toBeVisible();
  await screen.getByTestId("forgot-password-button").tap();
  await expect(screen.getByText("Reset password", { exact: true })).toBeVisible();
  await expect(screen.getByTestId("send-reset-link-button")).toBeVisible();
});

for (const [state, outcome] of [
  ["generated", "Paneer Bhurji with Toast"],
  ["offline", "You’re offline. Connect to generate AI meal suggestions."],
  ["error", "AI suggestions are unavailable. Please try again."],
  ["no-results", "No compatible result"],
] as const) {
  test(`IronFuel ${state} outcome is rendered through the actual submit flow`, async ({ screen, device, app }) => {
    await device.openApp(bundle, { relaunch: true, launchArguments: ["UITest_ResetStore", "UITest_IronFuelPassport", "ready", "UITest_IronFuelState", state] });
    await screen.getByTestId("main-tab-ironfuel").tap();
    await screen.getByTestId("fuel-buddy-request-field").fill("Heavy breakfast");
    await screen.getByRole("button", "Done", { exact: true }).tap();
    await expect(screen.getByRole("button", "Done", { exact: true })).toHaveCount(0);
    await reveal(screen, screen.getByTestId("fuel-buddy-submit-button"));
    await screen.getByTestId("fuel-buddy-submit-button").tap();
    await reveal(screen, screen.getByText(outcome, { exact: true }));
    await expect(screen.getByText(outcome, { exact: true })).toBeVisible();
    if (state === "generated") {
      await reveal(screen, screen.getByTestId("fuel-buddy-request-field"), { direction: "up" });
      await screen.getByTestId("fuel-buddy-request-field").fill("Quick Indian dinner");
      await expect(screen.getByText(outcome, { exact: true })).toHaveCount(0);
    }
    await app.screenshot(`ironfuel-${state}`);
  });
}

test("water history persists and local deletion requires confirmation", async ({ screen, device }) => {
  await screen.getByTestId("main-tab-progress").tap();
  await screen.getByRole("tab", "Stats", { exact: true }).tap();
  await reveal(screen, screen.getByRole("button", "Glass 3", { exact: true }));
  await screen.getByRole("button", "Glass 3", { exact: true }).tap();
  await expect(screen.getByText("3/8 glasses")).toBeVisible();
  await device.openApp(bundle, { relaunch: true, launchArguments: ["UITest_Seed", "7"] });
  // ResetStore suppresses the first intro without marking it complete.
  // Complete the real guest onboarding on the first persistence relaunch.
  await screen.getByTestId("onboarding-skip-button").tap();
  await screen.getByTestId("main-tab-progress").tap();
  await screen.getByRole("tab", "Stats", { exact: true }).tap();
  await reveal(screen, screen.getByText("3/8 glasses"));
  await expect(screen.getByText("3/8 glasses")).toBeVisible();
  await reveal(screen, screen.getByTestId("settings-button"), { direction: "up" });
  await screen.getByTestId("settings-button").tap();
  await screen.getByTestId("delete-workout-data-button").tap();
  await expect(screen.getByText("Delete local data?", { exact: true })).toBeVisible();
  await screen.getByRole("button", "Cancel", { exact: true }).tap();
  await screen.getByRole("button", "Close settings").tap();
  await reveal(screen, screen.getByText("3/8 glasses"));
  await expect(screen.getByText("3/8 glasses")).toBeVisible();
});
