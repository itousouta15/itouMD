import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as Y from 'yjs';
import { SyncClient } from '../src/sync.js';
import { until } from './helpers.js';

function fixture(t, options = {}) {
  const sockets = [];
  const statuses = [];
  class Socket {
    readyState = 0;
    sent = [];
    constructor() { sockets.push(this); }
    send(data) { this.sent.push(data); }
    open() { this.readyState = 1; this.onopen?.(); }
    receive(data) { this.onmessage?.({ data }); }
    close() { this.readyState = 3; this.onclose?.(); }
  }
  const doc = new Y.Doc();
  const client = new SyncClient(doc, 'ws://local/sync?room=test', {
    WebSocketImpl: Socket, onStatus: (status) => statuses.push(status), ...options,
  });
  t.after(() => { client.destroy(); doc.destroy(); });
  client.connect();
  return { doc, client, sockets, statuses };
}

test('a saved status waits for every outstanding update ACK', (t) => {
  const { doc, sockets, statuses } = fixture(t);
  const socket = sockets[0];
  socket.open();
  doc.getText('content').insert(0, 'one');
  doc.getText('content').insert(3, 'two');
  socket.receive('ack'); // Only the initial full-state handshake is saved.
  assert.equal(statuses.at(-1), 'Syncing…');
  socket.receive('ack');
  assert.equal(statuses.at(-1), 'Syncing…');
  socket.receive('ack');
  assert.equal(statuses.at(-1), 'Connected · server saved');
});

test('events from a replaced socket cannot acknowledge or change the new session', (t) => {
  const { doc, client, sockets, statuses } = fixture(t);
  const old = sockets[0];
  old.open();
  old.readyState = 2; // A connection can be closing before its close event arrives.
  client.connect();
  sockets[1].open();
  const foreign = new Y.Doc();
  foreign.getText('content').insert(0, 'stale data');
  old.receive(Y.encodeStateAsUpdate(foreign));
  old.receive('ack');
  foreign.destroy();
  assert.equal(doc.getText('content').toString(), '');
  assert.equal(statuses.at(-1), 'Syncing…');
  sockets[1].receive('ack');
  assert.equal(statuses.at(-1), 'Connected · server saved');
});

test('a silent network failure reconnects and resends edits without a close event', async (t) => {
  const { doc, sockets, statuses } = fixture(t, { retryMs: 10, heartbeatMs: 20, timeoutMs: 40 });
  sockets[0].open();
  sockets[0].receive('ack');
  doc.getText('content').insert(0, 'lost on the wire');
  // Neither ACK nor pong nor close arrives from the failed network.
  await until(() => sockets.length > 1, 'heartbeat reconnect');
  sockets[1].open();
  const restored = new Y.Doc();
  Y.applyUpdate(restored, sockets[1].sent[0]);
  assert.equal(restored.getText('content').toString(), 'lost on the wire');
  restored.destroy();
  sockets[1].receive('ack');
  assert.equal(statuses.at(-1), 'Connected · server saved');
});

test('a connection stuck opening times out and manual disconnect stops retries', async (t) => {
  const { client, sockets } = fixture(t, { retryMs: 10, heartbeatMs: 20, timeoutMs: 40 });
  await until(() => sockets.length > 1, 'connection timeout');
  client.disconnect();
  const count = sockets.length;
  await new Promise((resolve) => setTimeout(resolve, 100));
  assert.equal(sockets.length, count);
});
