// node --test server/test/server.test.js   (no dependencies)
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'asc-static-'));
fs.mkdirSync(path.join(root, 'web'));
fs.writeFileSync(path.join(root, 'web', 'index.html'), 'INDEX');
fs.writeFileSync(path.join(root, 'web', 'app.js'), 'APP');
fs.mkdirSync(path.join(root, 'web-old'));
fs.writeFileSync(path.join(root, 'web-old', 'secret.txt'), 'SECRET');
process.env.STATIC_DIR = path.join(root, 'web');
const { handle } = require('../server.js');

function get(server, rawPath, { method = 'GET', headers = {} } = {}) {
  return new Promise((resolve, reject) => {
    const { port } = server.address();
    // http.request keeps the path as written, so malformed escapes reach the server untouched.
    const req = http.request({ host: '127.0.0.1', port, path: rawPath, method, headers }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('error', reject);
    req.end();
  });
}

test('static serving survives bad input and stays inside STATIC_DIR', async () => {
  const server = http.createServer(handle).listen(0, '127.0.0.1');
  await new Promise((r) => server.once('listening', r));
  try {
    assert.equal((await get(server, '/app.js')).body, 'APP');
    assert.equal((await get(server, '/%E0%A4%A')).status, 400, 'malformed escape is a 400, not a crash');
    assert.equal((await get(server, '/app.js')).body, 'APP', 'and the server is still up');
    const sibling = await get(server, '/..%2Fweb-old%2Fsecret.txt');
    assert.notEqual(sibling.body, 'SECRET');
    const dots = await get(server, '/%2e%2e/web-old/secret.txt');
    assert.notEqual(dots.body, 'SECRET');
  } finally {
    server.close();
  }
});

test('the relay refuses other sites, non-API paths and oversized bodies before contacting Apple', async () => {
  const server = http.createServer(handle).listen(0, '127.0.0.1');
  await new Promise((r) => server.once('listening', r));
  try {
    assert.equal((await get(server, '/asc/v1/apps', { headers: { origin: 'https://evil.example' } })).status, 403);
    assert.equal((await get(server, '/asc/etc/passwd')).status, 404);
    assert.equal((await get(server, '/asc/v1/apps', { method: 'POST', headers: { 'content-length': String(2 * 1024 * 1024) } })).status, 413);
  } finally {
    server.close();
  }
});
