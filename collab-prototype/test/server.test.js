import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { connect } from 'node:net';
import { WebSocket } from 'ws';
import * as Y from 'yjs';
import { startServer } from '../server.js';
import { SyncClient } from '../src/sync.js';
import { connectSocket, temporaryDirectory, until } from './helpers.js';

async function fixture(t) {
  const dataDir = await temporaryDirectory(t);
  let server = await startServer({ port: 0, dataDir });
  t.after(() => server.close());
  return {
    dataDir,
    get port() { return server.port; },
    async restart() { await server.close(); server = await startServer({ port: 0, dataDir }); },
    async version(room) {
      const response = await fetch(`http://127.0.0.1:${server.port}/api/versions?room=${room}`, { method: 'POST' });
      assert.equal(response.status, 201);
      return response.json();
    },
  };
}

test('case-sensitive room names and Windows device names remain isolated across restart', async (t) => {
  const app = await fixture(t);
  const names = ['CaseRoom', 'caseroom', 'CON', 'aux'];
  for (const name of names) {
    const client = await connectSocket(t, app.port, name);
    assert.equal(client.doc.getText('content').toString(), '');
    client.doc.getText('content').insert(0, `Only ${name}`);
    await client.save();
    assert.equal((await app.version(name)).text, `Only ${name}`);
    client.socket.close();
  }
  await app.restart();
  for (const name of names) {
    const fresh = await connectSocket(t, app.port, name);
    assert.equal(fresh.doc.getText('content').toString(), `Only ${name}`);
    const versions = await (await fetch(`http://127.0.0.1:${app.port}/api/versions?room=${name}`)).json();
    assert.equal(versions.length, 1);
    assert.equal(versions[0].text, `Only ${name}`);
  }
});

test('a malformed Yjs update cannot leak a partially applied edit into the room', async (t) => {
  const app = await fixture(t);
  const client = await connectSocket(t, app.port, 'invalid');
  client.doc.getText('content').insert(0, 'saved');
  await client.save();
  client.doc.getText('content').insert(5, ' corrupt');
  const malformed = Y.encodeStateAsUpdate(client.doc).slice(0, -1); // Missing delete-set length, after valid structs.
  client.socket.send(malformed);
  await until(() => client.closeCode !== undefined, 'invalid update rejection');
  assert.equal((await app.version('invalid')).text, 'saved');
  const fresh = await connectSocket(t, app.port, 'invalid');
  assert.equal(fresh.doc.getText('content').toString(), 'saved');
  fresh.doc.getText('content').insert(5, ' healthy');
  await fresh.save();
  await app.restart();
  assert.equal((await app.version('invalid')).text, 'saved healthy');
});

test('a failed state write leaves memory, handshakes, versions and disk at the last saved state', async (t) => {
  const app = await fixture(t);
  const client = await connectSocket(t, app.port, 'failure');
  client.doc.getText('content').insert(0, 'saved');
  await client.save();
  const path = join(app.dataDir, (await readdir(app.dataDir)).find((name) => name.endsWith('.yjs')));
  const saved = await readFile(path);
  // A directory at the temporary-file path reliably simulates a write failure on Windows and Unix.
  await mkdir(`${path}.tmp`);
  client.doc.getText('content').insert(5, ' retry me');
  client.socket.send(Y.encodeStateAsUpdate(client.doc));
  await until(() => client.closeCode !== undefined, 'failed write rejection');
  assert.deepEqual(await readFile(path), saved);
  assert.equal((await app.version('failure')).text, 'saved');
  const fresh = await connectSocket(t, app.port, 'failure');
  assert.equal(fresh.doc.getText('content').toString(), 'saved');
  await rm(`${path}.tmp`, { recursive: true });
  // A reconnect's full-state update must recover the rejected local change.
  Y.applyUpdate(fresh.doc, Y.encodeStateAsUpdate(client.doc));
  await fresh.save();
  await app.restart();
  assert.equal((await app.version('failure')).text, 'saved retry me');
});

