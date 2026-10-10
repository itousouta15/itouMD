import { test, expect } from '@playwright/test';
import { flushLocal } from './helpers.js';

test('readable versions remain downloadable when the server reports damaged snapshots', async ({ page, baseURL }) => {
  await page.route('**/api/versions?*', (route) => route.fulfill({
    status: 200,
    headers: { 'Content-Type': 'application/json', 'X-Skipped-Versions': '2' },
    body: JSON.stringify([{ id: 'readable', createdAt: '2026-10-10T00:00:00Z', text: 'Recovered text', state: 'AAA=' }]),
  }));
  await page.goto(`${baseURL}/?room=version-warning`);
  await expect(page.locator('#versions li')).toHaveCount(1);
  await expect(page.locator('#versions button')).toContainText('14 characters');
  await expect(page.locator('#notice')).toContainText('2 unreadable server version(s) skipped');
  await expect(page.locator('#versions button')).toBeEnabled();
});

test('a failed IndexedDB transaction stops claiming local persistence is working', async ({ page, baseURL }) => {
  const room = `storage-${Date.now()}`;
  await page.goto(`${baseURL}/?room=${room}`);
  await expect(page.locator('#status')).toHaveText('Connected · server saved');
  await page.getByRole('button', { name: 'Go offline', exact: true }).click();
  const editor = page.getByRole('textbox', { name: 'Document text' });
  await editor.fill('Saved locally');
  await flushLocal(page, room);
  await page.evaluate(() => {
    const original = IDBDatabase.prototype.transaction;
    IDBDatabase.prototype.transaction = function (...args) {
      const transaction = original.apply(this, args);
      if (this.name.startsWith('itoumd-prototype-') && args[1] === 'readwrite') {
        IDBDatabase.prototype.transaction = original;
        queueMicrotask(() => transaction.abort());
      }
      return transaction;
    };
  });
  await editor.press('Control+End');
  await page.keyboard.insertText(' unsaved');
  await expect(editor).toHaveText('Saved locally unsaved');
  await expect(page.locator('#local')).toContainText('Local persistence failed');
  await expect(page.locator('#notice')).toContainText('download');
  await expect(page.getByRole('button', { name: 'Download text', exact: true })).toBeEnabled();
  // The aborted edit really was not persisted; the warning is about a genuine reload-loss risk.
  await page.reload();
  await expect(editor).toHaveText('Saved locally');
});
