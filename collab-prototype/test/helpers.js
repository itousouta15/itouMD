import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { WebSocket } from 'ws';
import * as Y from 'yjs';

export async function until(predicate, message = 'condition') {
  const deadline = Date.now() + 6000;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error(`Timed out: ${message}`);
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

export async function temporaryDirectory(t) {
  const parent = fileURLToPath(new URL('../test-results/', import.meta.url));
  await mkdir(parent, { recursive: true });
  const directory = await mkdtemp(`${parent}unit-`);
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

// Raw sockets let tests control delivery without SyncClient retrying rejected updates.
export async function connectSocket(t, port, room) {
  const doc = new Y.Doc();
  const socket = new WebSocket(`ws://127.0.0.1:${port}/sync?room=${room}`);
  let receivedState = false;
  let acknowledgements = 0;
  let closeCode;
  socket.on('error', () => {});
  socket.on('close', (code) => { closeCode = code; });
  socket.on('message', (data, binary) => {
    if (binary) { Y.applyUpdate(doc, data); receivedState = true; }
    else if (data.toString() === 'ack') acknowledgements++;
  });
  t.after(() => { socket.terminate(); doc.destroy(); });
  await until(() => receivedState || closeCode !== undefined, 'initial server state');
  assert.equal(closeCode, undefined, `Room ${room} closed before its handshake`);
  return {
    socket, doc,
    get closeCode() { return closeCode; },
    async send(update) {
      const expected = acknowledgements + 1;
      socket.send(update);
      await until(() => acknowledgements === expected || closeCode !== undefined, 'persisted ACK');
      assert.equal(closeCode, undefined, `Room ${room} rejected a valid update`);
    },
    async save() { await this.send(Y.encodeStateAsUpdate(doc)); },
  };
}
