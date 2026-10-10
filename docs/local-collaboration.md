# Native Flutter collaboration milestone

itouMD now opens collaboration documents **inside the existing Flutter Markdown reader/editor**. Browser clients keep using Yjs/CodeMirror realtime synchronization. Flutter uses explicit, revision-checked Markdown snapshots: it has a durable local draft and merge UI, not a native CRDT or a WebView.

## Start and use

In `collab-prototype/` (Node.js 22.12+):

```powershell
npm ci
npm run build
npm start
```

The server binds to **127.0.0.1:8787**. In the project root, run Flutter, for example:

```powershell
flutter run -d windows
```

1. Open **雲端 → 本機協作**.
2. Leave **協作伺服器** at `http://127.0.0.1:8787` and use room `demo`. Enter a server **origin** only, not the browser's `/?room=demo` URL. Credentials, paths, query strings, and fragments are rejected and are not stored.
3. Choose **開啟協作草稿**. This opens the local draft even if the server is unavailable. Press **同步 / 重試** to read the current server document. Opening a draft does not silently fetch/replace its content.
4. Use the existing **編輯** button, Markdown toolbar, reader preview, **複製原始碼**, and **另存新檔** actions. Edits are queued for local persistence as you type; **完成編輯** saves locally and returns to reading. It does not upload automatically.
5. Press **同步 / 重試** to send local edits. Open `http://127.0.0.1:8787/?room=demo` in a browser to see accepted native changes arrive in its live editor.
6. Stop the server, edit in Flutter, go back, and reopen the entry under **本機協作草稿**. Text and the last reviewed server base/revision are retained. Restart the server and sync explicitly.
7. If browser and Flutter edits differ from the same base, the existing **合併衝突** screen shows automatically mergeable changes and choices for conflicting blocks. **取消** preserves the draft. **合併並同步** still uses CAS; another browser edit during review causes another conflict/retry instead of an unconditional overwrite. The other providers' “always overwrite” preference is not used for collaboration documents.

Room names are case-sensitive, 1–64 ASCII letters/digits/`_`/`-`. Both room and canonical server origin identify a draft: `demo`, `Demo`, and the same name on another port are separate documents. Drafts use their own persistent list, not the five-entry general recent-documents cache.

## Local persistence and failures

- Each SharedPreferences record contains the endpoint, current text, base text/revision, and update time in one JSON value. Full records are written serially so older async saves cannot roll back newer edits. No new Flutter packages are required.
- The status distinguishes a pending local write, saved local draft, unsynced changes, and network/server failure. Leaving the editor flushes pending local writes. A failed local save keeps the editor open, with **重試本機儲存** and the existing copy/save-as actions available. Network uploads do not start until the draft is locally saved.
- Native edits made during an HTTP request are retained. A successful older upload advances only its confirmed base; newer text stays dirty. If a PUT response is lost, the next explicit sync reads the server again and recognizes identical already-saved text, or asks for a new merge if it changed further.
- Corrupt native draft records are reported and retained rather than reset; other readable drafts remain listed. SharedPreferences completion is not an fsync/power-loss guarantee, and storage eviction/application-data deletion is not recoverable automatically. Use one native app instance per OS profile: preferences are not an interprocess draft database. Use **另存新檔** for a portable backup. This prototype is for small Markdown documents (native uploads: **1 MiB UTF-8**).

## Devices and network policy

The server continues to bind only to loopback; no public listener or authentication change was introduced.

