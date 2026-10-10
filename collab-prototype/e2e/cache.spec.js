import { test, expect } from '@playwright/test';
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { startServer } from '../server.js';
import { flushLocal, waitForOfflineShell } from './helpers.js';

test('non-app navigation cannot replace the offline application shell', async ({ page, context, baseURL }) => {
  const room = `cache-scope-${Date.now()}`;
  await page.goto(`${baseURL}/?room=${room}`);
  await waitForOfflineShell(page);
  await page.getByRole('textbox', { name: 'Document text' }).fill('Kept offline');
  await flushLocal(page, room);
  await page.goto(`${baseURL}/sw.js`);
  await context.setOffline(true);
  await page.goto(`${baseURL}/?room=${room}`);
  await expect(page.getByRole('textbox', { name: 'Document text' })).toHaveText('Kept offline');
});

test('incomplete deployments and HTTP errors preserve a complete cached app', async ({ browser }) => {
  const parent = fileURLToPath(new URL('../test-results/', import.meta.url));
  await mkdir(parent, { recursive: true });
  const directory = await mkdtemp(`${parent}browser-cache-`);
  const distDir = join(directory, 'dist');
  await cp(fileURLToPath(new URL('../dist/', import.meta.url)), distDir, { recursive: true });
  const server = await startServer({ port: 0, dataDir: join(directory, 'data'), distDir });
  const context = await browser.newContext();
  const page = await context.newPage();
  const room = 'deployment';
  const url = `http://127.0.0.1:${server.port}/?room=${room}`;
  const editor = page.getByRole('textbox', { name: 'Document text' });
  try {
    await page.goto(url);
    await waitForOfflineShell(page);
    await editor.fill('Survives rebuild');
    await flushLocal(page, room);
    const indexPath = join(distDir, 'index.html');
    const html = await readFile(indexPath, 'utf8');
    await writeFile(indexPath, html.replace(/\/assets\/[^" ]+\.js/, '/assets/missing-deployment.js'));
    await page.reload();
    await expect(editor).toHaveText('Survives rebuild');
    // The incomplete shell must not have replaced the last fully cached one.
    await context.setOffline(true);
    await page.reload();
    await expect(editor).toHaveText('Survives rebuild');
    await context.setOffline(false);
    await rm(indexPath); // The server returns an HTTP error, not a network exception.
    await page.reload();
    await expect(editor).toHaveText('Survives rebuild');
    // A later complete build must still replace the shell, even if sw.js itself is unchanged.
    const originalScript = html.match(/\/assets\/[^" ]+\.js/)[0];
    const updatedScript = '/assets/updated-build.js';
    await cp(join(distDir, originalScript.slice(1)), join(distDir, updatedScript.slice(1)));
    await rm(join(distDir, originalScript.slice(1)));
    await writeFile(indexPath, html.replace(originalScript, updatedScript).replace(/<title>.*?<\/title>/, '<title>Updated shell</title>'));
    await page.reload();
    await expect(page).toHaveTitle('Updated shell');
    await expect(editor).toHaveText('Survives rebuild');
    await context.setOffline(true);
    await page.reload();
    await expect(page).toHaveTitle('Updated shell');
    await expect(editor).toHaveText('Survives rebuild');
    const cacheNames = await page.evaluate(() => caches.keys());
    const cachedURLs = await page.evaluate(async () => {
      const urls = [];
      for (const name of await caches.keys()) {
        for (const request of await (await caches.open(name)).keys()) urls.push(request.url);
      }
      return urls;
    });
    expect(cacheNames.length).toBeGreaterThan(0);
    expect(cachedURLs.some((url) => url.includes('/api/') || url.includes('/sync'))).toBe(false);
  } finally {
    await context.close();
    await server.close();
    await rm(directory, { recursive: true, force: true });
  }
});
