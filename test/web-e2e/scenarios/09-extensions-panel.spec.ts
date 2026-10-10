import { test, expect } from '@playwright/test';

async function openExtensions(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  await page.locator('#extensions-sidebar-item').click();
  await expect(page.locator('#extensions-panel')).toBeVisible({ timeout: 5000 });
}

test.describe('场景 14: 扩展市场面板', () => {
  test('扩展面板打开并显示内容', async ({ page }) => {
    await openExtensions(page);
    const panel = page.locator('#extensions-panel');
    await expect(panel).toBeVisible();
    const hasContent = await panel.locator('*').count();
    expect(hasContent).toBeGreaterThan(0);
  });

  test('扩展面板 URL hash 为 #extensions', async ({ page }) => {
    await openExtensions(page);
    const hash = await page.evaluate(() => window.location.hash);
    expect(hash).toMatch(/^#extensions/);
  });

  test('扩展面板包含搜索或分类区域', async ({ page }) => {
    await openExtensions(page);
    const panel = page.locator('#extensions-panel');
    const searchOrTabs = panel.locator(
      'input[type="search"], input[placeholder*="search" i], .ext-tabs, .ext-filter, [class*="tab"], [class*="search"]'
    ).first();
    await expect(searchOrTabs).toBeVisible({ timeout: 5000 });
  });

  test('扩展列表加载（API 驱动）', async ({ request }) => {
    const res = await request.get('/api/extensions');
    if (res.ok()) {
      const data = await res.json();
      expect(Array.isArray(data.extensions ?? data)).toBeTruthy();
    }
  });
});
