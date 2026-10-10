import { defineConfig } from 'vite';

export default defineConfig({
  server: {
    proxy: {
      '/sync': { target: 'ws://127.0.0.1:8787', ws: true },
      '/api': 'http://127.0.0.1:8787',
    },
  },
});
