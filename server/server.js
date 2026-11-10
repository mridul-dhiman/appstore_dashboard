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
// Zero dependencies. Put it behind HTTPS and some access control before exposing it beyond your own machine: anyone
// who can reach /asc can use it to relay requests to Apple (they still need a valid signed JWT to get anything back).

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

function proxy(req, res) {
  const upstreamPath = req.url.replace(/^\/asc/, '') || '/';
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
  req.pipe(up); // forwards the JSON body of POST/PATCH; GET/DELETE have none
}

function serveStatic(req, res) {
  const url = new URL(req.url, 'http://x');
  let file = path.normalize(path.join(STATIC_DIR, decodeURIComponent(url.pathname)));
  if (!file.startsWith(STATIC_DIR)) { res.writeHead(403); return res.end(); }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!fs.existsSync(file)) file = path.join(STATIC_DIR, 'index.html'); // single-page app fallback
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404, { 'content-type': 'text/plain' }); return res.end('Not found. Run `flutter build web` first.'); }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-cache' });
    res.end(data);
  });
}

http.createServer((req, res) => {
  const isApi = req.url === '/asc' || req.url.startsWith('/asc/');
  if (isApi && ['GET', 'POST', 'PATCH', 'DELETE'].includes(req.method)) return proxy(req, res);
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405); return res.end(); }
  serveStatic(req, res);
}).listen(PORT, HOST, () => console.log(`App Store Dashboard on http://${HOST}:${PORT}  (static: ${STATIC_DIR})`));
