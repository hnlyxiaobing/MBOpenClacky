import { test, expect } from '@playwright/test';

async function openProfile(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  await page.locator('#profile-sidebar-item').click();
  await expect(page.locator('#profile-panel')).toBeVisible({ timeout: 5000 });
}

test.describe('场景 16: Profile 面板', () => {
  test('Profile 面板打开并显示内容', async ({ page }) => {
    await openProfile(page);
    const panel = page.locator('#profile-panel');
    await expect(panel).toBeVisible();
    const hasContent = await panel.locator('*').count();
    expect(hasContent).toBeGreaterThan(0);
  });

  test('Profile 面板 URL hash 为 #profile', async ({ page }) => {
    await openProfile(page);
    const hash = await page.evaluate(() => window.location.hash);
    expect(hash).toBe('#profile');
  });

  test('Profile 面板包含 tab 切换', async ({ page }) => {
    await openProfile(page);
    const tabs = page.locator('#profile-panel .profile-tab, #profile-panel [data-tab]');
    const count = await tabs.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test('Profile 面板 soul/identity tab 渲染', async ({ page }) => {
    await openProfile(page);
    const soulTab = page.locator('#profile-panel [data-tab="soul"], #profile-panel .profile-tab').first();
    if (await soulTab.count() > 0) {
      await soulTab.click();
      await page.waitForTimeout(300);
      const panelVisible = await page.locator('#profile-panel').isVisible();
      expect(panelVisible).toBe(true);
    }
  });
});
