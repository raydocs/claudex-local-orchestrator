import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { COMPACTION_MARKERS, createProxyServer, createUsageAccumulator, extractUsageFromJsonBody, isNativeCompactionRequest, rewriteMessagesBody } from './model-filter-proxy.mjs';

const listen = server => new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', () => {
    server.removeListener('error', reject);
    resolve(server.address().port);
  });
});
const close = server => new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
const waitForLedger = async file => {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      const lines = (await readFile(file, 'utf8')).trim().split('\n');
      if (lines[0]) return JSON.parse(lines[0]);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  throw new Error('usage ledger was not written');
};

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

test('extracts usage from awkwardly split SSE chunks', () => {
  const accumulator = createUsageAccumulator();
  const stream = [
    'event: message_start\r\ndata: {"type":"message_start","message":{"usage":{"input_tokens":123,"cache_read_input_tokens":45}}}\r\n\r\n',
    'event: message_delta\ndata: {"type":"message_delta","usage":{"output_tokens":67}}\n\n',
  ].join('');
  const cuts = [1, 4, 9, 17, 31, 58, 93, 127, stream.length];
  let offset = 0;
  for (const cut of cuts) {
    accumulator.feed(Buffer.from(stream.slice(offset, cut)));
    offset = cut;
  }
  assert.deepEqual(accumulator.finish(), { input_tokens: 123, output_tokens: 67, cache_read_tokens: 45 });
});

test('extracts usage from a plain JSON body', () => {
  assert.deepEqual(extractUsageFromJsonBody(JSON.stringify({ usage: { input_tokens: 10, output_tokens: 4, cache_read_input_tokens: 7 } })), {
    input_tokens: 10,
    output_tokens: 4,
    cache_read_tokens: 7,
  });
});

test('malformed usage data returns nulls without throwing', () => {
  const accumulator = createUsageAccumulator();
  accumulator.feed('data: {not-json}\n');
  assert.deepEqual(accumulator.finish(), { input_tokens: null, output_tokens: null, cache_read_tokens: null });
  assert.deepEqual(extractUsageFromJsonBody('{not-json'), { input_tokens: null, output_tokens: null, cache_read_tokens: null });
});

test('proxy annotates routed responses and writes a ledger line', async t => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'claudex-usage-test-'));
  const usageLog = path.join(temp, 'usage.jsonl');
  const previousUsageLog = process.env.CLAUDEX_LOCAL_USAGE_LOG;
  process.env.CLAUDEX_LOCAL_USAGE_LOG = usageLog;
  t.after(async () => {
    if (previousUsageLog === undefined) delete process.env.CLAUDEX_LOCAL_USAGE_LOG;
    else process.env.CLAUDEX_LOCAL_USAGE_LOG = previousUsageLog;
    await rm(temp, { recursive: true, force: true });
  });
  const seen = [];
  const upstream = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => {
      seen.push(JSON.parse(Buffer.concat(chunks).toString()));
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ usage: { input_tokens: 9, output_tokens: 2, cache_read_input_tokens: 3 } }));
    });
  });
  let upstreamPort;
  try {
    upstreamPort = await listen(upstream);
  } catch (error) {
    if (error.code === 'EPERM') {
      t.skip('sandbox forbids listening on 127.0.0.1');
      return;
    }
    throw error;
  }
  t.after(() => close(upstream));
  const proxy = createProxyServer({ upstream: { hostname: '127.0.0.1', port: upstreamPort } });
  const proxyPort = await listen(proxy);
  t.after(() => close(proxy));
  const body = JSON.stringify({ model: 'gpt-5.6-sol', messages: [{ role: 'user', content: COMPACTION_MARKERS[0] }] });
  const response = await fetch(`http://127.0.0.1:${proxyPort}/v1/messages`, { method: 'POST', headers: { 'content-type': 'application/json' }, body });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('x-claudex-local-route'), 'compaction');
  assert.equal(seen[0].model, 'gpt-5.6-luna');
  await response.text();
  const entry = await waitForLedger(usageLog);
  assert.equal(entry.model, 'gpt-5.6-sol');
  assert.equal(entry.routed_model, 'gpt-5.6-luna');
  assert.equal(entry.route, 'compaction');
  assert.equal(entry.status, 200);
  assert.deepEqual({ input_tokens: entry.input_tokens, output_tokens: entry.output_tokens, cache_read_tokens: entry.cache_read_tokens }, { input_tokens: 9, output_tokens: 2, cache_read_tokens: 3 });
});
