import { createServer } from 'node:http';
import { existsSync, mkdirSync, readFileSync, writeFileSync, renameSync, readdirSync } from 'node:fs';
import { dirname, extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, randomUUID } from 'node:crypto';
import { WebSocketServer } from 'ws';
import * as Y from 'yjs';

const root = dirname(fileURLToPath(import.meta.url));
const validRoom = (room) => typeof room === 'string' && room.length >= 1 && room.length <= 64 && !/[^a-zA-Z0-9_-]/.test(room);
function atomicWrite(path, data) {
  writeFileSync(`${path}.tmp`, data);
  renameSync(`${path}.tmp`, path);
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size <= 4 * 1024 * 1024) chunks.push(chunk);
  }
  if (size > 4 * 1024 * 1024) throw Object.assign(new Error('Request too large'), { status: 413 });
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); }
  catch { throw Object.assign(new Error('Invalid JSON'), { status: 400 }); }
}

// Preserve unchanged Y.Text items (and browser cursor/undo anchors). Indices are UTF-16;
// never split a surrogate pair when the two emoji share only their first code unit.
function replaceText(text, next) {
  const prior = text.toString();
  let start = 0;
  while (start < prior.length && start < next.length && prior[start] === next[start]) start++;
  const splitsPair = (value, at) => at > 0 && /[\uD800-\uDBFF]/.test(value[at - 1]) && /[\uDC00-\uDFFF]/.test(value[at] || '');
  if (splitsPair(prior, start) || splitsPair(next, start)) start--;
  let tail = 0;
  while (tail < prior.length - start && tail < next.length - start && prior[prior.length - 1 - tail] === next[next.length - 1 - tail]) tail++;
  if (splitsPair(prior, prior.length - tail) || splitsPair(next, next.length - tail)) tail--;
  text.doc.transact(() => {
    const removed = prior.length - start - tail;
    if (removed) text.delete(start, removed);
    const inserted = next.slice(start, next.length - tail);
    if (inserted) text.insert(start, inserted);
  });
}

