import { test } from 'node:test';
import assert from 'node:assert/strict';
import { request } from 'node:http';
import { mkdir, readdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import * as Y from 'yjs';
import { startServer } from '../server.js';
import { connectSocket, temporaryDirectory, until } from './helpers.js';

async function fixture(t) {
  const dataDir = await temporaryDirectory(t);
  let server = await startServer({ port: 0, dataDir });
  t.after(() => server.close());
  return {
    dataDir,
    get port() { return server.port; },
    url(room = 'native') { return `http://127.0.0.1:${server.port}/api/document?room=${encodeURIComponent(room)}`; },
    async get(room = 'native') { return (await fetch(this.url(room))).json(); },
    async put(content, revision, room = 'native') {
      return fetch(this.url(room), { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ content, revision }) });
    },
    async restart() { await server.close(); server = await startServer({ port: 0, dataDir }); },
  };
}

test('native CAS broadcasts to browsers, preserves Unicode and browser offline edits, and restarts durably', async (t) => {
  const app = await fixture(t);
  const browser = await connectSocket(t, app.port, 'native');
  const initial = await app.get();
  const first = await (await app.put('A 🌎\nend', initial.revision)).json();
  await until(() => browser.doc.getText('content').toString() === first.content);
  const offline = new Y.Doc();
  t.after(() => offline.destroy());
  Y.applyUpdate(offline, Y.encodeStateAsUpdate(browser.doc));
  offline.getText('content').insert(offline.getText('content').length, ' offline');
  const second = await (await app.put('B 🌍\nend', first.revision)).json();
  assert.equal(second.content, 'B 🌍\nend');
  await until(() => browser.doc.getText('content').toString() === second.content);
  Y.applyUpdate(browser.doc, Y.encodeStateAsUpdate(offline));
  await browser.save();
  const merged = await app.get();
  assert.equal(merged.content, 'B 🌍\nend offline');
  const unchanged = await (await app.put(merged.content, merged.revision)).json();
  assert.equal(unchanged.revision, merged.revision);
  await app.restart();
  assert.deepEqual(await app.get(), merged);
  assert.notEqual((await app.get('Native')).revision, merged.revision);
  assert.equal((await app.get('Native')).content, '');
});

test('two simultaneous native CAS writes have exactly one winner', async (t) => {
  const app = await fixture(t);
  const base = await app.get();
  const results = await Promise.all([app.put('Alice', base.revision), app.put('Bob', base.revision)]);
  assert.deepEqual(results.map((response) => response.status).sort(), [200, 409]);
  const conflict = await results.find((response) => response.status === 409).json();
  assert.deepEqual(conflict.current, await app.get());
});

test('CAS is checked after a streaming body so a browser edit during upload wins safely', async (t) => {
  const app = await fixture(t);
  const browser = await connectSocket(t, app.port, 'native');
  const base = await app.get();
  const body = JSON.stringify({ content: 'stale native replacement', revision: base.revision });
  let req;
  const completed = new Promise((resolve, reject) => {
    req = request(app.url(), { method: 'PUT', headers: { 'Content-Type': 'application/json' } }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(Buffer.concat(chunks)) }));
    });
    req.on('error', reject);
    req.write(body.slice(0, 20));
  });
  browser.doc.getText('content').insert(0, 'browser edit');
  await browser.save();
  req.end(body.slice(20));
  const result = await completed;
  assert.equal(result.status, 409);
  assert.equal(result.body.current.content, 'browser edit');
  assert.equal((await app.get()).content, 'browser edit');
});

test('revision covers delete-only changes and pending causal updates across restart', async (t) => {
  const app = await fixture(t);
  const browser = await connectSocket(t, app.port, 'native');
  browser.doc.getText('content').insert(0, 'abc');
  await browser.save();
  const base = await app.get();
  const vector = Y.encodeStateVector(browser.doc);
  browser.doc.getText('content').delete(1, 1);
  await browser.save();
  assert.deepEqual(Y.encodeStateVector(browser.doc), vector);
  assert.notEqual((await app.get()).revision, base.revision);
  assert.equal((await app.put('overwrite deletion', base.revision)).status, 409);

  const source = new Y.Doc();
  const updates = [];
  source.on('update', (update) => updates.push(update));
  source.getText('content').insert(0, 'causal');
  source.getText('content').insert(6, ' later');
  const priorPending = await app.get();
  await browser.send(updates[1]);
  const pending = await app.get();
  assert.equal(pending.content, priorPending.content);
  assert.notEqual(pending.revision, priorPending.revision);
  assert.equal(pending.pending, true);
  assert.equal((await app.put('not safe to replace', pending.revision)).status, 409);
  await app.restart();
  assert.deepEqual(await app.get(), pending);
  const fresh = await connectSocket(t, app.port, 'native');
  await fresh.send(updates[0]);
  assert.equal((await app.get()).pending, false);
  source.destroy();
});

test('failed native persistence does not change revision, room state or browser content', async (t) => {
  const app = await fixture(t);
  const empty = await app.get();
  const saved = await (await app.put('saved', empty.revision)).json();
  const browser = await connectSocket(t, app.port, 'native');
  const path = join(app.dataDir, (await readdir(app.dataDir)).find((file) => file.endsWith('.yjs')));
  await mkdir(`${path}.tmp`);
  assert.equal((await app.put('unsaved', saved.revision)).status, 500);
  assert.deepEqual(await app.get(), saved);
  assert.equal(browser.doc.getText('content').toString(), 'saved');
  await rm(`${path}.tmp`, { recursive: true });
  assert.equal((await app.put('retry', saved.revision)).status, 200);
});

test('snapshot validation rejects unconditional/invalid/oversized requests without changing state', async (t) => {
  const app = await fixture(t);
  const base = await app.get();
  assert.equal((await app.put('no revision')).status, 428);
  assert.equal((await app.put(123, base.revision)).status, 400);
  assert.equal((await app.put('\ud800', base.revision)).status, 400);
  assert.equal((await app.put('x'.repeat(1024 * 1024 + 1), base.revision)).status, 413);
  assert.equal((await app.put('x', base.revision, 'bad.room')).status, 400);
  assert.equal((await app.put('x', base.revision, 'native\n')).status, 400);
  const invalid = await fetch(app.url(), { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: '{' });
  assert.equal(invalid.status, 400);
  assert.deepEqual(await app.get(), base);
  assert.equal((await fetch(app.url())).headers.get('Cache-Control'), 'no-store');
});
