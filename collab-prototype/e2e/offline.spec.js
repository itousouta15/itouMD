import { test, expect } from '@playwright/test';
import { flushLocal, waitForOfflineShell } from './helpers.js';

test('two isolated browsers edit offline, reload from local storage, reconnect and converge', async ({ browser, baseURL }) => {
  const contexts = await Promise.all([browser.newContext(), browser.newContext()]);
  const pages = await Promise.all(contexts.map((context) => context.newPage()));
  const [a, b] = pages;
  const errors = [];
  pages.forEach((page) => page.on('pageerror', (error) => errors.push(error.message)));
  const room = `browser-${Date.now()}`;
  const editor = (page) => page.getByRole('textbox', { name: 'Document text' });
  try {
    for (const page of pages) {
      await page.goto(`${baseURL}/?room=${room}`);
      await expect(page.locator('#status')).toHaveText('Connected · server saved');
      await waitForOfflineShell(page);
    }
    await editor(a).fill('Shared');
    await expect(editor(b)).toHaveText('Shared');
    for (const page of pages) await page.getByRole('button', { name: 'Go offline', exact: true }).click();
    await editor(a).click();
    await a.keyboard.press('Control+End');
    await a.keyboard.insertText(' Alice');
    await editor(b).click();
    await b.keyboard.press('Control+Home');
    await b.keyboard.insertText('Bob ');
    await expect(editor(a)).toHaveText('Shared Alice');
    await expect(editor(b)).toHaveText('Bob Shared');
    for (const page of pages) await flushLocal(page, room);
    for (const context of contexts) await context.setOffline(true);
    for (const page of pages) await page.reload();
    await expect(editor(a)).toHaveText('Shared Alice');
    await expect(editor(b)).toHaveText('Bob Shared');
    for (const context of contexts) await context.setOffline(false);
    for (const page of pages) await page.getByRole('button', { name: 'Reconnect', exact: true }).click();
    for (const page of pages) {
      await expect(page.locator('#status')).toHaveText('Connected · server saved');
      await expect(editor(page)).toHaveText('Bob Shared Alice');
    }
    await a.getByRole('button', { name: 'Save server version' }).click();
    await expect(a.locator('#versions li')).toHaveCount(1);
    await expect(a.locator('#notice')).toContainText('Version saved');
    await a.reload();
    await expect(editor(a)).toHaveText('Bob Shared Alice');
    await expect(a.locator('#versions li')).toHaveCount(1);
    expect(errors).toEqual([]);
  } finally {
    await Promise.all(contexts.map((context) => context.close()));
  }
});

test('actual network loss, offline reload and room switching recover without manual reconnect', async ({ browser, baseURL }) => {
  const contexts = await Promise.all([browser.newContext(), browser.newContext()]);
  const [a, b] = await Promise.all(contexts.map((context) => context.newPage()));
  const room = `network-${Date.now()}`;
  const editor = (page) => page.getByRole('textbox', { name: 'Document text' });
  const errors = [];
  for (const page of [a, b]) page.on('pageerror', (error) => errors.push(error.message));
  try {
    for (const page of [a, b]) {
      await page.goto(`${baseURL}/?room=${room}`);
      await expect(page.locator('#status')).toHaveText('Connected · server saved');
      await waitForOfflineShell(page);
    }
    await editor(a).fill('Shared');
    await expect(editor(b)).toHaveText('Shared');
    await Promise.all(contexts.map((context) => context.setOffline(true)));
    for (const page of [a, b]) {
      await expect(page.locator('#status')).toContainText('editing locally');
      await expect(page.locator('#snapshot')).toBeDisabled();
    }
    await editor(a).press('Control+End');
    await a.keyboard.insertText(' Alice');
    await editor(b).press('Control+Home');
    await b.keyboard.insertText('Bob ');
    await flushLocal(a, room);
    await flushLocal(b, room);
    // A new room must not pick up the previous room's IndexedDB data or cached URL.
    await a.goto(`${baseURL}/?room=${room}-other`);
    await expect(editor(a)).toHaveText('');
    await editor(a).fill('Separate local room');
    await flushLocal(a, `${room}-other`);
    await a.goto(`${baseURL}/?room=${room}`);
    await b.reload();
    await expect(editor(a)).toHaveText('Shared Alice');
    await expect(editor(b)).toHaveText('Bob Shared');
    await Promise.all(contexts.map((context) => context.setOffline(false)));
    for (const page of [a, b]) {
      await expect(page.locator('#status')).toHaveText('Connected · server saved');
      await expect(editor(page)).toHaveText('Bob Shared Alice');
    }
    await a.goto(`${baseURL}/?room=${room}-other`);
    await expect(editor(a)).toHaveText('Separate local room');
    expect(errors).toEqual([]);
  } finally {
    await Promise.all(contexts.map((context) => context.close()));
  }
});
