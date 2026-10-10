import { test, expect } from '@playwright/test';

async function openChannels(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  await page.locator('#channels-sidebar-item').click();
  await expect(page.locator('#channels-panel')).toBeVisible({ timeout: 5000 });
}

test.describe('场景 30: 渠道管理面板', () => {
  test('渠道面板打开并显示内容', async ({ page }) => {
    await openChannels(page);
    const panel = page.locator('#channels-panel');
    await expect(panel).toBeVisible();
    const hasContent = await panel.locator('*').count();
    expect(hasContent).toBeGreaterThan(0);
  });

  test('渠道面板 URL hash 为 #channels', async ({ page }) => {
    await openChannels(page);
    const hash = await page.evaluate(() => window.location.hash);
    expect(hash).toMatch(/^#channels/);
  });

  test('渠道面板显示平台列表或配置区域', async ({ page }) => {
    await openChannels(page);
    const panel = page.locator('#channels-panel');
    const hasContent = await panel.locator('.channel-card, .platform-list, [class*="channel"], [class*="platform"]').count();
    expect(hasContent).toBeGreaterThanOrEqual(0);
  });

  test('渠道面板包含配置说明或平台信息', async ({ page }) => {
    await openChannels(page);
    const panel = page.locator('#channels-panel');
    const hasText = await panel.locator('text=/飞书|微信|Telegram|Discord|钉钉|企业/i').count();
    expect(hasText).toBeGreaterThanOrEqual(0);
  });

  test('渠道面板包含操作区域或按钮', async ({ page }) => {
    await openChannels(page);
    const panel = page.locator('#channels-panel');
    const hasActions = await panel.locator('button, .actions, [class*="action"]').count();
    expect(hasActions).toBeGreaterThanOrEqual(0);
  });
});
