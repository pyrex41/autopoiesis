import { defineConfig } from "vite";
import solidPlugin from "vite-plugin-solid";

export default defineConfig({
  plugins: [solidPlugin()],
  build: {
    target: "esnext",
    outDir: "dist",
    lib: {
      entry: "src/holodeck-standalone.tsx",
      formats: ["es"],
      fileName: () => "holodeck.js",
    },
    rollupOptions: {
      output: {
        inlineDynamicImports: true,
      },
    },
  },
});
