import path from "path";
import { mergeConfig } from "vite";
import { defineConfig } from "vitest/config";
import { playwright } from "@vitest/browser-playwright";
import viteConfig from "./vite.config";

const projectRoot = process.cwd();

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
          screenshotDirectory: path.resolve(projectRoot, "tmp/screenshots-js"),
        },
        coverage: {
          enabled: true,
          include: ["**/*.{js,jsx,ts,tsx}"],
          reportOnFailure: true,
          reportsDirectory: path.resolve(projectRoot, "coverage-js"),
        },
      },
    }),
  ),
);
