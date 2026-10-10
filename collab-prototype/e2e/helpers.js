export async function waitForOfflineShell(page) {
  await page.evaluate(async () => { await navigator.serviceWorker.ready; });
  await page.waitForFunction(() => navigator.serviceWorker.controller !== null);
}

// A transaction queued after the editor's write confirms that write has completed.
export async function flushLocal(page, room) {
  await page.evaluate(async (roomName) => {
    await new Promise((resolve, reject) => {
      const request = indexedDB.open(`itoumd-prototype-v1-${roomName}`);
      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const db = request.result;
        const transaction = db.transaction('updates', 'readonly');
        transaction.oncomplete = () => { db.close(); resolve(); };
        transaction.onerror = () => { db.close(); reject(transaction.error); };
        transaction.objectStore('updates').getAll();
      };
    });
  }, room);
}