test('legacy room state and versions survive loading with exact-case names', async (t) => {
  const app = await fixture(t);
  const doc = new Y.Doc();
  doc.getText('content').insert(0, 'existing document');
  await writeFile(join(app.dataDir, 'Legacy.yjs'), Y.encodeStateAsUpdate(doc));
  const legacyVersion = { id: 'old', createdAt: new Date().toISOString(), text: doc.getText('content').toString(), state: Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64') };
  doc.destroy();
  await mkdir(join(app.dataDir, 'Legacy-versions'));
  await writeFile(join(app.dataDir, 'Legacy-versions', 'old.json'), JSON.stringify(legacyVersion));
  // On a case-insensitive filesystem this must not claim Legacy's existing files.
  const differentRoom = await connectSocket(t, app.port, 'legacy');
  assert.equal(differentRoom.doc.getText('content').toString(), '');
  const client = await connectSocket(t, app.port, 'Legacy');
  assert.equal(client.doc.getText('content').toString(), 'existing document');
  const versions = await (await fetch(`http://127.0.0.1:${app.port}/api/versions?room=Legacy`)).json();
  assert.deepEqual(versions, [legacyVersion]);
  await app.restart();
  assert.equal((await app.version('Legacy')).text, 'existing document');
});

test('a corrupt state file is rejected without being overwritten or affecting other rooms', async (t) => {
  const app = await fixture(t);
  const corrupt = Buffer.from([255]);
  const path = join(app.dataDir, 'broken.yjs');
  await writeFile(path, corrupt);
  const response = await fetch(`http://127.0.0.1:${app.port}/api/versions?room=broken`, { method: 'POST' });
  assert.equal(response.status, 500);
  assert.deepEqual(await readFile(path), corrupt);
  const healthy = await connectSocket(t, app.port, 'healthy');
  healthy.doc.getText('content').insert(0, 'still works');
  await healthy.save();
});

test('corrupt snapshots do not hide readable versions and remain available for manual repair', async (t) => {
  const app = await fixture(t);
  const client = await connectSocket(t, app.port, 'history');
  client.doc.getText('content').insert(0, 'recoverable history');
  await client.save();
  const version = await app.version('history');
  const directory = join(app.dataDir, (await readdir(app.dataDir)).find((name) => name.endsWith('-versions')));
  await writeFile(join(directory, 'truncated.json'), '{');
  await writeFile(join(directory, 'invalid-shape.json'), 'null');
  await app.restart();
  const response = await fetch(`http://127.0.0.1:${app.port}/api/versions?room=history`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('X-Skipped-Versions'), '2');
  assert.deepEqual(await response.json(), [version]);
  assert.equal(await readFile(join(directory, 'truncated.json'), 'utf8'), '{');
  assert.equal((await app.version('history')).text, 'recoverable history');
});

test('pending causal updates and deletes survive staging, restart and duplicate delivery', async (t) => {
  const app = await fixture(t);
  const source = new Y.Doc();
  t.after(() => source.destroy());
  const updates = [];
  source.on('update', (update) => updates.push(update));
  source.getText('content').insert(0, 'abc');
  source.getText('content').insert(3, 'def');
  source.getText('content').delete(1, 2);
  const sender = await connectSocket(t, app.port, 'causal');
  await sender.send(updates[2]); // Delete before its insertion exists.
  await sender.send(updates[1]); // Struct depending on a missing earlier struct.
  await app.restart();
  const fresh = await connectSocket(t, app.port, 'causal');
  assert.equal(fresh.doc.getText('content').toString(), '');
  await fresh.send(updates[0]);
  for (const update of [...updates].reverse().concat(updates)) await fresh.send(update);
  const observer = await connectSocket(t, app.port, 'causal');
  assert.equal(observer.doc.getText('content').toString(), 'adef');
  assert.deepEqual(Y.encodeStateVector(observer.doc), Y.encodeStateVector(source));
  assert.equal((await app.version('causal')).text, 'adef');
});

test('healthy real sockets answer heartbeats without reconnecting', async (t) => {
  const app = await fixture(t);
  const doc = new Y.Doc();
  const client = new SyncClient(doc, `ws://127.0.0.1:${app.port}/sync?room=heartbeat`, {
    WebSocketImpl: WebSocket, heartbeatMs: 20, timeoutMs: 1000,
  });
  t.after(() => { client.destroy(); doc.destroy(); });
  client.connect();
  const socket = client.socket;
  let pongs = 0;
  socket.on('message', (data, binary) => { if (!binary && data.toString() === 'pong') pongs++; });
  await until(() => pongs >= 3, 'heartbeat replies');
  assert.equal(client.socket, socket);
  doc.getText('content').insert(0, 'still connected');
  await until(() => client.pending === 0, 'edit after heartbeats');
  assert.equal((await app.version('heartbeat')).text, 'still connected');
});

test('unsupported text, malformed UTF-8 and oversized frames close only the sending socket', async (t) => {
  const app = await fixture(t);
  const cases = [
    { data: 'not a ping', code: 1003 },
    { data: Buffer.from([255]), options: { binary: false }, code: 1007 },
    { data: Buffer.alloc(4 * 1024 * 1024 + 1), code: 1009 },
  ];
  for (const { data, options, code } of cases) {
    const client = await connectSocket(t, app.port, 'frames');
    client.socket.send(data, options);
    await until(() => client.closeCode !== undefined, 'frame rejection');
    assert.equal(client.closeCode, code);
  }
  assert.equal((await app.version('frames')).text, '');
});

test('a malformed WebSocket upgrade URL cannot crash the server process', async (t) => {
  const dataDir = await temporaryDirectory(t);
  const child = spawn(process.execPath, ['--input-type=module', '-e',
    'import { startServer } from "./server.js"; const app = await startServer({ port: 0, dataDir: process.argv[1] }); process.send(app.port);', dataDir], {
    cwd: fileURLToPath(new URL('../', import.meta.url)), stdio: ['ignore', 'pipe', 'pipe', 'ipc'],
  });
  let output = '';
  child.stderr.on('data', (data) => { output += data; });
  const exited = new Promise((resolve) => child.once('exit', resolve));
  t.after(async () => { child.kill(); await exited; });
  const port = await new Promise((resolve, reject) => {
    child.once('message', resolve);
    child.once('error', reject);
    child.once('exit', () => reject(new Error(output || 'Server exited before listening')));
  });
  const socket = connect(port, '127.0.0.1');
  socket.on('error', () => {});
  const closed = new Promise((resolve) => socket.once('close', resolve));
  await new Promise((resolve) => socket.once('connect', resolve));
  socket.write('GET //[ HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n');
  await closed;
  assert.equal(child.exitCode, null, output);
  const response = await fetch(`http://127.0.0.1:${port}/api/versions?room=healthy`);
  assert.equal(response.status, 200, output);
});