- **Windows desktop:** use `http://127.0.0.1:8787` on the same computer. The Windows debug application compiles with the native integration.
- **Android USB debug:** run `adb reverse tcp:8787 tcp:8787`, then use `http://127.0.0.1:8787` inside the app. `localhost` always means the app's device unless a port is reversed.
- `flutter build apk --debug --no-pub` was verified and produces `build/app/outputs/flutter-apk/app-debug.apk`. This verifies compilation and the scoped debug manifest, not device connectivity. The Windows artifact is `build/windows/x64/runner/Debug/itou_md.exe`.
- **Android emulator debug:** use `http://10.0.2.2:8787` to reach the host loopback server, or use `adb reverse` and the default URL.
- The added Android network-security configuration is **debug-only**, allowing cleartext only for `127.0.0.1`, `localhost`, and `10.0.2.2`. It does not globally enable cleartext and does not change release networking policy. Other debug origins and release deployments may require HTTPS. There is no Android device connected in the current verification environment.
- **iOS/macOS/Linux:** device builds and networking have not been verified here. Existing ATS, sandbox entitlements, local-network permissions and platform policy still apply; this milestone does not relax them globally. Use an appropriate local debug setup or a trusted HTTPS endpoint.
- **Flutter web:** this milestone targets native Flutter. No cross-origin CORS enablement was added. The standalone browser app is the supported browser collaboration client.

This is a **local trusted protocol**: room names identify documents, not permissions. No tokens or secret-bearing URLs are used. Exposing the server beyond a trusted local setup is outside this milestone.

## Snapshot API

Both endpoints use `/api/document?room=NAME` and return `Cache-Control: no-store`. The service worker does not cache these API requests.

### GET

```json
{"room":"demo","content":"Markdown text","revision":"opaque-token","pending":false}
```

An absent room has an empty snapshot. Treat the revision as opaque. It hashes the exact room and **full encoded Yjs state**, not just visible text or a state vector. Delete-only operations, structurally different equal text, and buffered causal updates therefore invalidate stale writes. Revisions remain stable across ordinary restarts and no-op PUTs.

### Conditional PUT

Send `Content-Type: application/json`:

```json
{"content":"Updated Markdown","revision":"token-from-the-reviewed-snapshot"}
```

- `200`: the committed snapshot (same shape as GET).
- `409`: `{ "error": "Revision changed", "current": { ...snapshot... } }`. Merge/review against `current`; any retry must use that exact revision. If `current.pending` is true, the server is waiting for causal CRDT dependencies and native writes must wait. The native UI preserves its draft and asks for a later retry.
- `428`: missing revision; unconditional replacements are unsupported.
- `400`/`415`: invalid room, JSON, text, or media type.
- `413`: text exceeds 1 MiB or the encoded request body exceeds 4 MiB.
- `500`: persistence/request failure; keep the draft and retry. No failed candidate is made visible to other clients.

The final comparison happens **after receiving the complete request body**, with no `await` between comparing and committing. Accepted native edits change the differing middle range of `Y.Text` while retaining unchanged prefix/suffix items and avoiding split UTF-16 surrogate pairs. The resulting Yjs update is sent to connected browser peers.

Native PUT and browser WebSocket updates share one staged transaction: clone the current Yjs state, apply the change, atomically replace the state file, then publish the document and broadcast. A stale write, decode error, or failed write cannot contaminate active room state. Concurrent native edits have at most one winner per revision. The server remains single-process; there is no fsync-based power-loss guarantee or automatic backup/restore.

## Verification

From the project root:

```powershell
flutter test --no-pub
dart analyze lib
dart analyze test
flutter build windows --debug --no-pub
```

The native service/widget tests cover URL/room validation, reopening offline drafts, conflicts and cancellation, a second race after review, lost PUT responses, edits during GET/PUT, ordered local saves, local-write failure/retry, and corrupt draft preservation. The line-merge regressions cover dropped insertions, overlapping changes, and exact empty/final-newline handling.

From `collab-prototype/`, sequentially:

```powershell
npm test
npm run build
npm run test:browser
```

Server tests use real sockets/files and include native/native CAS races, a browser edit during a streaming PUT, causal/deletion revision changes, restart, Unicode, failed-write rollback, and malformed snapshot requests. Playwright covers browser-only offline behavior plus snapshot writes reaching the real CodeMirror editor and merging with its offline edits. Flutter widget tests exercise the native screens with a mock HTTP transport; they are not device-network tests.
