#!/usr/bin/env node
// Serves the built Flutter web app and forwards /asc/* to the App Store Connect API.
//
// Why: Apple's API sends no CORS headers, so a browser cannot call it directly. This forwards the request as-is,
// including the Authorization header the app signs in the browser. The API key never reaches this server (only the
// short-lived JWT it produces does), and nothing is logged, stored or cached.
//
//   flutter build web --release && node server/server.js          # http://localhost:8080
//   PORT=9000 STATIC_DIR=build/web node server/server.js
//
// Zero dependencies. It forwards only Apple API paths, refuses requests that come from other sites (Origin check) and
// bodies over 1 MB. Still put it behind HTTPS and some access control before exposing it beyond your own machine:
// anyone who can reach /asc directly can relay requests to Apple (they still need a valid signed JWT to get anything).

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '127.0.0.1';
const STATIC_DIR = path.resolve(process.env.STATIC_DIR || path.join(__dirname, '..', 'build', 'web'));
const UPSTREAM = 'api.appstoreconnect.apple.com';

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.otf': 'font/otf', '.ttf': 'font/ttf',
  '.woff2': 'font/woff2', '.map': 'application/json', '.txt': 'text/plain; charset=utf-8',
};

// Apple's JSON:API bodies are small; screenshots and builds go straight to Apple's upload URLs, never through here.
const MAX_BODY = 1024 * 1024;

function reject(res, status, detail) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ errors: [{ status: String(status), title: 'Proxy refused', detail }] }));
}

// Only this app's own page may use the relay: a browser sends Origin on cross-site requests, and it must match the host
// the page was served from. Clients that send no Origin (curl) still need a valid signed JWT to get anything from Apple.
// Extra page origins allowed to use the relay, e.g. ALLOWED_ORIGINS=http://localhost:5000 for `flutter run -d chrome`.
const ALLOWED_ORIGINS = new Set((process.env.ALLOWED_ORIGINS || '').split(',').map((o) => o.trim()).filter(Boolean));

function sameOrigin(req) {
  const origin = req.headers.origin;
  if (!origin) return true;
  if (ALLOWED_ORIGINS.has(origin)) return true;
  try {
    return new URL(origin).host === req.headers.host;
  } catch {
    return false;
  }
}

function proxy(req, res) {
  const upstreamPath = req.url.replace(/^\/asc/, '') || '/';
  if (!/^\/v[0-9]+\//.test(upstreamPath)) return reject(res, 404, 'Only /asc/v1/… and /asc/v2/… API paths are forwarded.');
  if (!sameOrigin(req)) return reject(res, 403, 'Requests from other sites are not forwarded.');
  if (Number(req.headers['content-length'] || 0) > MAX_BODY) return reject(res, 413, 'Request body too large.');
  const headers = { accept: req.headers.accept || '*/*', 'user-agent': 'appstore-dashboard-proxy' };
  if (req.headers.authorization) headers.authorization = req.headers.authorization;
  if (req.headers['content-type']) headers['content-type'] = req.headers['content-type'];
  if (req.headers['content-length']) headers['content-length'] = req.headers['content-length'];
  const up = https.request({ host: UPSTREAM, path: upstreamPath, method: req.method, headers }, (r) => {
    res.writeHead(r.statusCode || 502, {
      'content-type': r.headers['content-type'] || 'application/octet-stream',
      'cache-control': 'no-store',
    });
    r.pipe(res);
  });
  up.setTimeout(60000, () => up.destroy(new Error('upstream timeout')));
  up.on('error', (e) => {
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ errors: [{ status: '502', title: 'Proxy error', detail: String(e.message) }] }));
  });
  // Forwards the JSON body of POST/PATCH (GET/DELETE have none), cutting off a body that grows past the limit even
  // when no content-length was sent.
  let seen = 0;
  req.on('data', (chunk) => {
    seen += chunk.length;
    if (seen > MAX_BODY) {
      up.destroy(new Error('request body too large'));
      req.destroy();
    }
  });
  req.pipe(up);
}

function serveStatic(req, res) {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  } catch {
    res.writeHead(400, { 'content-type': 'text/plain' }); // a malformed %-escape must not take the server down
    return res.end('Bad request');
  }
  let file = path.join(STATIC_DIR, path.normalize(pathname));
  // Inside STATIC_DIR itself, not merely a folder whose name starts the same (build/web vs build/web-old).
  const rel = path.relative(STATIC_DIR, file);
  if (rel.startsWith('..') || path.isAbsolute(rel) || pathname.includes('\0')) { res.writeHead(403); return res.end(); }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!fs.existsSync(file)) file = path.join(STATIC_DIR, 'index.html'); // single-page app fallback
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404, { 'content-type': 'text/plain' }); return res.end('Not found. Run `flutter build web` first.'); }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-cache' });
    res.end(data);
  });
}

function handle(req, res) {
  try {
    const isApi = req.url === '/asc' || req.url.startsWith('/asc/');
    if (isApi && ['GET', 'POST', 'PATCH', 'DELETE'].includes(req.method)) return proxy(req, res);
    if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405); return res.end(); }
    serveStatic(req, res);
  } catch (e) {
    // Last line of defence: one bad request gets a 500, the server keeps running.
    if (!res.headersSent) res.writeHead(500, { 'content-type': 'text/plain' });
    res.end('Internal error');
  }
}

module.exports = { handle, STATIC_DIR };

if (require.main === module) {
  http.createServer(handle).listen(PORT, HOST, () => console.log(`App Store Dashboard on http://${HOST}:${PORT}  (static: ${STATIC_DIR})`));
}
