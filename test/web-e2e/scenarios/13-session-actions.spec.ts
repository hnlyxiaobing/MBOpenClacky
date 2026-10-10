import { test, expect } from '@playwright/test';
import { createSessionAndNavigate } from '../helpers';

test.describe('场景 13: 会话管理操作', () => {
  test('会话列表显示至少一个会话', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);
    await page.goto('/');

    const sessionItems = page.locator('.session-item, [data-session-id]');
    await expect(sessionItems.first()).toBeVisible({ timeout: 10000 });
    const count = await sessionItems.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test('通过 API 重命名会话', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const patchResp = await request.patch(`/api/sessions/${sessionId}/rename`, {
      data: { name: 'Renamed by API' },
    });
    expect(patchResp.ok()).toBeTruthy();

    // Verify via GET
    const getResp = await request.get(`/api/sessions/${sessionId}`);
    const detail = await getResp.json();
    const name = detail.session?.name || detail.name;
    expect(name).toBe('Renamed by API');
  });

  test('通过 API 删除会话', async ({ page, request }) => {
    const session = await request.post('/api/sessions', {
      data: { name: 'To Delete' },
    });
    const data = await session.json();
    const sessionId = data.session?.id || data.id;

    const deleteResp = await request.delete(`/api/sessions/${sessionId}`);
    expect(deleteResp.ok()).toBeTruthy();

    // Verify it's gone
    const getResp = await request.get(`/api/sessions/${sessionId}`);
    expect(getResp.status()).toBe(404);
  });

  test('通过 API fork 会话', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const forkResp = await request.post(`/api/sessions/${sessionId}/fork`);
    expect(forkResp.ok()).toBeTruthy();

    const forked = await forkResp.json();
    const forkedId = forked.forked_session?.session_id || forked.forked_session?.id;
    expect(forkedId).toBeTruthy();
    expect(forkedId).not.toBe(sessionId);
    expect(forked.source_session_id).toBe(sessionId);
  });

  test('会话详情 API 返回完整信息', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.get(`/api/sessions/${sessionId}`);
    expect(resp.ok()).toBeTruthy();

    const detail = await resp.json();
    const s = detail.session || detail;
    expect(s.id).toBe(sessionId);
    expect(s.name).toBeTruthy();
  });

  test('获取会话消息列表 API', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.get(`/api/sessions/${sessionId}/messages`);
    expect(resp.ok()).toBeTruthy();

    const data = await resp.json();
    // Messages API returns { events: [...], has_more: bool }
    expect(Array.isArray(data.events)).toBeTruthy();
    expect(typeof data.has_more).toBe('boolean');
  });

  test('获取会话成本信息 API', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.get(`/api/sessions/${sessionId}/cost`);
    expect(resp.ok()).toBeTruthy();

    const data = await resp.json();
    // Cost endpoint should return some structure
    expect(data).toBeTruthy();
  });

  test('获取会话工具列表 API', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.get(`/api/sessions/${sessionId}/tools`);
    expect(resp.ok()).toBeTruthy();

    const data = await resp.json();
    expect(Array.isArray(data.tools || data)).toBeTruthy();
  });
});
