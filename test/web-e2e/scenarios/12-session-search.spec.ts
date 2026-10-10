import { test, expect } from '@playwright/test';
import { createSessionAndNavigate, sendMessage, waitForAgentResponse } from '../helpers';

async function openSearch(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  // Open search via Ctrl+K
  await page.keyboard.press('Control+k');
  await expect(page.locator('#session-search-overlay')).toBeVisible({ timeout: 5000 });
}

test.describe('场景 12: 会话搜索与命令面板', () => {
  test('Ctrl+K 打开搜索面板', async ({ page }) => {
    await openSearch(page);
  });

  test('搜索面板包含搜索输入框', async ({ page }) => {
    await openSearch(page);
    const searchInput = page.locator('#session-search-q');
    await expect(searchInput).toBeVisible();
  });

  test('搜索面板包含类型过滤器', async ({ page }) => {
    await openSearch(page);
    const typeSelect = page.locator('#session-search-type');
    await expect(typeSelect).toBeVisible();
    // Verify it has options
    const options = typeSelect.locator('option');
    const count = await options.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test('Escape 关闭搜索面板', async ({ page }) => {
    await openSearch(page);
    await page.keyboard.press('Escape');
    await expect(page.locator('#session-search-overlay')).toBeHidden({ timeout: 5000 });
  });

  test('点击搜索面板外部区域关闭', async ({ page }) => {
    await openSearch(page);
    // Click on the overlay background (not the search box)
    await page.locator('#session-search-overlay').click({ position: { x: 10, y: 10 } });
    await expect(page.locator('#session-search-overlay')).toBeHidden({ timeout: 5000 });
  });

  test('输入搜索词后显示结果', async ({ page, request }) => {
    // Create a session with a known name
    await request.post('/api/sessions', {
      data: { name: 'Phoenix Test Session' },
    });

    await openSearch(page);
    const searchInput = page.locator('#session-search-q');
    await searchInput.fill('Phoenix');

    // Wait for debounced search to trigger
    await page.waitForTimeout(500);

    // Results should appear
    const results = page.locator('#session-search-results');
    await expect(results).toBeVisible({ timeout: 5000 });
  });

  test('清除搜索按钮在输入后显示', async ({ page }) => {
    await openSearch(page);
    const searchInput = page.locator('#session-search-q');
    await searchInput.fill('test');

    const clearBtn = page.locator('#btn-search-q-clear');
    await expect(clearBtn).toBeVisible({ timeout: 3000 });
  });

  test('点击清除按钮清空搜索', async ({ page }) => {
    await openSearch(page);
    const searchInput = page.locator('#session-search-q');
    await searchInput.fill('test');

    const clearBtn = page.locator('#btn-search-q-clear');
    await clearBtn.click();

    const value = await searchInput.inputValue();
    expect(value).toBe('');
  });
});
