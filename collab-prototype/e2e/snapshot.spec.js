import { test, expect } from '@playwright/test';

test('snapshot clients and the real browser editor merge across an offline reconnect', async ({ page, request, baseURL }) => {
  const room = `snapshot-${Date.now()}`;
  const url = `${baseURL}/api/document?room=${room}`;
  const editor = page.getByRole('textbox', { name: 'Document text' });
  await page.goto(`${baseURL}/?room=${room}`);
  await expect(page.locator('#status')).toHaveText('Connected · server saved');
  await editor.fill('Shared\nend');
  await expect(page.locator('#status')).toHaveText('Connected · server saved');
  const base = await (await request.get(url)).json();
  const response = await request.put(url, { data: { content: 'Native\nend', revision: base.revision } });
  expect(response.status()).toBe(200);
  const native = await response.json();
  await expect(editor).toHaveText('Native\nend', { useInnerText: true });
  const rejected = await request.put(url, { data: { content: 'stale replacement', revision: base.revision } });
  expect(rejected.status()).toBe(409);
  await expect(editor).toHaveText('Native\nend', { useInnerText: true });
  await page.getByRole('button', { name: 'Go offline', exact: true }).click();
  await editor.press('Control+End');
  await page.keyboard.insertText(' browser offline');
  const advanced = await request.put(url, { data: { content: 'Server native\nend', revision: native.revision } });
  expect(advanced.status()).toBe(200);
  await page.getByRole('button', { name: 'Reconnect', exact: true }).click();
  await expect(page.locator('#status')).toHaveText('Connected · server saved');
  await expect(editor).toHaveText('Server native\nend browser offline', { useInnerText: true });
  expect((await (await request.get(url)).json()).content).toBe('Server native\nend browser offline');
});
