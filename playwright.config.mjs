import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './scripts/tests/browser',
  fullyParallel: true,
  workers: 2,
  retries: process.env.CI ? 1 : 0,
  forbidOnly: Boolean(process.env.CI),
  reporter: 'list',
  use: {
    baseURL: 'http://127.0.0.1:4321',
    locale: 'en-US',
    browserName: 'chromium',
    launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined },
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'pnpm docs:preview --host 127.0.0.1 --port 4321',
    url: 'http://127.0.0.1:4321/winenv/',
    reuseExistingServer: !process.env.CI,
    // Playwright owns this process, including when run by a coding agent.
    env: { ASTRO_TELEMETRY_DISABLED: '1', ASTRO_PREVIEW_BACKGROUND: '0' },
  },
});
