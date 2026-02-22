import path from "path";
import { defineConfig } from "vite";
import ReactPlugin from "@vitejs/plugin-react";
import RubyPlugin from "vite-plugin-ruby";
import StimulusHMRPlugin from "vite-plugin-stimulus-hmr";

export default defineConfig({
  resolve: {
    alias: {
      // Stimulus controllers
      controllers: path.resolve(__dirname, "app/javascript/controllers"),
    },
  },
  plugins: [ReactPlugin(), RubyPlugin(), StimulusHMRPlugin()],
});