export async function startServer({ port = 8787, host = '127.0.0.1', dataDir = resolve(root, 'data'), distDir = resolve(root, 'dist') } = {}) {
  mkdirSync(dataDir, { recursive: true });
  const rooms = new Map();
  // Hex preserves case on Windows; '~' keeps this namespace distinct from legacy room names.
  const storagePath = (name, suffix) => resolve(dataDir, `room~${Buffer.from(name, 'utf8').toString('hex')}${suffix}`);
  function legacyPath(name, suffix) {
    const filename = `${name}${suffix}`;
    return readdirSync(dataDir).includes(filename) ? resolve(dataDir, filename) : null;
  }
  function versionDirectory(name) {
    const path = storagePath(name, '-versions');
    const legacy = !existsSync(path) && legacyPath(name, '-versions');
    if (legacy) renameSync(legacy, path);
    return path;
  }
  function getRoom(name) {
    if (!rooms.has(name)) {
      const doc = new Y.Doc();
      const path = storagePath(name, '.yjs');
      const legacy = !existsSync(path) && legacyPath(name, '.yjs');
      try {
        if (existsSync(legacy || path)) Y.applyUpdate(doc, readFileSync(legacy || path));
        // Only migrate a legacy file after successfully decoding it. Never claim a case-only alias.
        if (legacy) renameSync(legacy, path);
      } catch (error) { doc.destroy(); throw error; }
      rooms.set(name, { doc, path, sockets: new Set() });
    }
    return rooms.get(name);
  }
  function snapshot(name, room) {
    const content = room.doc.getText('content').toString();
    // A state vector alone misses delete-only and buffered out-of-order changes.
    const revision = createHash('sha256').update(name).update('\0').update(Y.encodeStateAsUpdate(room.doc)).digest('hex');
    return { room: name, content, revision, pending: Boolean(room.doc.store.pendingStructs || room.doc.store.pendingDs) };
  }
  function commitRoom(room, change, sender = null, receivedUpdate = null) {
    const candidate = new Y.Doc();
    let update;
    try {
      Y.applyUpdate(candidate, Y.encodeStateAsUpdate(room.doc));
      change(candidate);
      update = receivedUpdate || Y.encodeStateAsUpdate(candidate, Y.encodeStateVector(room.doc));
      atomicWrite(room.path, Y.encodeStateAsUpdate(candidate));
    } catch (error) { candidate.destroy(); throw error; }
    const previous = room.doc;
    room.doc = candidate;
    previous.destroy();
    for (const peer of room.sockets) if (peer !== sender && peer.readyState === 1) peer.send(update);
  }
  const server = createServer(async (req, res) => {
    const json = (status, value) => { res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(value)); };
    try {
      const url = new URL(req.url, 'http://localhost');
      if (url.pathname === '/api/document') {
        const name = url.searchParams.get('room');
        if (!validRoom(name)) return json(400, { error: 'Invalid document name' });
        if (req.method === 'GET') return json(200, snapshot(name, getRoom(name)));
        if (req.method !== 'PUT') return json(405, { error: 'Method not allowed' });
        if (req.headers['content-type']?.split(';')[0].trim() !== 'application/json') return json(415, { error: 'JSON required' });
        const body = await readJson(req);
        if (!body || typeof body !== 'object' || Array.isArray(body)) return json(400, { error: 'Invalid document' });
        if (typeof body.revision !== 'string' || !body.revision) return json(428, { error: 'Revision required' });
        if (typeof body.content !== 'string' || !body.content.isWellFormed()) return json(400, { error: 'Valid text required' });
        if (Buffer.byteLength(body.content, 'utf8') > 1024 * 1024) return json(413, { error: 'Snapshot text exceeds 1 MiB' });
        // No await between this CAS check and the shared staged commit. Browser updates can
        // arrive while the body is streaming, so checking before readJson would lose edits.
        const room = getRoom(name);
        const current = snapshot(name, room);
        if (current.revision !== body.revision || current.pending) {
          return json(409, { error: current.pending ? 'Causal updates pending' : 'Revision changed', current });
        }
        if (body.content !== current.content) commitRoom(room, (doc) => replaceText(doc.getText('content'), body.content));
        return json(200, snapshot(name, room));
      }
      if (url.pathname === '/api/versions') {
        const name = url.searchParams.get('room');
        if (!validRoom(name)) return json(400, { error: 'Invalid document name' });
        const directory = versionDirectory(name);
        if (req.method === 'POST') {
          const { doc } = getRoom(name);
          const id = `${Date.now()}-${randomUUID()}`;
          const version = { id, createdAt: new Date().toISOString(), text: doc.getText('content').toString(), state: Buffer.from(Y.encodeStateAsUpdate(doc)).toString('base64') };
          mkdirSync(directory, { recursive: true });
          atomicWrite(resolve(directory, `${id}.json`), JSON.stringify(version));
          return json(201, version);
        }
        if (req.method !== 'GET') return json(405, { error: 'Method not allowed' });
        const versions = [];
        let skipped = 0;
        const files = existsSync(directory) ? readdirSync(directory).filter((file) => file.endsWith('.json')).sort().reverse() : [];
        for (const file of files) {
          try {
            const version = JSON.parse(readFileSync(resolve(directory, file), 'utf8'));
            if (!version || !['id', 'createdAt', 'text', 'state'].every((key) => typeof version[key] === 'string') || !Number.isFinite(Date.parse(version.createdAt))) {
              throw new Error('Invalid version record');
            }
            versions.push(version);
          } catch (error) {
            skipped++;
            console.error(`Unreadable version in room ${name}: ${file}: ${error.message}`);
          }
        }
        res.setHeader('X-Skipped-Versions', String(skipped));
        return json(200, versions);
      }
      if (req.method !== 'GET') return json(405, { error: 'Method not allowed' });
      const path = resolve(distDir, `.${decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname)}`);
      if (!path.startsWith(`${resolve(distDir)}${sep}`)) return json(403, { error: 'Forbidden' });
      if (!existsSync(path)) return json(404, { error: 'Not found. Run npm run build first, or use npm run dev.' });
      const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' };
      res.writeHead(200, { 'Content-Type': types[extname(path)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
      res.end(readFileSync(path));
    } catch (error) {
      if (!error.status) console.error(error);
      if (!res.headersSent) json(error.status || 500, { error: error.status ? error.message : 'Storage or request failed' });
      else res.end();
    }
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 4 * 1024 * 1024 });
  server.on('upgrade', (req, socket, head) => {
    let room;
    try {
      const url = new URL(req.url, 'http://localhost');
      const name = url.searchParams.get('room');
      if (url.pathname !== '/sync' || !validRoom(name)) return socket.destroy();
      room = getRoom(name);
    } catch { return socket.destroy(); }
    wss.handleUpgrade(req, socket, head, (ws) => {
      room.sockets.add(ws);
      ws.on('error', () => {});
      ws.on('close', () => room.sockets.delete(ws));
      ws.send(Y.encodeStateAsUpdate(room.doc));
      ws.on('message', (data, binary) => {
        if (!binary) {
          if (data.toString() === 'ping') return ws.send('pong');
          return ws.close(1003, 'Binary Yjs updates or ping only');
        }
        // Y.applyUpdate can mutate a document before throwing on a truncated update.
        // Stage both decoding and persistence so rejected/unsaved edits never reach other clients.
        try {
          commitRoom(room, (doc) => Y.applyUpdate(doc, new Uint8Array(data)), ws, data);
        } catch (error) {
          console.error('Update or persistence failed:', error.message);
          return ws.close(1011, 'Update could not be saved');
        }
        if (ws.readyState === 1) ws.send('ack');
      });
    });
  });
  await new Promise((done, reject) => { server.once('error', reject); server.listen(port, host, done); });
  return {
    port: server.address().port,
    async close() {
      for (const ws of wss.clients) ws.terminate();
      await new Promise((done) => wss.close(done));
      await new Promise((done) => server.close(done));
      for (const { doc } of rooms.values()) doc.destroy();
    },
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const app = await startServer({ port: Number(process.env.PORT || 8787), dataDir: process.env.DATA_DIR ? resolve(process.env.DATA_DIR) : undefined });
  console.log(`itouMD collaboration prototype: http://127.0.0.1:${app.port}`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await app.close(); process.exit(0); });
}
