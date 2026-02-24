import path from "path";
import { defineConfig } from "vite";
import ReactPlugin from "@vitejs/plugin-react";
import StimulusHMRPlugin from "vite-plugin-stimulus-hmr";
import fg from "fast-glob";

const projectRoot = process.cwd();
const sourceCodeDir = path.resolve(projectRoot, "app/javascript");

function envConfig(mode: string) {
  if (mode === "development")
    return { publicOutputDir: "vite-dev", port: 3036 };
  if (mode === "test") return { publicOutputDir: "vite-test", port: 3037 };
  return { publicOutputDir: "vite", port: 3036 };
}

export default defineConfig(({ mode }) => {
  const { publicOutputDir, port } = envConfig(mode);
  const isLocal = mode === "development" || mode === "test";
  const base = `/${publicOutputDir}/`;
  const outDir = path.resolve(projectRoot, "public", publicOutputDir);

  const entrypointFiles = fg.sync(`${sourceCodeDir}/entrypoints/**/*`);
  const input = Object.fromEntries(
    entrypointFiles.map((file) => [path.relative(sourceCodeDir, file), file]),
  );

  return {
    root: sourceCodeDir,
    base,
    envDir: projectRoot,
    resolve: {
      alias: {
        "~/": `${sourceCodeDir}/`,
        "@/": `${sourceCodeDir}/`,
        // Stimulus controllers
        controllers: path.resolve(sourceCodeDir, "controllers"),
      },
    },
    server: {
      host: process.env.VITE_RUBY_HOST || "localhost",
      port,
    },
    build: {
      manifest: true,
      outDir,
      emptyOutDir: isLocal,
      sourcemap: !isLocal,
      assetsDir: "assets",
      rollupOptions: {
        input,
        output: {
          assetFileNames: "assets/[name]-[hash].[ext]",
          entryFileNames: "assets/[name]-[hash].js",
        },
      },
    },
    plugins: [ReactPlugin(), StimulusHMRPlugin()],
  };
});
