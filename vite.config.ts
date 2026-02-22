import path from "path";
import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import StimulusHMRPlugin from "vite-plugin-stimulus-hmr";

export default defineConfig({
  resolve: {
    alias: {
      "@views": path.resolve(__dirname, "app/views"),
      "@javascript": path.resolve(__dirname, "app/javascript"),

      // Stimulus controllers
      "controllers": path.resolve(__dirname, "app/javascript/controllers"),
    },
  },
  plugins: [
    RubyPlugin(),
    StimulusHMRPlugin(),
  ],
})
