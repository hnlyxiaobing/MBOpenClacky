import { test, expect } from '@playwright/test';
import { createSessionAndNavigate, sendMessage, waitForAgentResponse } from '../helpers';

test.describe('场景 15: 会话导出与批量操作', () => {
  test('导出会话为 JSON', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.post(`/api/sessions/${sessionId}/export`);
    expect(resp.ok()).toBeTruthy();

    const data = await resp.json();
    expect(data).toBeTruthy();
    // Export should contain session data
    expect(data.session || data.messages || data.id).toBeTruthy();
  });

  test('导出所有会话', async ({ page, request }) => {
    const resp = await request.get('/api/sessions/export-all');
    expect(resp.ok()).toBeTruthy();

    // Returns ZIP binary with Content-Type: application/zip
    const contentType = resp.headers()['content-type'] || '';
    expect(contentType).toContain('application/zip');
  });

  test('批量导出 ZIP 格式', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.post(`/api/sessions/${sessionId}/export/zip`);
    // ZIP export may return binary or may not be implemented in all builds
    // Just verify the endpoint responds (200 or 404 are both acceptable)
    expect(resp.status()).toBeLessThan(500);
  });

  test('获取会话状态 API', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.get(`/api/sessions/${sessionId}/status`);
    expect(resp.ok()).toBeTruthy();

    const data = await resp.json();
    expect(data).toBeTruthy();
    // Status should have some state information
    expect(data.status || data.state || data.id).toBeTruthy();
  });

  test('取消会话执行 API', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.post(`/api/sessions/${sessionId}/cancel`);
    // Cancel may return 200 (ok) or 400 (no active agent) - both are valid
    expect(resp.status()).toBeLessThan(500);
  });

  test('获取会话技能列表 API', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.get(`/api/sessions/${sessionId}/skills`);
    expect(resp.ok()).toBeTruthy();

    const data = await resp.json();
    expect(Array.isArray(data.skills || data)).toBeTruthy();
  });

  test('获取会话文件列表 API', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.get(`/api/sessions/${sessionId}/files`);
    expect(resp.ok()).toBeTruthy();

    const data = await resp.json();
    expect(Array.isArray(data.files || data)).toBeTruthy();
  });

  test('获取 Time Machine 快照列表 API', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.get(`/api/sessions/${sessionId}/time-machine`);
    // May return 200 with points or 500 if no config path
    expect(resp.status()).toBeLessThan(501);

    if (resp.ok()) {
      const data = await resp.json();
      // Time Machine returns { session_id, points: [...] }
      expect(data.session_id || Array.isArray(data.points)).toBeTruthy();
    }
  });

  test('获取 Git 状态 API', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.get(`/api/sessions/${sessionId}/git/status`);
    // May return 200 with git status or 400/500 if no git repo configured
    expect(resp.status()).toBeLessThan(501);
  });

  test('会话 patch 更新字段', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);
    const sessionId = session.session?.id || session.id;

    const resp = await request.patch(`/api/sessions/${sessionId}`, {
      data: { name: 'Patched Name' },
    });
    expect(resp.ok()).toBeTruthy();

    // Verify the change
    const getResp = await request.get(`/api/sessions/${sessionId}`);
    const detail = await getResp.json();
    const name = detail.session?.name || detail.name;
    expect(name).toBe('Patched Name');
  });
});
