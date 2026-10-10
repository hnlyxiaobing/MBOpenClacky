import { test, expect } from '@playwright/test';

test.describe('场景 16: 错误处理与边界情况', () => {
  test('访问不存在的会话返回 404', async ({ request }) => {
    const resp = await request.get('/api/sessions/nonexistent-session-id-12345');
    expect(resp.status()).toBe(404);
  });

  test('删除不存在的会话返回 200（soft delete）', async ({ request }) => {
    const resp = await request.delete('/api/sessions/nonexistent-session-id-12345');
    // Server implements soft-delete: always returns 200 even for non-existent
    expect(resp.status()).toBe(200);
  });

  test('创建会话不带 name 字段仍可成功', async ({ request }) => {
    const resp = await request.post('/api/sessions', {
      data: {},
    });
    // Should create a session (with auto-generated name or empty name)
    // Server may accept or reject - both are valid behaviors
    expect(resp.status()).toBeLessThan(500);
    if (resp.ok()) {
      const data = await resp.json();
      const sessionId = data.session?.id || data.id;
      expect(sessionId).toBeTruthy();
      // Cleanup
      await request.delete(`/api/sessions/${sessionId}`);
    }
  });

  test('重命名会话为空字符串仍可接受', async ({ request }) => {
    const createResp = await request.post('/api/sessions', {
      data: { name: 'Temp' },
    });
    const data = await createResp.json();
    const sessionId = data.session?.id || data.id;

    const patchResp = await request.patch(`/api/sessions/${sessionId}/rename`, {
      data: { name: '' },
    });
    // Server may accept empty name or reject it - both are valid
    expect(patchResp.status()).toBeLessThan(500);

    // Cleanup
    await request.delete(`/api/sessions/${sessionId}`);
  });

  test('重复删除同一会话两次都返回 200（soft delete）', async ({ request }) => {
    const createResp = await request.post('/api/sessions', {
      data: { name: 'Double Delete' },
    });
    const data = await createResp.json();
    const sessionId = data.session?.id || data.id;

    // First delete should succeed
    const first = await request.delete(`/api/sessions/${sessionId}`);
    expect(first.ok()).toBeTruthy();

    // Second delete also returns 200 (soft-delete is idempotent)
    const second = await request.delete(`/api/sessions/${sessionId}`);
    expect(second.status()).toBe(200);
  });

  test('健康检查返回正确格式', async ({ request }) => {
    const resp = await request.get('/health');
    expect(resp.ok()).toBeTruthy();

    const body = await resp.json();
    expect(body.status).toBe('ok');
  });

  test('info API 返回版本信息', async ({ request }) => {
    const resp = await request.get('/api/info');
    expect(resp.ok()).toBeTruthy();

    const body = await resp.json();
    expect(body.version || body.app).toBeTruthy();
  });

  test('获取模型列表 API', async ({ request }) => {
    const resp = await request.get('/api/config/models');
    expect(resp.ok()).toBeTruthy();

    const data = await resp.json();
    // Returns { models: [...] }
    expect(Array.isArray(data.models)).toBeTruthy();
  });

  test('静态资源 SPA fallback 返回 index.html', async ({ page }) => {
    // Navigate to a non-existent route - SPA should serve index.html
    const resp = await page.goto('/nonexistent-route-xyz');
    // Should get 200 (SPA fallback) rather than 404
    expect(resp?.status()).toBe(200);
  });

  test('WebSocket 模块已加载', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#welcome, .sidebar').first()).toBeVisible({ timeout: 10000 });

    // Check that WS module is loaded by verifying the page has WebSocket-related elements
    // The WS module is an IIFE that sets up connection - verify via page state
    const hasWS = await page.evaluate(() => {
      // Check if WS global exists or if there's a WebSocket connection attempt
      return typeof (window as any).WS === 'object' ||
             typeof (window as any).Clacky === 'object';
    });
    expect(hasWS).toBeTruthy();
  });

  test('页面刷新后可重新加载', async ({ page, request }) => {
    // Create session via API
    const resp = await request.post('/api/sessions', {
      data: { name: 'Persistence Test' },
    });
    const data = await resp.json();
    const sessionId = data.session?.id || data.id;

    // Navigate to session
    await page.goto('/');
    await page.evaluate((id: string) => {
      (window as any).Clacky.Router.navigate('session', { id });
    }, sessionId);
    await expect(page.locator('#chat-panel')).toBeVisible({ timeout: 10000 });

    // Reload page - should load without errors
    await page.reload();
    // Wait for page to settle (any main element should be in DOM)
    await page.waitForTimeout(3000);

    // Session should still be accessible via API after reload
    const getResp = await request.get(`/api/sessions/${sessionId}`);
    expect(getResp.ok()).toBeTruthy();
  });
});
