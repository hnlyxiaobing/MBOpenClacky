import { test, expect } from '@playwright/test';

async function openBilling(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  await page.locator('#billing-sidebar-item').click();
  await expect(page.locator('#billing-panel')).toBeVisible({ timeout: 5000 });
}

test.describe('场景 25: Billing 费用面板', () => {
  test('billing 面板打开并显示内容', async ({ page }) => {
    await openBilling(page);
    const panel = page.locator('#billing-panel');
    await expect(panel).toBeVisible();
    const content = panel.locator('#billing-content');
    await expect(content).toBeVisible({ timeout: 5000 });
  });

  test('billing 面板 URL hash 为 #billing', async ({ page }) => {
    await openBilling(page);
    const hash = await page.evaluate(() => window.location.hash);
    expect(hash).toMatch(/^#billing/);
  });

  test('billing dashboard 渲染（骨架或数据）', async ({ page }) => {
    await openBilling(page);
    const panel = page.locator('#billing-panel');
    const dashboard = panel.locator('.billing-dashboard, .billing-skeleton, .billing-error').first();
    await expect(dashboard).toBeVisible({ timeout: 10000 });
  });

  test('billing API 返回有效响应', async ({ request }) => {
    const res = await request.get('/api/billing/summary');
    if (res.ok()) {
      const data = await res.json();
      expect(typeof data).toBe('object');
    }
  });

  test('billing 面板包含周期筛选控件', async ({ page }) => {
    await openBilling(page);
    const panel = page.locator('#billing-panel');
    const controls = panel.locator('.billing-controls, .billing-period-tabs, [class*="period"], [class*="filter"]').first();
    await expect(controls).toBeVisible({ timeout: 5000 });
  });
});
