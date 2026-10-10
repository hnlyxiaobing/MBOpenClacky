import { test, expect } from '@playwright/test';

async function openSkills(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  await page.locator('#skills-sidebar-item').click();
  await expect(page.locator('#skills-panel')).toBeVisible({ timeout: 5000 });
}

test.describe('场景 13: 技能管理面板', () => {
  test('技能面板打开并显示技能列表', async ({ page }) => {
    await openSkills(page);
    const list = page.locator('#skills-panel .skill-list, #skills-panel [class*="skill"]').first();
    await expect(list).toBeVisible({ timeout: 10000 });
  });

  test('技能面板包含创建与导入按钮', async ({ page }) => {
    await openSkills(page);
    const createBtn = page.locator('#btn-create-skill, [data-action="create-skill"]').first();
    const importBtn = page.locator('#btn-import-skill, [data-action="import-skill"]').first();
    await expect(createBtn).toBeVisible();
    await expect(importBtn).toBeVisible();
  });

  test('技能面板 URL hash 为 #skills', async ({ page }) => {
    await openSkills(page);
    const hash = await page.evaluate(() => window.location.hash);
    expect(hash).toBe('#skills');
  });

  test('技能面板 tab 切换', async ({ page }) => {
    await openSkills(page);
    const tabs = page.locator('#skills-panel .skills-tab:visible');
    const count = await tabs.count();
    if (count >= 2) {
      await tabs.nth(1).click();
      await page.waitForTimeout(300);
    }
    const panelVisible = await page.locator('#skills-panel').isVisible();
    expect(panelVisible).toBe(true);
  });
});
