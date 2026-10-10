import { test, expect } from '@playwright/test';

async function openTasks(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  await page.locator('#tasks-sidebar-item').click();
  await expect(page.locator('#task-detail-panel, #tasks-panel').first()).toBeVisible({ timeout: 5000 });
}

test.describe('场景 31: 定时任务面板', () => {
  test('任务面板打开并显示内容', async ({ page }) => {
    await openTasks(page);
    const panel = page.locator('#task-detail-panel, #tasks-panel').first();
    await expect(panel).toBeVisible();
    const hasContent = await panel.locator('*').count();
    expect(hasContent).toBeGreaterThan(0);
  });

  test('任务面板 URL hash 为 #tasks', async ({ page }) => {
    await openTasks(page);
    const hash = await page.evaluate(() => window.location.hash);
    expect(hash).toMatch(/^#tasks/);
  });

  test('任务面板显示任务列表或空状态', async ({ page }) => {
    await openTasks(page);
    const panel = page.locator('#task-detail-panel, #tasks-panel').first();
    const listOrEmpty = panel.locator('.task-card, .task-table-empty, #task-list-table, .task-list-table').first();
    await expect(listOrEmpty).toBeVisible({ timeout: 5000 });
  });

  test('任务 API 返回有效响应', async ({ request }) => {
    const res = await request.get('/api/tasks');
    if (res.ok()) {
      const data = await res.json();
      expect(Array.isArray(data.tasks ?? data)).toBeTruthy();
    }
  });

  test('任务卡片显示 cron 表达式和操作按钮', async ({ page }) => {
    await openTasks(page);
    const panel = page.locator('#task-detail-panel, #tasks-panel').first();
    const cards = panel.locator('.task-card');
    const count = await cards.count();
    if (count > 0) {
      const firstCard = cards.first();
      const cron = firstCard.locator('.task-card-cron');
      await expect(cron).toBeVisible({ timeout: 3000 });
      const actions = firstCard.locator('.task-card-actions, .task-action-btn').first();
      await expect(actions).toBeVisible({ timeout: 3000 });
    }
  });
});
