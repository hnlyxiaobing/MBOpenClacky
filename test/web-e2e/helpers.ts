import { type Page, type APIRequestContext, expect } from '@playwright/test';

// Completed-run count captured by the most recent `sendMessage` for a page.
// Without it `waitForAgentResponse` cannot tell turn N's reply from turn N-1's:
// once any `.msg-assistant` exists it returns immediately and the caller reads
// a stale bubble, which made every multi-turn spec fail nondeterministically.
const responseBaseline = new WeakMap<Page, number>();

export async function assistantMessageCount(page: Page): Promise<number> {
  return page.locator('#messages .msg-assistant').count();
}

// A finished run is what the WS `complete` event reports, and the browser
// renders it as a `✓ …` `.msg-info` line (web/ws-dispatcher.js, Sessions
// .appendInfo). Counting `.msg-assistant` is NOT that signal: a ReAct turn
// emits one assistant bubble per iteration — the model narrates before each
// tool call — so the first bubble is pre-tool narration. 03-multi-turn-context
// asserted against "我直接用记忆工具保存。" because of exactly this race.
async function completedRunCount(page: Page): Promise<number> {
  return page.locator('#messages .msg-info', { hasText: '✓' }).count();
}

const MAX_AUTO_APPROVALS = 5;

// Default covers a full multi-iteration ReAct run (including a tool-confirmation
// round trip), not just the first token.
export async function waitForAgentResponse(page: Page, timeoutMs = 90000) {
  const baseline = responseBaseline.get(page) ?? 0;
  responseBaseline.delete(page);
  let start = Date.now();
  let approvals = 0;
  while (Date.now() - start < timeoutMs) {
    if (await completedRunCount(page) > baseline) return;
    const errorVisible = await page.locator('.msg-error').first().isVisible().catch(() => false);
    if (errorVisible) return;
    // `confirm_safes` (the shipped default) pauses the run whenever the model
    // wants to write — which memory-preserving prompts do, because the agent
    // saves the fact with the write tool. The run then never completes and the
    // old wait loop just reported a timeout. These specs test conversation
    // context, not the permission UX (that has its own journey scenario), so
    // approval is answered here — with a cap, so a model that keeps asking
    // fails loudly instead of burning live round trips forever.
    const overlay = page.locator('#modal-overlay');
    if (await overlay.isVisible().catch(() => false)) {
      if (approvals >= MAX_AUTO_APPROVALS) {
        throw new Error(
          `Still awaiting tool confirmation after ${approvals} approvals: ` +
          `${await page.locator('#modal-message').textContent().catch(() => '(unreadable)')}`,
        );
      }
      approvals++;
      await page.locator('#modal-yes').click();
      // The run resumes from scratch, so it gets a fresh budget; without this a
      // single approval that lands at t=85s would fail the wait seconds later.
      start = Date.now();
      continue;
    }
    await page.waitForTimeout(500);
  }
  // Timing out used to return silently, so the caller asserted against whatever
  // happened to be on screen — a stale bubble could satisfy it, turning a broken
  // run into a green test. No new response after the full budget is a failure.
  throw new Error(
    `No completed agent run within ${timeoutMs}ms ` +
    `(expected ✓ line count > ${baseline}, saw ${await completedRunCount(page)}; ` +
    `.msg-assistant count: ${await assistantMessageCount(page)}; ` +
    `tool approvals: ${approvals}; ` +
    `.msg-error visible: ${await page.locator('.msg-error').first().isVisible().catch(() => false)})`,
  );
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
  responseBaseline.set(page, await completedRunCount(page));
  await page.fill('#user-input', text);
  await page.press('#user-input', 'Enter');
}

export async function getLastAssistantText(page: Page): Promise<string | null> {
  const count = await page.locator('#messages .msg-assistant').count();
  if (count === 0) return null;
  return page.locator('#messages .msg-assistant').last().textContent();
}
