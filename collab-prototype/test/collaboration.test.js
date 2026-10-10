import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as Y from 'yjs';
import { WebSocket } from 'ws';
import { SyncClient } from '../src/sync.js';
import { startServer } from '../server.js';
import { temporaryDirectory, until } from './helpers.js';

test('Yjs converges after offline insert/delete, duplicate and reverse causal delivery', () => {
  const seed = new Y.Doc();
  seed.getText('content').insert(0, 'shared base');
  const clients = [new Y.Doc(), new Y.Doc()];
  const updates = [];
  for (const doc of clients) {
    Y.applyUpdate(doc, Y.encodeStateAsUpdate(seed));
    doc.on('update', (update, origin) => { if (origin !== 'delivery') updates.push(update); });
  }
  const [a, b] = clients.map((doc) => doc.getText('content'));
  a.insert(0, 'Alice ');
  a.insert(6, 'offline ');
  a.delete(14, 7);
  b.insert(b.length, ' Bob');
  b.insert(b.length, ' offline 🌍');
  b.delete(0, 6);
  for (const doc of clients) for (const update of [...updates].reverse().concat(updates, updates)) Y.applyUpdate(doc, update, 'delivery');
  assert.equal(a.toString(), b.toString());
  assert.match(a.toString(), /Alice offline/);
  assert.match(a.toString(), /Bob offline 🌍/);
  assert.deepEqual(Y.encodeStateVector(clients[0]), Y.encodeStateVector(clients[1]));
  for (const doc of [seed, ...clients]) doc.destroy();
});

test('real sockets: offline merge, automatic reconnect, room isolation, durable restart and versions', async (t) => {
  const dataDir = await temporaryDirectory(t);
  let server = await startServer({ port: 0, dataDir });
  const port = server.port;
  const docs = [new Y.Doc(), new Y.Doc(), new Y.Doc()];
  const statuses = [];
  const clients = docs.map((doc, i) => new SyncClient(doc, `ws://127.0.0.1:${port}/sync?room=${i === 2 ? 'other' : 'demo'}`, { WebSocketImpl: WebSocket, retryMs: 50, onStatus: (status) => { statuses[i] = status; } }));
  t.after(async () => {
    for (const client of clients) client.destroy();
    for (const doc of docs) doc.destroy();
    await server.close();
  });
  clients.forEach((client) => client.connect());
  await until(() => statuses.filter((status) => status?.startsWith('Connected')).length === 3);
  const [a, b, other] = docs.map((doc) => doc.getText('content'));
  a.insert(0, 'base');
  await until(() => b.toString() === 'base');
  clients[0].disconnect();
  clients[1].disconnect();
  a.insert(0, 'Alice ');
  b.insert(b.length, ' Bob');
  b.delete(0, 1);
  assert.notEqual(a.toString(), b.toString());
  clients[1].connect();
  clients[0].connect();
  await until(() => a.toString() === b.toString() && statuses[0].startsWith('Connected') && statuses[1].startsWith('Connected'));
  assert.equal(a.toString(), 'Alice ase Bob');
  assert.equal(other.toString(), '');
  const response = await fetch(`http://127.0.0.1:${port}/api/versions?room=demo`, { method: 'POST' });
  assert.equal(response.status, 201);
  const version = await response.json();
  assert.equal(version.text, a.toString());
  const restored = new Y.Doc();
  Y.applyUpdate(restored, Buffer.from(version.state, 'base64'));
  assert.equal(restored.getText('content').toString(), a.toString());
  restored.destroy();
  await server.close();
  await until(() => statuses[0].includes('unavailable'));
  a.insert(a.length, ' after outage');
  b.insert(0, 'reconnect ');
  server = await startServer({ port, dataDir });
  await until(() => a.toString() === b.toString() && statuses[0].startsWith('Connected') && statuses[1].startsWith('Connected'));
  assert.match(a.toString(), /after outage/);
  assert.match(a.toString(), /reconnect/);
  const versions = await (await fetch(`http://127.0.0.1:${port}/api/versions?room=demo`)).json();
  assert.equal(versions[0].text, version.text);
  const expected = a.toString();
  clients.forEach((client) => client.disconnect());
  await server.close();
  server = await startServer({ port, dataDir });
  const fresh = new Y.Doc();
  const freshClient = new SyncClient(fresh, `ws://127.0.0.1:${port}/sync?room=demo`, { WebSocketImpl: WebSocket });
  try {
    freshClient.connect();
    await until(() => fresh.getText('content').toString() === expected, 'fresh client recovers disk state');
  } finally { freshClient.destroy(); fresh.destroy(); }
});
