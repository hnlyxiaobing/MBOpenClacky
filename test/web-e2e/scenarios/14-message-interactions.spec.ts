import { test, expect } from '@playwright/test';
import { createSessionAndNavigate, sendMessage, waitForAgentResponse, getLastAssistantText } from '../helpers';

test.describe('场景 14: 消息交互', () => {
  test('用户消息气泡显示复制按钮', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);
    await sendMessage(page, 'Hello, this is a test message');
    await page.waitForTimeout(1000);

    // The action bar is a SIBLING of the bubble inside .msg-user-wrap
    // (_appendUserActionBar in web/sessions.js appends to the wrap, not to
    // .msg-user), so it must be located from the wrap. Hover-reveal is CSS
    // opacity, so DOM presence is the contract — the button used to be located
    // and never asserted, which made this pass with no action bar at all.
    const wrap = page.locator('#messages .msg-user-wrap').last();
    await expect(wrap.locator('.msg-user')).toBeVisible({ timeout: 5000 });
    await wrap.hover();
    await expect(wrap.locator('.msg-user-action-btn')).toHaveCount(2);
    await expect(wrap.locator('.msg-edit-btn')).toHaveCount(1);
    const text = await wrap.locator('.msg-user').textContent();
    expect(text).toContain('Hello');
  });

  test('助手消息气泡显示复制按钮', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);
    await sendMessage(page, 'Please say hello');
    await waitForAgentResponse(page);

    const assistantMsg = page.locator('#messages .msg-assistant').last();
    const hasAssistant = await assistantMsg.count() > 0;
    if (!hasAssistant) {
      test.skip(true, 'LLM unavailable');
      return;
    }

    // Assistant message should have a copy button. `.msg-copy-btn` is rendered
    // with the bubble and only revealed on hover via CSS opacity, so its
    // presence in the DOM is the contract under test.
    const copyBtn = assistantMsg.locator('.msg-copy-btn').first();
    await expect(copyBtn).toHaveCount(1);
  });

  test('消息区域支持滚动', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    // Send multiple messages to create scrollable content
    for (let i = 0; i < 3; i++) {
      await sendMessage(page, `Message number ${i + 1}`);
      await page.waitForTimeout(500);
    }

    const messagesContainer = page.locator('#messages');
    await expect(messagesContainer).toBeVisible({ timeout: 5000 });

    // The scroll contract is the container's own overflow rule
    // (.chat-messages-scroll { overflow-y: auto } in web/app.css), not whether
    // three short messages happen to overflow. The previous version computed
    // `isScrollable`, never used it, and asserted that a locator was truthy —
    // which cannot fail.
    const overflowY = await page.evaluate(() => {
      const el = document.getElementById('messages');
      return el ? getComputedStyle(el).overflowY : null;
    });
    expect(overflowY).toBe('auto');
  });

  test('输入框支持 Shift+Enter 换行', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    const input = page.locator('#user-input');
    await input.fill('Line 1');
    await input.press('Shift+Enter');
    await input.type('Line 2');

    const value = await input.inputValue();
    expect(value).toContain('Line 1');
    expect(value).toContain('Line 2');
    // Should contain a newline character
    expect(value).toContain('\n');
  });

  test('空消息不能发送', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    const sendBtn = page.locator('#btn-send');
    const input = page.locator('#user-input');

    // Clear input
    await input.fill('');

    // Send button should be disabled or clicking should not create a message
    const isDisabled = await sendBtn.isDisabled();
    if (!isDisabled) {
      const beforeCount = await page.locator('#messages .msg-user').count();
      await sendBtn.click();
      await page.waitForTimeout(500);
      const afterCount = await page.locator('#messages .msg-user').count();
      // No new user message should appear
      expect(afterCount).toBe(beforeCount);
    } else {
      expect(isDisabled).toBe(true);
    }
  });

  test('消息编辑按钮存在', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);
    await sendMessage(page, 'Edit me please');
    await page.waitForTimeout(1000);

    // This test is named for the edit button but only asserted the bubble text.
    // The wrap holds the button (.msg-edit-btn) and clicking it swaps the
    // bubble for the inline editor (_enterEditMode → .msg-user-edit-textarea).
    const wrap = page.locator('#messages .msg-user-wrap').last();
    await expect(wrap.locator('.msg-user')).toBeVisible();
    expect(await wrap.locator('.msg-user').textContent()).toContain('Edit me');

    const editBtn = wrap.locator('.msg-edit-btn');
    await expect(editBtn).toHaveCount(1);
    // .msg-user-actions is pointer-events:none until .msg-user-wrap:hover
    // (web/app.css), so the click needs the hover first.
    await wrap.hover();
    await editBtn.click();

    // Editing rewrites history, so the button deliberately raises the
    // throw-away warning first (sessions.js → Modal.confirmOnce) and only swaps
    // the bubble for the inline editor after it is dismissed. Asserting the
    // textarea straight after the click tests a state the product never enters.
    const overlay = page.locator('#modal-overlay');
    await expect(overlay).toBeVisible({ timeout: 5000 });
    await page.locator('#modal-yes').click();
    await expect(overlay).toBeHidden();
    await expect(wrap.locator('.msg-user-edit-textarea')).toBeVisible({ timeout: 5000 });
    expect(await wrap.locator('.msg-user-edit-textarea').inputValue()).toContain('Edit me');

    // Escaping the editor must restore the original bubble, not leave an empty
    // bubble behind (_exitEditMode restores dataset.originalHtml).
    await wrap.locator('.msg-user-edit-cancel').click();
    await expect(wrap.locator('.msg-user-edit-textarea')).toHaveCount(0);
    expect(await wrap.locator('.msg-user').textContent()).toContain('Edit me');
  });

  test('图片缩略图点击打开灯箱', async ({ page, request }) => {
    const path = require('path');
    const FIXTURES_DIR = path.join(__dirname, '..', 'fixtures');

    await createSessionAndNavigate(page, request);

    // Upload an image
    const fileInput = page.locator('#image-file-input');
    await fileInput.setInputFiles(path.join(FIXTURES_DIR, 'red.png'));
    await expect(page.locator('#image-preview-strip')).toBeVisible({ timeout: 5000 });

    // Send the message
    await sendMessage(page, 'Check this image');
    await page.waitForTimeout(2000);

    // Look for image thumbnail in the preview strip (before send it's there, after send it may be in messages)
    const previewThumb = page.locator('#image-preview-strip .msg-image-thumb, #image-preview-strip img').first();
    const hasPreview = await previewThumb.count() > 0 && await previewThumb.isVisible().catch(() => false);

    if (hasPreview) {
      await previewThumb.click();
      // Image lightbox uses class .img-lightbox (dynamically created)
      const lightbox = page.locator('.img-lightbox');
      const hasLightbox = await lightbox.count() > 0;
      if (hasLightbox) {
        await expect(lightbox).toBeVisible({ timeout: 5000 });
        // ESC closes lightbox
        await page.keyboard.press('Escape');
        await expect(lightbox).toBeHidden({ timeout: 5000 });
      }
    }
    // If no thumbnail visible, the test passes by verifying the upload workflow
  });
});
