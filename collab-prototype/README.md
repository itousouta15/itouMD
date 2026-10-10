# itouMD local collaboration prototype

A standalone browser editor and local collaboration server, with a **native Flutter snapshot integration** under Cloud → 本機協作. The browser uses **Yjs** for CRDT text, **CodeMirror 6** for editing, and **y-indexeddb** for local persistence. Flutter reuses its Markdown editor and conflict screen, saves offline drafts, and explicitly syncs through a conditional snapshot API. See [native setup, platform limits, and protocol](../docs/local-collaboration.md). Collaboration rooms are not connected to HackMD or GitHub.

## Run the complete app

Requires Node.js 22.12+ and npm. In this directory:

```powershell
npm ci
npm run build
npm start
```

Open **http://127.0.0.1:8787/?room=demo**. The server serves the built browser client and WebSocket endpoint. It binds to loopback only. Stop with Ctrl+C. `PORT` and `DATA_DIR` environment variables optionally override the port and storage location.

For client development, run these in two terminals in this directory:

```powershell
# Terminal 1: synchronization / persistence server
npm run server
```

```powershell
# Terminal 2: Vite client, with HTTP and WebSocket proxies
npm run dev
```

Open the Vite URL printed in terminal 2 (normally http://127.0.0.1:5173). Offline editing works in either mode; **offline page reload requires the built app**, whose service worker caches the application shell. Dependencies are bundled; no CDN is needed at runtime. Initial installation and first page load require connectivity to the relevant servers.

## Two-client offline demo

1. Open the built app's `?room=demo` URL in two separate browser profiles, or a normal window and a private window. Use the same URL/port in both. Separate profiles ensure independent IndexedDB stores; tabs in one profile may share local storage.
2. Wait for **Connected · server saved**. Type `Shared` in the first client; observe it in the second.
3. Click **Go offline** in both clients. Append ` Alice` in the first and prepend `Bob ` in the second. Each should show only its own edit.
4. Reload both pages. Each recovers its own offline text from IndexedDB and remains manually offline. For a true network-offline reload, wait for the initial service worker installation, then set the browser's network offline or stop the server. The cached built app still opens.
5. Restore network/server availability and click **Reconnect** in both. Both converge to `Bob Shared Alice`. Concurrent insertions at the exact same position have deterministic Yjs ordering, not a wall-clock ordering guarantee.
6. Click **Save server version**, then download that version. **Download text** also exports the current local document while disconnected.
7. Stop/restart the Node server, then open the same room in a fresh browser profile. Its merged document is recovered from disk. Connected clients also automatically retry every second during a server outage and exchange their offline changes after restart.

Document names accept 1–64 ASCII letters, digits, `_`, or `-` and are **case-sensitive**, including on Windows. The document form opens another independent room. Private-mode storage lasts only as long as the private browsing session.

## Persistence and protocol

- A `Y.Doc` contains `getText('content')`. CodeMirror's Yjs binding generates CRDT operations rather than replacing the document on remote changes. Yjs undo shortcuts are prioritized over the editor's default history bindings.
- IndexedDB is loaded **before** the editor and network connection open. Local updates are persisted asynchronously by `y-indexeddb`. The UI states that persistence is enabled; it does not claim every keystroke is synchronously flushed. IndexedDB permission/open failures prevent the editor from opening. Runtime request/transaction failures or connection invalidation leave a persistent failure indicator and ask you to download your text before reloading; failed local writes are not automatically retried.
- `/sync?room=NAME` uses binary Yjs updates, the text message `ack`, and text `ping`/`pong` heartbeats. This is a deliberately small custom transport, **not the y-websocket wire protocol**. Both sides send full state on every connection. Subsequent updates are incremental, with an ACK only after server persistence. The client says **server saved** only after all its outstanding updates have been acknowledged. Full-state reconnects recover missed updates without relying on a volatile outbound queue. Yjs handles duplicate and out-of-order updates.
- Native clients use `GET /api/document?room=NAME` for `{room, content, revision, pending}` and conditional JSON `PUT` with `{content, revision}`. A stale revision returns `409` with the current snapshot; missing revisions return `428`. Revisions include full causal state, including deletions and pending dependencies. Pending causal state blocks native writes. The CAS check runs after the complete body arrives and shares staged persistence with WebSockets; accepted text changes broadcast as Yjs updates. Native text is limited to 1 MiB UTF-8 and requests to 4 MiB. Full details are in the native integration guide.
- Browser offline/online events suspend and resume automatic synchronization unless **Go offline** was selected manually. Heartbeats detect silent network failures without depending on a WebSocket close event: a ping is sent every 10 seconds, with a 10-second response timeout. Opening a connection also has a 10-second timeout, followed by one-second retries. Background-tab timer throttling can delay these checks. Events from superseded sockets are ignored.
- Each server update is applied to a temporary `Y.Doc`, then written through a temporary file and rename **before** replacing the active room, broadcasting, or acknowledging. Malformed updates and failed writes leave the last-saved room intact; full-state reconnects can retry unsaved client edits. Restart also preserves pending out-of-order CRDT operations. The server is single-process; the data directory must not be shared by concurrently running servers.
- State filenames are `data/room~HEX.yjs`, where `HEX` is the lowercase UTF-8 hex encoding of the case-sensitive room name. This prevents case-insensitive filesystem collisions and Windows reserved-device filenames. Earlier `NAME.yjs` and `NAME-versions/` paths migrate on access **only when their directory entry matches the requested name exactly**, and only when the encoded destination is absent. Corrupt legacy state is left in place. Already-collided data from the earlier layout cannot be separated automatically.
- `POST /api/versions?room=NAME` captures the server's current state in an immutable `data/room~HEX-versions/TIMESTAMP-UUID.json`, including text, timestamp and base64 Yjs state. `GET` returns readable version records and reports any unreadable records in the `X-Skipped-Versions` header. Damaged files are left in place, their names are logged, and the UI shows a repair notice while keeping readable versions downloadable. These are explicit snapshots, not per-keystroke history or a restore/branch UI. A snapshot captures what the server has received, not edits still offline on another device.
- The service worker caches only the root/index application shell and its bundled assets, not document APIs or arbitrary navigations. It caches a new HTML shell only after all its referenced bundles are downloaded, falls back to the last complete shell on network/HTTP errors or incomplete deployments, and serves cached content-hashed bundles even after a rebuild removes them from the server. Local documents live in IndexedDB, not HTTP cache. Browser storage is origin-specific: switching between Vite and the built server does not share the local database.

## Checks

```powershell
npm test
npm run build
npx playwright install chromium --no-shell
npm run test:browser
```

`npm test` covers:

- Offline insert/delete edits, reverse causal delivery, repeated duplicates, and text/state-vector convergence.
- Real two-client WebSocket merging, outage/restart recovery, and persisted version state.
- Outstanding-ACK races, stale socket events, silent-connection timeouts, opening timeouts, and real heartbeat replies.
- Case-only and Windows reserved-name room isolation, exact-case legacy migration, and room/version isolation after restart.
- Partially decoded malformed updates, disk-write failure rollback/retry, corrupt saved state/snapshots, and persistence of pending causal updates/deletes across restart.
- Malformed upgrade URLs in an isolated server process, invalid text/UTF-8 frames, and oversized messages.
- Native/browser and native/native CAS races, streaming request races, deletion/pending-operation revisions, Unicode updates, no-op/restart stability, failed native writes, and snapshot request validation.

The Playwright suite starts its own server on port 8790 with disposable storage under ignored `test-results/`; deployment-cache tests also start an ephemeral-port server with a private copy of the build. It uses **two independent Chromium browser contexts** to cover manual disconnection and actual network loss without the manual button, offline reload/room switching, automatic reconnection, exact text convergence, and version saving. It also checks cache poisoning by non-app navigation, incomplete/complete deployments with an unchanged service worker, HTTP-error fallback, damaged-version notices, and a genuinely aborted IndexedDB write. Unit-test storage also stays under `test-results/`. Build first so browser tests use current assets; run the two suites sequentially because Playwright cleans its output directory.

## Prototype boundary

- Plain text / Markdown source editing only; no Markdown rendering, rich-text model, attachments, presence, remote cursors, authentication, authorization, or document sharing management.
- Flutter uses explicit Markdown snapshot sync, not realtime native CRDT/presence. No collaboration-room integration with HackMD, GitHub, or any production service.
- Local trusted demo only. There is no access control or comprehensive hostile-client hardening. Invalid upgrade URLs and malformed/oversized messages are rejected without crashing the process; room names are identifiers, not secrets.
- Full-state handshakes and synchronous full-state disk writes favor correctness and inspectability over scale. WebSocket messages are limited to 4 MiB; rooms and versions have no eviction/retention policy. Large documents are outside this milestone.
- Atomic file replacement and staged updates handle ordinary restarts and rejected writes; there is no fsync-based power-loss guarantee, replication, or backup automation. A corrupt state file is refused rather than overwritten, and unreadable version records are reported and skipped: repairing those files or restoring a snapshot is manual. Browser storage can be cleared/evicted, and failed local writes require a download/storage repair rather than automatic replay; downloads are the explicit portable backup.
- No automated cross-browser/IME matrix, mobile validation, conflict-resolution UI, or snapshot restore UI. Browser automation currently exercises Chromium.

## Files

| Path | Purpose |
| --- | --- |
| `src/main.js`, `src/style.css`, `index.html` | Browser UI, local persistence, editor binding, version downloads |
| `src/sync.js` | Reconnecting Yjs WebSocket client, shared with socket tests |
| `server.js` | Static hosting, room synchronization, atomic state files, version API |
| `public/sw.js` | Built-app offline shell cache |
| `test/collaboration.test.js`, `test/server.test.js`, `test/sync.test.js`, `test/helpers.js` | CRDT, client-race, malformed-request, real-socket and persistence regression tests |
| `test/snapshot.test.js`, `e2e/snapshot.spec.js` | Native snapshot CAS, causal revision, rollback and browser interoperability tests |
| `e2e/offline.spec.js`, `e2e/cache.spec.js`, `e2e/storage.spec.js`, `e2e/helpers.js`, `playwright.config.js` | Chromium network/offline/room, deployment-cache and local-write-failure verification |
| `package.json`, `package-lock.json`, `vite.config.js` | Reproducible dependencies, commands, client build/proxy |

Generated `node_modules/`, `dist/`, `data/`, and `test-results/` are ignored.
