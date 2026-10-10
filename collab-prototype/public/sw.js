const CACHE = 'itoumd-shell-v2';

async function cacheShell(request) {
  const response = await fetch(request, { cache: 'reload' });
  if (!response.ok || !response.headers.get('Content-Type')?.includes('text/html')) {
    throw new Error('Application shell unavailable');
  }
  const html = await response.clone().text();
  const assets = [...new Set([...html.matchAll(/(?:src|href)="(\/assets\/[^\"]+)"/g)].map((match) => match[1]))];
  const cache = await caches.open(CACHE);
  // Commit the HTML last. A failed deployment/download must keep the previous complete shell.
  await cache.addAll(assets.map((asset) => new Request(asset, { cache: 'reload' })));
  await cache.put('/', response.clone());
  return response;
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    await cacheShell('/');
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith('itoumd-shell-') && name !== CACHE) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;
  const shell = event.request.mode === 'navigate' && (url.pathname === '/' || url.pathname === '/index.html');
  const asset = url.pathname.startsWith('/assets/');
  // In particular, navigating to /sw.js or an API must never overwrite the cached HTML.
  if (!shell && !asset) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    if (shell) {
      try { return await cacheShell(event.request); }
      catch {
        return (await cache.match('/')) || Response.error();
      }
    }
    // Vite assets are content-hashed: use installed copies even if a rebuild removed them on disk.
    return (await cache.match(event.request)) || fetch(event.request);
  })());
});
