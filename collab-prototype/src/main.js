import * as Y from 'yjs';
import { IndexeddbPersistence } from 'y-indexeddb';
import { EditorView, keymap } from '@codemirror/view';
import { basicSetup } from 'codemirror';
import { yCollab, yUndoManagerKeymap } from 'y-codemirror.next';
import { SyncClient } from './sync.js';
import './style.css';

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const requestedRoom = params.get('room') || '';
const room = requestedRoom.length >= 1 && requestedRoom.length <= 64 && !/[^a-zA-Z0-9_-]/.test(requestedRoom) ? requestedRoom : 'welcome';
$('room').value = room;
$('room-form').onsubmit = (event) => {
  event.preventDefault();
  location.search = new URLSearchParams({ room: $('room').value }).toString();
};
const doc = new Y.Doc();
const text = doc.getText('content');
const persistence = new IndexeddbPersistence(`itoumd-prototype-v1-${room}`, doc);
function download(content, filename, type = 'text/plain;charset=utf-8') {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
async function refreshVersions() {
  try {
    const response = await fetch(`/api/versions?room=${room}`);
    if (!response.ok) throw new Error('Version server unavailable');
    const versions = await response.json();
    const skipped = Number(response.headers.get('X-Skipped-Versions') || 0);
    $('versions').replaceChildren();
    for (const version of versions) {
      const item = document.createElement('li');
      const button = document.createElement('button');
      button.textContent = `${new Date(version.createdAt).toLocaleString()} · ${version.text.length} characters · download`;
      button.onclick = () => download(version.text, `${room}-${version.id}.md`);
      item.append(button);
      $('versions').append(item);
    }
    if (!versions.length) $('versions').textContent = skipped ? 'No readable saved server versions.' : 'No saved server versions yet.';
    if (skipped) $('notice').textContent = `${skipped} unreadable server version(s) skipped. Readable versions are listed; check the server log to repair damaged files.`;
  } catch (error) { $('notice').textContent = `${error.message}. Local editing still works.`; }
}
$('refresh').onclick = refreshVersions;

try {
  await Promise.race([
    persistence.whenSynced,
    new Promise((_, reject) => setTimeout(() => reject(new Error('IndexedDB did not open. Check browser storage permissions and reload.')), 10000)),
  ]);
  $('local').textContent = 'Local persistence enabled · IndexedDB';
  const localStorageFailed = () => {
    $('local').textContent = 'Local persistence failed · download text before reloading';
    $('notice').textContent = 'Local storage could not save reliably. Keep this page open and download your text before reloading.';
  };
  // y-indexeddb writes asynchronously. A failed/aborted write must not leave a success indicator.
  for (const event of ['error', 'abort', 'close', 'versionchange']) {
    persistence.db.addEventListener(event, localStorageFailed);
  }
  const undoManager = new Y.UndoManager(text);
  new EditorView({
    doc: text.toString(),
    extensions: [keymap.of(yUndoManagerKeymap), basicSetup, yCollab(text, null, { undoManager }), EditorView.lineWrapping, EditorView.contentAttributes.of({ 'aria-label': 'Document text', spellcheck: 'true' })],
    parent: $('editor'),
  });
  const updateCount = () => { $('count').textContent = `${text.length} characters`; };
  text.observe(updateCount);
  updateCount();
  const sync = new SyncClient(doc, `${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/sync?room=${room}`, {
    onStatus(status) {
      $('status').textContent = status;
      $('status').dataset.connected = String(status.startsWith('Connected'));
      $('snapshot').disabled = !status.startsWith('Connected');
    },
  });
  let offline = sessionStorage.getItem('itoumd-manual-offline') === 'true';
  function setConnection() {
    $('connection').textContent = offline ? 'Reconnect' : 'Go offline';
    if (offline || !navigator.onLine) sync.disconnect(); else sync.connect();
  }
  $('connection').disabled = false;
  $('connection').onclick = () => {
    offline = !offline;
    sessionStorage.setItem('itoumd-manual-offline', String(offline));
    setConnection();
  };
  setConnection();
  // Browsers can leave an existing WebSocket OPEN when the network disappears.
  window.addEventListener('offline', () => sync.disconnect());
  window.addEventListener('online', () => { if (!offline) sync.connect(); });
  $('export').disabled = false;
  $('export').onclick = () => download(text.toString(), `${room}.md`);
  $('snapshot').onclick = async () => {
    try {
      const response = await fetch(`/api/versions?room=${room}`, { method: 'POST' });
      if (!response.ok) throw new Error('Could not save server version');
      $('notice').textContent = 'Version saved from the server’s current merged document.';
      await refreshVersions();
    } catch (error) { $('notice').textContent = error.message; }
  };
  if (!offline && navigator.onLine) await refreshVersions();
} catch (error) {
  $('status').textContent = 'Local storage unavailable';
  $('local').textContent = 'Editor not opened: persistent storage is required.';
  $('notice').textContent = error.message;
}

if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch((error) => { $('notice').textContent = `Offline reload cache unavailable: ${error.message}`; });
}
