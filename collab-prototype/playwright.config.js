import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  workers: 1,
  use: { baseURL: 'http://127.0.0.1:8790', browserName: 'chromium', channel: 'chromium' },
  webServer: {
    command: 'node server.js',
    url: 'http://127.0.0.1:8790',
    env: { PORT: '8790', DATA_DIR: 'test-results/server-data' },
    reuseExistingServer: false,
  },
});
