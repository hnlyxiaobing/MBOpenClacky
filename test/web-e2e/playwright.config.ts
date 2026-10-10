import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './scenarios',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:7071',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { 
        ...devices['Desktop Chrome'],
        launchOptions: {
          executablePath: 'C:/Users/hnlyh/AppData/Local/ms-playwright/chromium-1248/chrome-win64/chrome.exe',
        },
      },
    },
  ],
  webServer: {
    command: 'D:/MoonBit/MBOpenClacky/_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe server --port 7071',
    url: 'http://localhost:7071/health',
    reuseExistingServer: !process.env.CI,
    timeout: 10000,
  },
});
