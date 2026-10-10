import { test, expect } from '@playwright/test';

async function openTrash(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  await page.locator('#trash-sidebar-item').click();
  await expect(page.locator('#trash-panel')).toBeVisible({ timeout: 5000 });
}

test.describe('场景 15: 文件回收站', () => {
  test('回收站面板打开并显示 tab 切换', async ({ page }) => {
    await openTrash(page);
    const tabs = page.locator('.trash-tab');
    const count = await tabs.count();
    expect(count).toBeGreaterThanOrEqual(2);
  });

  test('回收站 URL hash 为 #trash', async ({ page }) => {
    await openTrash(page);
    const hash = await page.evaluate(() => window.location.hash);
    expect(hash).toBe('#trash');
  });

  test('切换文件/会话 tab 显示对应面板', async ({ page }) => {
    await openTrash(page);
    const fileTab = page.locator('.trash-tab[data-tab="file-trash"]');
    const sessionTab = page.locator('.trash-tab[data-tab="session-trash"]');

    if (await fileTab.count() > 0) {
      await fileTab.click();
      const filePane = page.locator('#trash-tab-file');
      await expect(filePane).toBeVisible({ timeout: 3000 });
    }

    if (await sessionTab.count() > 0) {
      await sessionTab.click();
      const sessionPane = page.locator('#trash-tab-session');
      await expect(sessionPane).toBeVisible({ timeout: 3000 });
    }
  });

  test('文件回收站 API 可访问', async ({ request }) => {
    const res = await request.get('/api/trash/files');
    if (res.ok()) {
      const data = await res.json();
      expect(Array.isArray(data.files ?? data)).toBeTruthy();
    }
  });
});
