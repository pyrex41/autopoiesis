import { defineConfig } from "vite";
import solidPlugin from "vite-plugin-solid";

// Backend ports (mapped from container 8080/8081)
const WS_PORT = process.env.AP_WS_PORT ?? "8095";
const REST_PORT = process.env.AP_REST_PORT ?? "8097";

export default defineConfig({
  plugins: [solidPlugin()],
  server: {
    port: 3000,
    proxy: {
      "/api": {
        target: `http://localhost:${REST_PORT}`,
        changeOrigin: true,
      },
      "/ws": {
        target: `ws://localhost:${WS_PORT}`,
        ws: true,
      },
    },
  },
  build: {
    target: "esnext",
  },
});
