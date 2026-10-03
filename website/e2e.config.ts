import { web } from "@e2e-dev/web";
import type { E2EConfig } from "e2e";
import { googleChrome } from "./e2e/chrome-provider.js";

export default {
  tests: "e2e/**/*.e2e.ts",
  targets: [{
    name: "google-chrome",
    engine: web({ browser: googleChrome(), viewport: { width: 1440, height: 900 } }),
    app: {
      url: "http://127.0.0.1:4313",
      command: { executable: "node", args: ["node_modules/next/dist/bin/next", "start", "--hostname", "127.0.0.1", "--port", "4313"], log: ".e2e/logs/website.log" },
    },
  }],
  workers: 1,
  retries: 0,
  timeout: 60_000,
  assertionTimeout: 10_000,
  trace: "retain-on-failure",
  cache: "off",
  reporters: ["list", "markdown", "junit"],
} satisfies E2EConfig;
