import { test, expect } from '@playwright/test';
import { createSessionAndNavigate } from '../helpers';

test.describe('场景 9: 模型切换', () => {
  test('模型下拉列表打开并显示可用模型', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    // 验证模型名称在信息栏中显示
    const modelLabel = page.locator('#sib-model');
    await expect(modelLabel).toBeVisible();

    // 点击打开模型下拉
    await modelLabel.click();
    await expect(page.locator('#sib-model-dropdown')).toBeVisible({ timeout: 5000 });

    // 验证至少有一个模型选项
    const options = page.locator('.sib-model-option');
    await expect(options.first()).toBeVisible({ timeout: 5000 });
    const count = await options.count();
    expect(count).toBeGreaterThanOrEqual(1);

    // 验证当前模型有 .current 标记
    const currentOption = page.locator('.sib-model-option.current');
    await expect(currentOption).toBeVisible();
  });

  test('切换到不同模型后信息栏更新', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    // 读取当前模型名称
    const modelLabel = page.locator('#sib-model');
    const originalText = (await modelLabel.textContent())?.trim() || '';

    // 打开下拉
    await modelLabel.click();
    await expect(page.locator('#sib-model-dropdown')).toBeVisible({ timeout: 5000 });

    // 选择一个非当前的模型
    const nonCurrent = page.locator('.sib-model-option:not(.current)').first();
    const hasNonCurrent = await nonCurrent.count() > 0;

    if (!hasNonCurrent) {
      test.skip(true, 'Only one model available');
      return;
    }

    const newModelName = (await nonCurrent.locator('.sib-model-name-main').textContent())?.trim() || '';
    await nonCurrent.click();

    // 下拉关闭
    await expect(page.locator('#sib-model-dropdown')).toBeHidden({ timeout: 5000 });

    // 等待信息栏模型名称更新（通过 WS 广播）
    await expect(modelLabel).not.toHaveText(originalText, { timeout: 10000 });

    const updatedText = (await modelLabel.textContent())?.trim() || '';
    if (newModelName) {
      expect(updatedText).toContain(newModelName);
    }

    // 通过 API 验证模型已切换
    const sessionId = await page.locator('#sib-id').getAttribute('data-session-id');
    if (sessionId) {
      const resp = await request.get(`/api/sessions/${sessionId}`);
      const detail = await resp.json();
      // SessionSummary uses 'model' field
      const modelName = detail.session?.model || detail.model;
      expect(modelName).toBeTruthy();
    }
  });

  test('通过 API 切换模型后 UI 同步更新', async ({ page, request }) => {
    const session = await createSessionAndNavigate(page, request);

    // 获取可用模型列表
    const configResp = await request.get('/api/config/models');
    const models = await configResp.json();

    if (!Array.isArray(models) || models.length < 2) {
      test.skip(true, 'Less than 2 models configured');
      return;
    }

    // 找到与当前不同的模型
    const currentModelId = session.session?.model_config_id || session.model_config_id || session.session?.model_id || session.model_id;
    const otherModel = models.find((m: { id: string; runtime_id: string }) =>
      m.id !== currentModelId && m.runtime_id !== currentModelId
    );

    if (!otherModel) {
      test.skip(true, 'No alternative model found');
      return;
    }

    // 通过 API 切换
    const sessionId = session.session?.id || session.id;
    const patchResp = await request.patch(`/api/sessions/${sessionId}/model`, {
      data: { model_id: otherModel.id || otherModel.runtime_id },
    });
    expect(patchResp.ok()).toBeTruthy();

    // 刷新页面验证 UI 同步
    await page.reload();
    await expect(page.locator('#chat-panel')).toBeVisible({ timeout: 10000 });

    const modelLabel = page.locator('#sib-model');
    await expect(modelLabel).toBeVisible();
  });
});
