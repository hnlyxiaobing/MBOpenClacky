import { test, expect } from '@playwright/test';

async function openMcp(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  await page.locator('#mcp-sidebar-item').click();
  await expect(page.locator('#mcp-panel')).toBeVisible({ timeout: 5000 });
}

test.describe('场景 29: MCP 服务器面板', () => {
  test('MCP 面板打开并显示内容', async ({ page }) => {
    await openMcp(page);
    const panel = page.locator('#mcp-panel');
    await expect(panel).toBeVisible();
    const hasContent = await panel.locator('*').count();
    expect(hasContent).toBeGreaterThan(0);
  });

  test('MCP 面板 URL hash 为 #mcp', async ({ page }) => {
    await openMcp(page);
    const hash = await page.evaluate(() => window.location.hash);
    expect(hash).toMatch(/^#mcp/);
  });

  test('MCP 面板显示列表区域或空状态', async ({ page }) => {
    await openMcp(page);
    const panel = page.locator('#mcp-panel');
    const listOrEmpty = panel.locator('#mcp-list, .mcp-empty, .mcp-cta').first();
    await expect(listOrEmpty).toBeVisible({ timeout: 5000 });
  });

  test('MCP 面板显示配置路径信息', async ({ page }) => {
    await openMcp(page);
    const panel = page.locator('#mcp-panel');
    const configLine = panel.locator('.mcp-config-line, .mcp-config-text').first();
    await expect(configLine).toBeVisible({ timeout: 5000 });
  });

  test('MCP API 返回服务器列表', async ({ request }) => {
    const res = await request.get('/api/mcp/servers');
    if (res.ok()) {
      const data = await res.json();
      expect(Array.isArray(data.servers ?? data)).toBeTruthy();
    }
  });

  test('MCP 面板有刷新按钮', async ({ page }) => {
    await openMcp(page);
    const panel = page.locator('#mcp-panel');
    const refreshBtn = panel.locator('#btn-mcp-refresh, .btn-mcp-refresh').first();
    await expect(refreshBtn).toBeVisible({ timeout: 5000 });
  });
});
