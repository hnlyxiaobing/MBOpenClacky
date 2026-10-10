import { test, expect } from '@playwright/test';

test.describe('Web UI 基础验证', () => {
  test('健康检查 API', async ({ request }) => {
    const response = await request.get('/health');
    expect(response.ok()).toBeTruthy();
    const body = await response.json();
    expect(body.status).toBe('ok');
  });

  test('首页加载成功', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle(/MBOpenClacky/);
  });

  test('侧边栏可见', async ({ page }) => {
    await page.goto('/');
    const sidebar = page.locator('[data-testid="sidebar"], .sidebar, aside').first();
    await expect(sidebar).toBeVisible();
  });

  test('新建会话按钮存在', async ({ page }) => {
    await page.goto('/');
    const newSessionBtn = page.locator('#btn-new-session-inline, #btn-new-session, button, [role="button"]').filter({ hasText: /新建|new|创建/i }).first();
    await expect(newSessionBtn).toBeAttached({ timeout: 5000 });
  });
});
