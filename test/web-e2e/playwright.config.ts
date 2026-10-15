import { defineConfig, devices } from '@playwright/test';
import { existsSync, statSync } from 'fs';
import * as path from 'path';

// The server resolves its frontend assets relative to the process cwd
// (`StaticServer::new("web")` / `web/index.html`), so it must be spawned from
// the repository root. Playwright defaults `cwd` to this config's directory.
const repoRoot = path.resolve(__dirname, '../..');

// Both `build/cmd/` and `build/<module>/cmd/` layouts exist depending on how
// the release build was invoked; take the most recently built one so the suite
// never silently drives a stale binary.
function resolveServerBin(): string {
  const exe = process.platform === 'win32' ? 'cmd.exe' : 'cmd';
  const found = [
    path.join(repoRoot, '_build', 'native', 'release', 'build', 'cmd', exe),
    path.join(
      repoRoot, '_build', 'native', 'release', 'build',
      'hnlyxiaobing', 'MBOpenClacky', 'cmd', exe,
    ),
  ].filter((candidate) => existsSync(candidate));
  if (found.length === 0) {
    throw new Error(
      'No release binary under _build/native/release; run: moon build --target native --release cmd',
    );
  }
  return found.reduce((a, b) => (statSync(a).mtimeMs >= statSync(b).mtimeMs ? a : b));
}

export default defineConfig({
  testDir: './scenarios',
  // Each live turn can stream for a minute and `waitForAgentResponse` allows
  // 90s for it; Playwright's 30s default would kill the test mid-wait.
  timeout: 180_000,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : 3,
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
    command: `"${resolveServerBin()}" server --port 7071`,
    cwd: repoRoot,
    url: 'http://localhost:7071/health',
    reuseExistingServer: !process.env.CI,
    timeout: 10000,
  },
});
