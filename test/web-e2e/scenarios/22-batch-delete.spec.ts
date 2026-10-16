import { test, expect } from '@playwright/test';

// 场景 22: 会话批量删除
//
// 覆盖契约：
//   1. 入口按钮进入/退出批量模式（checkbox 出现/消失、操作条显隐）
//   2. 手动勾选若干会话 → 一次确认 → 仅选中项被删除（API 侧 404 复核）
//   3. 「全选」勾选当前列表全部可见会话 → 确认后全部删除
//   4. 确认框点「否」时不删除任何会话
//   5. 回归：批量模式下点击会话行不跳转；退出后单击恢复导航
//   6. Esc 退出批量模式

async function createSessions(request: any, names: string[]): Promise<string[]> {
  const ids: string[] = [];
  for (const name of names) {
    const resp = await request.post('/api/sessions', { data: { name } });
    expect(resp.ok()).toBeTruthy();
    const data = await resp.json();
    const id = data.session?.id || data.id;
    expect(id).toBeTruthy();
    ids.push(id);
  }
  return ids;
}

async function deleteViaApi(request: any, id: string) {
  await request.delete(`/api/sessions/${id}`);
}

test.describe('场景 22: 会话批量删除', () => {
  test('批量模式进入与退出', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#btn-batch-delete')).toBeVisible();

    await page.locator('#btn-batch-delete').click();
    await expect(page.locator('#batch-delete-bar')).toBeVisible();
    await expect(page.locator('#chat-section')).toHaveClass(/batch-mode/);

    // 退出：取消按钮
    await page.locator('#batch-cancel').click();
    await expect(page.locator('#batch-delete-bar')).toBeHidden();
    await expect(page.locator('#chat-section')).not.toHaveClass(/batch-mode/);

    // 再次进入，Esc 退出
    await page.locator('#btn-batch-delete').click();
    await expect(page.locator('#batch-delete-bar')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator('#batch-delete-bar')).toBeHidden();
  });

  test('手动勾选并批量删除', async ({ page, request }) => {
    const [victim1, victim2, survivor] = await createSessions(request, [
      'batch victim 1', 'batch victim 2', 'batch survivor',
    ]);
    try {
      await page.goto('/');
      await expect(page.locator(`.session-item[data-session-id="${victim1}"]`)).toBeVisible({ timeout: 10000 });

      await page.locator('#btn-batch-delete').click();

      // 勾选 victim1 / victim2
      await page.locator(`.session-item[data-session-id="${victim1}"]`).click();
      await page.locator(`.session-item[data-session-id="${victim2}"]`).click();

      // 计数文案显示 2 项
      await expect(page.locator('#batch-count')).toContainText('2');
      // 确认按钮在勾选后才可用
      await expect(page.locator('#batch-confirm')).toBeEnabled();

      await page.locator('#batch-confirm').click();
      await page.locator('#modal-yes').click();

      // 两条从列表消失，幸存者仍在
      await expect(page.locator(`.session-item[data-session-id="${victim1}"]`)).toHaveCount(0, { timeout: 10000 });
      await expect(page.locator(`.session-item[data-session-id="${victim2}"]`)).toHaveCount(0);
      await expect(page.locator(`.session-item[data-session-id="${survivor}"]`)).toBeVisible();

      // 删除完成后自动退出批量模式
      await expect(page.locator('#batch-delete-bar')).toBeHidden();

      // API 复核：被删的 404，幸存者 200
      expect((await request.get(`/api/sessions/${victim1}`)).status()).toBe(404);
      expect((await request.get(`/api/sessions/${victim2}`)).status()).toBe(404);
      expect((await request.get(`/api/sessions/${survivor}`)).ok()).toBeTruthy();
    } finally {
      await deleteViaApi(request, survivor);
    }
  });

  test('全选后批量删除', async ({ page, request }) => {
    const ids = await createSessions(request, ['batch all 1', 'batch all 2']);
    try {
      await page.goto('/');
      await expect(page.locator(`.session-item[data-session-id="${ids[0]}"]`)).toBeVisible({ timeout: 10000 });

      await page.locator('#btn-batch-delete').click();
      await page.locator('#batch-select-all').check();

      // 所有可见行都被勾选
      const boxes = page.locator('#session-list .session-batch-check');
      const total = await boxes.count();
      expect(total).toBeGreaterThanOrEqual(2);
      for (let i = 0; i < total; i++) {
        await expect(boxes.nth(i)).toBeChecked();
      }

      await page.locator('#batch-confirm').click();
      await page.locator('#modal-yes').click();

      for (const id of ids) {
        await expect(page.locator(`.session-item[data-session-id="${id}"]`)).toHaveCount(0, { timeout: 10000 });
      }
    } finally {
      // 兜底清理（若用例失败残留）
      for (const id of ids) await deleteViaApi(request, id);
    }
  });

  test('确认框取消则不删除任何会话', async ({ page, request }) => {
    const [id] = await createSessions(request, ['batch keep me']);
    try {
      await page.goto('/');
      await expect(page.locator(`.session-item[data-session-id="${id}"]`)).toBeVisible({ timeout: 10000 });

      await page.locator('#btn-batch-delete').click();
      await page.locator(`.session-item[data-session-id="${id}"]`).click();
      await page.locator('#batch-confirm').click();
      await page.locator('#modal-no').click();

      // 仍在列表中，且 API 仍可访问
      await expect(page.locator(`.session-item[data-session-id="${id}"]`)).toBeVisible();
      expect((await request.get(`/api/sessions/${id}`)).ok()).toBeTruthy();

      // 批量模式仍然处于激活状态（取消确认 ≠ 退出模式）
      await expect(page.locator('#batch-delete-bar')).toBeVisible();
    } finally {
      await deleteViaApi(request, id);
    }
  });

  test('回归：批量模式不跳转、退出后恢复导航', async ({ page, request }) => {
    const [a, b] = await createSessions(request, ['batch nav A', 'batch nav B']);
    try {
      await page.goto('/');
      await expect(page.locator(`.session-item[data-session-id="${a}"]`)).toBeVisible({ timeout: 10000 });

      // 批量模式下点击行：URL 不变，只是勾选
      const urlBefore = page.url();
      await page.locator('#btn-batch-delete').click();
      await page.locator(`.session-item[data-session-id="${a}"]`).click();
      expect(page.url()).toBe(urlBefore);
      await expect(page.locator(`.session-item[data-session-id="${a}"] .session-batch-check`)).toBeChecked();

      // 退出批量模式后点击 b：正常跳转
      await page.locator('#batch-cancel').click();
      await page.locator(`.session-item[data-session-id="${b}"]`).click();
      await page.waitForURL(new RegExp(`session/${b}`), { timeout: 10000 });
    } finally {
      await deleteViaApi(request, a);
      await deleteViaApi(request, b);
    }
  });

  test('回归：单个删除路径不受影响', async ({ page, request }) => {
    const [id] = await createSessions(request, ['single delete regression']);
    await page.goto('/');
    await expect(page.locator(`.session-item[data-session-id="${id}"]`)).toBeVisible({ timeout: 10000 });

    // 行内 actions 菜单删除（现有契约：逐条确认；按钮 hover 才可见）
    const row = page.locator(`.session-item[data-session-id="${id}"]`);
    await row.hover();
    await row.locator('.session-actions-btn').click();
    await page.locator('.session-actions-menu-item--danger').click();
    await page.locator('#modal-yes').click();

    await expect(page.locator(`.session-item[data-session-id="${id}"]`)).toHaveCount(0, { timeout: 10000 });
    expect((await request.get(`/api/sessions/${id}`)).status()).toBe(404);
  });
});
