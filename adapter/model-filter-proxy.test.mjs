import assert from 'node:assert/strict';
import http from 'node:http';
import test from 'node:test';
import { COMPACTION_MARKERS, createProxyServer, isNativeCompactionRequest, rewriteMessagesBody } from './model-filter-proxy.mjs';

const listen = server => new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
const close = server => new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));

test('matches only a final native compact prompt', () => {
  assert.equal(isNativeCompactionRequest({ messages: [{ role: 'user', content: COMPACTION_MARKERS[0] }] }), true);
  assert.equal(isNativeCompactionRequest({ messages: [{ role: 'user', content: COMPACTION_MARKERS[0] }, { role: 'assistant', content: 'quoted only' }] }), false);
});

test('rewrites only Sol compact requests', () => {
  const body = { model: 'gpt-5.6-sol', effort: 'high', messages: [{ role: 'user', content: COMPACTION_MARKERS[1] }] };
  const routed = rewriteMessagesBody(body);
  assert.equal(routed.routed, true);
  assert.equal(routed.body.model, 'gpt-5.6-luna');
  assert.equal(routed.body.effort, 'high');
  assert.equal(rewriteMessagesBody({ ...body, model: 'grok-4.5' }).routed, false);
});

test('proxy annotates routed responses', async () => {
  const seen = [];
  const upstream = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => {
      seen.push(JSON.parse(Buffer.concat(chunks).toString()));
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
    });
  });
  const upstreamPort = await listen(upstream);
  const proxy = createProxyServer({ upstream: { hostname: '127.0.0.1', port: upstreamPort } });
  const proxyPort = await listen(proxy);
  const body = JSON.stringify({ model: 'gpt-5.6-sol', messages: [{ role: 'user', content: COMPACTION_MARKERS[0] }] });
  const response = await fetch(`http://127.0.0.1:${proxyPort}/v1/messages`, { method: 'POST', headers: { 'content-type': 'application/json' }, body });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('x-claudex-local-route'), 'compaction');
  assert.equal(seen[0].model, 'gpt-5.6-luna');
  await close(proxy);
  await close(upstream);
});
