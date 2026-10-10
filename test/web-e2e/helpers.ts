import { type Page, type APIRequestContext, expect } from '@playwright/test';

export async function waitForAgentResponse(page: Page, timeoutMs = 30000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const assistantCount = await page.locator('#messages .msg-assistant').count();
    if (assistantCount > 0) return;
    const errorVisible = await page.locator('.msg-error').first().isVisible().catch(() => false);
    if (errorVisible) return;
    await page.waitForTimeout(500);
  }
}

export async function createSessionAndNavigate(page: Page, request: APIRequestContext) {
  await page.goto('/');
  await expect(page.locator('#welcome')).toBeVisible({ timeout: 15000 });

  const resp = await request.post('/api/sessions', {
    data: { name: 'E2E Test Session' },
  });
  expect(resp.ok()).toBeTruthy();
  const session = await resp.json();
  const sid = session.session?.id || session.id;
  expect(sid).toBeTruthy();

  await page.evaluate((id: string) => {
    (window as any).Clacky.Router.navigate('session', { id });
  }, sid);

  await expect(page.locator('#chat-panel')).toBeVisible({ timeout: 10000 });
  await expect(page.locator('#btn-send')).toBeEnabled({ timeout: 10000 });
  return session;
}

export async function sendMessage(page: Page, text: string) {
  await page.fill('#user-input', text);
  await page.press('#user-input', 'Enter');
}

export async function getLastAssistantText(page: Page): Promise<string | null> {
  const count = await page.locator('#messages .msg-assistant').count();
  if (count === 0) return null;
  return page.locator('#messages .msg-assistant').last().textContent();
}
