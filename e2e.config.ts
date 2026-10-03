import { mobile } from "@e2e-dev/mobile";
import type { E2EConfig } from "e2e";

export default {
  tests: "e2e/**/*.e2e.ts",
  targets: [{
    name: "setzo-ios",
    engine: mobile({ platform: "ios", device: process.env.SETZO_E2E_DEVICE ?? "Setzo E2E", session: "setzo-e2e", settle: 250 }),
    app: {
      bundleId: "com.parthjadhav.ironlog",
      appPath: `${process.env.SETZO_E2E_DERIVED_DATA ?? "build/e2e/DerivedData"}/Build/Products/Debug-iphonesimulator/Setzo.app`,
      launchArguments: ["UITest_ResetStore", "UITest_Seed", "7"],
    },
  }],
  workers: 1,
  retries: 0,
  timeout: 120_000,
  launchTimeout: 120_000,
  actionTimeout: 30_000,
  assertionTimeout: 10_000,
  cache: "off",
  reporters: ["list", "markdown", "junit"],
} satisfies E2EConfig;
