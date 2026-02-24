import { mergeConfig } from "vite";
import { defineConfig } from "vitest/config";
import { playwright } from "@vitest/browser-playwright";
import viteConfig from "./vite.config";

export default defineConfig((configEnv) =>
  mergeConfig(
    viteConfig(configEnv),
    defineConfig({
      base: "/vite-test/",
      test: {
        browser: {
          enabled: true,
          headless: true,
          provider: playwright(),
          instances: [{ browser: "chromium" }],
        },
      },
    }),
  ),
);
