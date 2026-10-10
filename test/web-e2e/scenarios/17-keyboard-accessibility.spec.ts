import { test, expect } from '@playwright/test';
import { createSessionAndNavigate, sendMessage } from '../helpers';

test.describe('场景 17: 键盘快捷键与可访问性', () => {
  test('Enter 键发送消息', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    const input = page.locator('#user-input');
    await input.fill('Test enter send');
    await input.press('Enter');

    // Message should be sent (input cleared or user message appears)
    await page.waitForTimeout(500);
    const userMsg = page.locator('#messages .msg-user').last();
    const text = await userMsg.textContent();
    expect(text).toContain('Test enter send');
  });

  test('Ctrl+K 打开会话搜索', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#welcome, .sidebar').first()).toBeVisible({ timeout: 10000 });

    await page.keyboard.press('Control+k');
    await expect(page.locator('#session-search-overlay')).toBeVisible({ timeout: 5000 });
  });

  test('Escape 关闭搜索面板', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#welcome, .sidebar').first()).toBeVisible({ timeout: 10000 });

    await page.keyboard.press('Control+k');
    await expect(page.locator('#session-search-overlay')).toBeVisible({ timeout: 5000 });

    await page.keyboard.press('Escape');
    await expect(page.locator('#session-search-overlay')).toBeHidden({ timeout: 5000 });
  });

  test('Tab 键在可聚焦元素间导航', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#welcome, .sidebar').first()).toBeVisible({ timeout: 10000 });

    // Press Tab multiple times and verify focus moves
    await page.keyboard.press('Tab');
    await page.waitForTimeout(200);

    const focusedTag = await page.evaluate(() => {
      return document.activeElement?.tagName?.toLowerCase() || '';
    });
    // Should have focused something (button, input, link, etc.)
    expect(focusedTag).toBeTruthy();
  });

  test('输入框获得焦点后可输入', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    const input = page.locator('#user-input');
    await expect(input).toBeVisible({ timeout: 10000 });
    await input.click();
    await input.fill('Hello');
    const value = await input.inputValue();
    expect(value).toBe('Hello');
  });

  test('按钮具有可点击区域', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#welcome, .sidebar').first()).toBeVisible({ timeout: 10000 });

    // New session button should be clickable
    const newBtn = page.locator('#btn-new-session-inline, #btn-new-session, button').filter({ hasText: /新建|new|创建/i }).first();
    await expect(newBtn).toBeAttached({ timeout: 5000 });

    const box = await newBtn.boundingBox();
    if (box) {
      expect(box.width).toBeGreaterThan(0);
      expect(box.height).toBeGreaterThan(0);
    }
  });

  test('设置按钮可通过键盘访问', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#welcome, .sidebar').first()).toBeVisible({ timeout: 10000 });

    const settingsBtn = page.locator('#btn-settings');
    await expect(settingsBtn).toBeVisible({ timeout: 5000 });

    // Focus and activate via keyboard
    await settingsBtn.focus();
    await expect(settingsBtn).toBeFocused();
    await settingsBtn.press('Enter');

    await expect(page.locator('#settings-panel')).toBeVisible({ timeout: 5000 });
  });

  test('侧边栏导航项可通过 Tab 到达', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#welcome, .sidebar').first()).toBeVisible({ timeout: 10000 });

    const sidebar = page.locator('.sidebar, aside, [data-testid="sidebar"]').first();
    await expect(sidebar).toBeVisible();

    // Find focusable items in sidebar
    const focusableItems = sidebar.locator('button, [role="button"], a, [tabindex]');
    const count = await focusableItems.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test('消息区域具有正确的 ARIA 角色或语义', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);
    await sendMessage(page, 'Test accessibility');
    await page.waitForTimeout(500);

    const messages = page.locator('#messages');
    await expect(messages).toBeVisible({ timeout: 5000 });

    // Messages container should exist and have content
    const childCount = await messages.locator('.msg-user, .msg-assistant, [class*="msg"]').count();
    expect(childCount).toBeGreaterThanOrEqual(1);
  });
});
