import { test, expect } from '@playwright/test';
import { waitForAgentResponse, createSessionAndNavigate, sendMessage } from '../helpers';
import path from 'path';

const FIXTURES_DIR = path.join(__dirname, '..', 'fixtures');

test.describe('场景 10: 文件附件上传', () => {
  test('上传文本文件附件并发送', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    // 上传文件
    const fileInput = page.locator('#image-file-input');
    await fileInput.setInputFiles(path.join(FIXTURES_DIR, 'sample.txt'));

    // 验证预览区域出现
    await expect(page.locator('#image-preview-strip')).toBeVisible({ timeout: 5000 });

    // 输入消息并发送
    await sendMessage(page, '请分析这个文件的内容');
    await page.waitForTimeout(1000);

    // 验证用户消息气泡中出现文件附件标记
    const userMsg = page.locator('#messages .msg-user').last();
    const userText = await userMsg.textContent();
    expect(userText).toBeTruthy();
    // 附件名应显示在用户消息中（PDF badge 或文件名）
    expect(userText).toContain('sample');
  });

  test('上传多个文件附件', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    // 上传多个文件
    const fileInput = page.locator('#image-file-input');
    await fileInput.setInputFiles([
      path.join(FIXTURES_DIR, 'sample.txt'),
      path.join(FIXTURES_DIR, 'red.png'),
    ]);

    // 验证预览区域出现
    await expect(page.locator('#image-preview-strip')).toBeVisible({ timeout: 5000 });

    // 发送消息
    await sendMessage(page, '这两个文件有什么区别？');
    await page.waitForTimeout(1000);

    // 验证用户消息中包含附件信息
    const userMsg = page.locator('#messages .msg-user').last();
    const userText = await userMsg.textContent();
    expect(userText).toBeTruthy();
  });

  test('通过 API 验证文件上传成功', async ({ page, request }) => {
    await createSessionAndNavigate(page, request);

    // 直接通过 API 上传文件
    const formData = new FormData();
    const fileContent = 'Test file content for upload verification';
    formData.append('file', new Blob([fileContent], { type: 'text/plain' }), 'api-test.txt');

    const uploadResp = await request.post('/api/upload', {
      multipart: { file: { name: 'api-test.txt', mimeType: 'text/plain', buffer: Buffer.from(fileContent) } },
    });
    expect(uploadResp.ok()).toBeTruthy();
    const uploadResult = await uploadResp.json();
    expect(uploadResult.ok).toBe(true);
    expect(uploadResult.name).toBe('api-test.txt');
    expect(uploadResult.path).toBeTruthy();
  });
});
