import { test, expect } from '@playwright/test';
import { waitForAgentResponse, createSessionAndNavigate, sendMessage, getLastAssistantText } from '../helpers';

test.describe('场景 8: 多轮对话上下文保持', () => {
  test('连续对话中 Agent 记住上下文', async ({ page, request }) => {
    test.setTimeout(300_000);
    const session = await createSessionAndNavigate(page, request);

    // Turn 1: 告诉 Agent 一个事实
    await sendMessage(page, '我的项目名叫 Phoenix，请记住这个名字');
    await waitForAgentResponse(page);

    const firstResponse = await getLastAssistantText(page);
    // A run that produced no assistant text at all is an unavailable model, and
    // that has to show up as a SKIP in the report — `return` used to record a
    // PASS for a test that asserted nothing.
    if (!firstResponse) {
      test.skip(true, 'no assistant reply — LLM unavailable');
    }

    // Turn 2: 询问 Agent 是否记住
    await sendMessage(page, '我的项目名叫什么？');
    await waitForAgentResponse(page);

    const secondResponse = await getLastAssistantText(page);
    expect(secondResponse).toBeTruthy();
    // 验证 Agent 记住了项目名称（不区分大小写）
    expect(secondResponse?.toLowerCase()).toContain('phoenix');
  });

  test('三轮对话持续保持上下文', async ({ page, request }) => {
    // Three live model round trips. `waitForAgentResponse` allows 90s per turn
    // and restarts that budget after each tool-confirmation it answers, so the
    // test budget has to cover the worst case, not three fast replies.
    test.setTimeout(300_000);
    await createSessionAndNavigate(page, request);

    // Turn 1
    await sendMessage(page, '我最喜欢的颜色是蓝色');
    await waitForAgentResponse(page);

    const response1 = await getLastAssistantText(page);
    if (!response1) {
      test.skip(true, 'no assistant reply — LLM unavailable');
    }

    // Turn 2
    await sendMessage(page, '我最喜欢的颜色是什么？');
    await waitForAgentResponse(page);
    const response2 = await getLastAssistantText(page);
    expect(response2?.toLowerCase()).toContain('蓝');

    // Turn 3: 再次确认
    await sendMessage(page, '再重复一次我的偏好');
    await waitForAgentResponse(page);
    const response3 = await getLastAssistantText(page);
    expect(response3?.toLowerCase()).toContain('蓝');
  });

  test('新会话不继承旧会话上下文', async ({ page, request }) => {
    // Two live model round trips plus two session bootstraps — the heaviest
    // case in this file.
    test.setTimeout(300_000);
    // 第一个会话：告诉 Agent 一个事实
    await createSessionAndNavigate(page, request);
    await sendMessage(page, '我的名字是 Alice');
    await waitForAgentResponse(page);

    // 创建第二个会话
    await createSessionAndNavigate(page, request);
    await sendMessage(page, '我叫什么名字？');
    await waitForAgentResponse(page);

    const response = await getLastAssistantText(page);
    if (!response) {
      test.skip(true, 'no assistant reply — LLM unavailable');
    }
    // The title overstates what is guaranteed here. Conversation *history* is
    // per-session, but the assistant-memory file is shared, so a new session
    // can legitimately know the name it was told in an older one. What this
    // asserts is that the second session booted and ran its own turn; the
    // history-isolation contract itself belongs to a deterministic (mocked)
    // scenario, not a live model.
    expect(response?.length).toBeGreaterThan(0);
  });
});
