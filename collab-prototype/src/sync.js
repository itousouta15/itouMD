import * as Y from 'yjs';

// Full-state handshakes also resend edits made before a socket closed or an ACK arrived.
export class SyncClient {
  constructor(doc, url, { WebSocketImpl = globalThis.WebSocket, onStatus = () => {}, retryMs = 1000, heartbeatMs = 10000, timeoutMs = 10000 } = {}) {
    this.doc = doc;
    this.url = url;
    this.WebSocketImpl = WebSocketImpl;
    this.onStatus = onStatus;
    this.retryMs = retryMs;
    this.heartbeatMs = heartbeatMs;
    this.timeoutMs = timeoutMs;
    this.enabled = false;
    this.socket = null;
    this.pending = 0;
    this.remote = {};
    this.onUpdate = (update, origin) => {
      if (origin !== this.remote) this.sendUpdate(update);
    };
    doc.on('update', this.onUpdate);
  }

  connect() {
    if (this.destroyed) return;
    this.enabled = true;
    clearTimeout(this.timer);
    if (this.socket && this.socket.readyState < 2) return;
    this.closeSocket();
    this.onStatus('Connecting…');
    let socket;
    try { socket = new this.WebSocketImpl(this.url); }
    catch { this.connectionLost(null); return; }
    this.socket = socket;
    socket.binaryType = 'arraybuffer';
    this.openTimer = setTimeout(() => this.connectionLost(socket), this.timeoutMs);
    socket.onopen = () => {
      if (this.socket !== socket || !this.enabled) return;
      clearTimeout(this.openTimer);
      this.sendUpdate(Y.encodeStateAsUpdate(this.doc));
      this.schedulePing(socket);
    };
    socket.onmessage = (event) => {
      if (this.socket !== socket || !this.enabled) return;
      if (typeof event.data === 'string') {
        if (event.data === 'ack' && this.pending > 0) {
          this.pending--;
          if (this.pending === 0) this.onStatus('Connected · server saved');
        } else if (event.data === 'pong') {
          clearTimeout(this.pongTimer);
          this.schedulePing(socket);
        }
        return;
      }
      try { Y.applyUpdate(this.doc, new Uint8Array(event.data), this.remote); }
      catch { this.connectionLost(socket); }
    };
    socket.onerror = () => this.connectionLost(socket);
    socket.onclose = () => this.connectionLost(socket);
  }

  sendUpdate(update) {
    const socket = this.socket;
    if (!this.enabled || socket?.readyState !== 1) return;
    this.pending++;
    this.onStatus('Syncing…');
    try { socket.send(update); }
    catch { this.connectionLost(socket); }
  }

  schedulePing(socket) {
    if (this.socket !== socket) return;
    clearTimeout(this.pingTimer);
    this.pingTimer = setTimeout(() => {
      if (this.socket !== socket) return;
      this.pongTimer = setTimeout(() => this.connectionLost(socket), this.timeoutMs);
      try { socket.send('ping'); }
      catch { this.connectionLost(socket); }
    }, this.heartbeatMs);
  }

  closeSocket() {
    const socket = this.socket;
    this.socket = null;
    this.pending = 0;
    clearTimeout(this.openTimer);
    clearTimeout(this.pingTimer);
    clearTimeout(this.pongTimer);
    if (socket) {
      socket.onopen = null;
      socket.onmessage = null;
      try { socket.close(); } catch { /* Reconnect from the full document even if closing fails. */ }
    }
  }

  connectionLost(socket) {
    if (this.socket !== socket) return;
    this.closeSocket();
    this.onStatus(this.enabled ? 'Server unavailable · editing locally' : 'Offline · editing locally');
    if (this.enabled) this.timer = setTimeout(() => this.connect(), this.retryMs);
  }

  disconnect() {
    this.enabled = false;
    clearTimeout(this.timer);
    this.closeSocket();
    this.onStatus('Offline · editing locally');
  }

  destroy() {
    this.destroyed = true;
    this.disconnect();
    this.doc.off('update', this.onUpdate);
  }
}
