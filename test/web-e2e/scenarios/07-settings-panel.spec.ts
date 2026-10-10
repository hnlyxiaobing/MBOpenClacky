import { test, expect } from '@playwright/test';

async function openSettings(page: any) {
  await page.goto('/');
  await expect(page.locator('#welcome, .sidebar, #chat-panel').first()).toBeVisible({ timeout: 15000 });
  await page.locator('#btn-settings').click();
  await expect(page.locator('#settings-panel')).toBeVisible({ timeout: 5000 });
}

test.describe('场景 12: 设置面板', () => {
  test('打开设置面板并显示模型卡片区域', async ({ page }) => {
    await openSettings(page);
    await expect(page.locator('#model-cards')).toBeVisible();
  });

  test('切换语言按钮存在并可点击', async ({ page }) => {
    await openSettings(page);
    await page.locator('#settings-tabs .settings-tab[data-tab="ui"]').click();
    const langSection = page.locator('#language-section');
    await expect(langSection).toBeVisible({ timeout: 5000 });
    const langBtns = langSection.locator('.settings-lang-btn');
    const count = await langBtns.count();
    expect(count).toBeGreaterThanOrEqual(2);
  });

  test('切换字体大小并验证 data-font-size 属性变化', async ({ page }) => {
    await openSettings(page);
    await page.locator('#settings-tabs .settings-tab[data-tab="ui"]').click();
    const fontSection = page.locator('#font-size-section');
    await expect(fontSection).toBeVisible({ timeout: 5000 });
    const fontBtns = fontSection.locator('.settings-lang-btn');

    const initial = await page.evaluate(() =>
      document.documentElement.getAttribute('data-font-size')
    );

    const smallBtn = fontBtns.filter({ has: page.locator('[data-font="small"]') });
    if (await smallBtn.count() > 0) {
      await smallBtn.click();
      const after = await page.evaluate(() =>
        document.documentElement.getAttribute('data-font-size')
      );
      expect(after).toBe('small');
    } else {
      const firstBtn = fontBtns.first();
      const fontValue = await firstBtn.getAttribute('data-font');
      await firstBtn.click();
      const after = await page.evaluate(() =>
        document.documentElement.getAttribute('data-font-size')
      );
      expect(after).toBe(fontValue);
    }
  });

  test('切换主题背景并验证 localStorage 持久化', async ({ page }) => {
    await openSettings(page);
    await page.locator('#settings-tabs .settings-tab[data-tab="ui"]').click();
    const themeSection = page.locator('#bg-theme-section');
    await expect(themeSection).toBeVisible({ timeout: 5000 });
    const themeCards = themeSection.locator('.settings-bg-theme-card');

    const firstTheme = await themeCards.first().getAttribute('data-bg-theme');
    await themeCards.first().click();

    const storedTheme = await page.evaluate(() =>
      localStorage.getItem('clacky-theme')
    );
    const appliedTheme = await page.evaluate(() =>
      document.documentElement.getAttribute('data-theme')
    );
    expect(appliedTheme).toBe(firstTheme);
    if (storedTheme !== null) {
      expect(storedTheme).toBe(firstTheme);
    }
  });

  test('设置面板包含多个 tab 且可切换', async ({ page }) => {
    await openSettings(page);
    const tabs = page.locator('#settings-tabs .settings-tab');
    const count = await tabs.count();
    expect(count).toBeGreaterThanOrEqual(2);

    const firstTab = tabs.first();
    const tabName = await firstTab.getAttribute('data-tab');
    await firstTab.click();

    const activeContent = page.locator(
      `#settings-body .settings-tab-content[data-tab-content="${tabName}"]`
    );
    await expect(activeContent).toBeVisible({ timeout: 3000 });
  });

  test('关于 tab 显示版本号', async ({ page }) => {
    await openSettings(page);
    const aboutTab = page.locator('#settings-tabs .settings-tab[data-tab="about"]');
    if (await aboutTab.isVisible()) {
      await aboutTab.click();
      const versionEl = page.locator('#about-version');
      await expect(versionEl).toBeVisible({ timeout: 5000 });
      const text = await versionEl.textContent();
      expect(text).toMatch(/v?\d+\.\d+/);
    }
  });
});
