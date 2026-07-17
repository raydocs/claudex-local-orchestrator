import http from 'node:http';
import { appendFile, mkdirSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const DEFAULT_UPSTREAM = Object.freeze({ hostname: '127.0.0.1', port: 8317 });
export const DEFAULT_LISTEN = Object.freeze({ hostname: '127.0.0.1', port: 8318 });
export const DEFAULT_COMPACTION_MODEL = 'gpt-5.6-luna';
export const DEFAULT_MAX_BUFFER_BYTES = 256 * 1024 * 1024;
export const DEFAULT_USAGE_LOG = path.join(os.homedir(), '.local/state/claudex-local/usage.jsonl');

export const COMPACTION_MARKERS = Object.freeze([
  "Your task is to create a detailed summary of the conversation so far, paying close attention to the user's explicit requests and your previous actions.",
  'Your task is to create a detailed summary of the RECENT portion of the conversation',
]);

function contentText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.filter(block => block?.type === 'text' && typeof block.text === 'string').map(block => block.text).join('\n');
}

export function isNativeCompactionRequest(body) {
  if (!body || !Array.isArray(body.messages)) return false;
  const last = body.messages.at(-1);
  if (!last || last.role !== 'user') return false;
  const text = contentText(last.content).trimStart();
  return COMPACTION_MARKERS.some(marker => text.startsWith(marker));
}

export function rewriteMessagesBody(body, { sourceModels = ['gpt-5.6-sol'], compactionModel = DEFAULT_COMPACTION_MODEL } = {}) {
  const fromModel = typeof body?.model === 'string' ? body.model : '';
  if (!sourceModels.includes(fromModel) || !isNativeCompactionRequest(body)) {
    return { body, routed: false, fromModel, toModel: fromModel };
  }
  return { body: { ...body, model: compactionModel }, routed: true, fromModel, toModel: compactionModel };
}

function tokenCount(value) {
  return Number.isFinite(value) ? value : null;
}

function usageValues(usage) {
  if (!usage || typeof usage !== 'object') return { input_tokens: null, output_tokens: null, cache_read_tokens: null };
  return {
    input_tokens: tokenCount(usage.input_tokens),
    output_tokens: tokenCount(usage.output_tokens),
    cache_read_tokens: tokenCount(usage.cache_read_input_tokens),
  };
}

export function extractUsageFromJsonBody(body) {
  try {
    const parsed = Buffer.isBuffer(body) || body instanceof Uint8Array ? JSON.parse(Buffer.from(body).toString('utf8')) : typeof body === 'string' ? JSON.parse(body) : body;
    return usageValues(parsed?.usage);
  } catch {
    return usageValues(null);
  }
}

export function createUsageAccumulator() {
  const decoder = new TextDecoder();
  let partial = '';
  let tokens = usageValues(null);

  const scanLine = line => {
    if (!line.startsWith('data:')) return;
    const data = line.slice(5).trimStart();
    if (!data || data === '[DONE]') return;
    try {
      const event = JSON.parse(data);
      if (event?.type === 'message_start') {
        const usage = usageValues(event.message?.usage);
        tokens.input_tokens = usage.input_tokens;
        tokens.cache_read_tokens = usage.cache_read_tokens;
      } else if (event?.type === 'message_delta') {
        tokens.output_tokens = usageValues(event.usage).output_tokens;
      }
    } catch {
      // Malformed events are ignored; logging remains best-effort.
    }
  };

  const scan = text => {
    partial += text;
    const lines = partial.split('\n');
    partial = lines.pop() ?? '';
    for (const line of lines) scanLine(line.endsWith('\r') ? line.slice(0, -1) : line);
  };

  return {
    feed(chunk) {
      try {
        scan(typeof chunk === 'string' ? chunk : decoder.decode(chunk, { stream: true }));
      } catch {
        tokens = usageValues(null);
      }
    },
    finish() {
      try {
        scan(decoder.decode());
        if (partial) scanLine(partial.endsWith('\r') ? partial.slice(0, -1) : partial);
      } catch {
        tokens = usageValues(null);
      }
      partial = '';
      return { ...tokens };
    },
  };
}

let usageWarningPrinted = false;

function warnUsage(error) {
  if (usageWarningPrinted) return;
  usageWarningPrinted = true;
  console.error(`claudex-local adapter: usage ledger warning: ${error.message}`);
}

function prepareUsageLog(usageLog) {
  try {
    mkdirSync(path.dirname(usageLog), { recursive: true });
  } catch (error) {
    warnUsage(error);
  }
}

function appendUsage(usageLog, entry) {
  try {
    appendFile(usageLog, `${JSON.stringify(entry)}\n`, error => {
      if (error) warnUsage(error);
    });
  } catch (error) {
    warnUsage(error);
  }
}

function observeUsage(upstreamResponse, usageLog, request) {
  const started = request.started;
  const isSse = /^text\/event-stream\b/i.test(String(upstreamResponse.headers['content-type'] ?? ''));
  const accumulator = isSse ? createUsageAccumulator() : null;
  const chunks = isSse ? null : [];
  upstreamResponse.on('data', chunk => {
    if (accumulator) accumulator.feed(chunk);
    else chunks.push(chunk);
  });
  upstreamResponse.on('end', () => {
    const usage = accumulator ? accumulator.finish() : extractUsageFromJsonBody(Buffer.concat(chunks));
    const entry = {
      ts: new Date().toISOString(),
      model: request.route.fromModel,
      ...(request.route.routed ? { routed_model: request.route.toModel } : {}),
      route: request.route.routed ? 'compaction' : 'passthrough',
      status: upstreamResponse.statusCode ?? 502,
      duration_ms: Date.now() - started,
      ...usage,
    };
    appendUsage(usageLog, entry);
  });
}

function requestUpstream(req, res, upstream, headers, route, usageRequest) {
  const proxy = http.request({ hostname: upstream.hostname, port: upstream.port, method: req.method, path: req.url, headers: { ...headers, host: `${upstream.hostname}:${upstream.port}` } }, upstreamResponse => {
    const responseHeaders = { ...upstreamResponse.headers };
    if (route.routed) {
      responseHeaders['x-claudex-local-route'] = 'compaction';
      responseHeaders['x-claudex-local-original-model'] = route.fromModel;
      responseHeaders['x-claudex-local-routed-model'] = route.toModel;
    }
    res.writeHead(upstreamResponse.statusCode ?? 502, responseHeaders);
    upstreamResponse.pipe(res);
    if (usageRequest) observeUsage(upstreamResponse, usageRequest.usageLog, { ...usageRequest, route });
  });
  proxy.on('error', error => {
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: { message: `CLIProxyAPI unavailable: ${error.message}` } }));
  });
  return proxy;
}

function streamUnchanged(req, res, upstream) {
  req.pipe(requestUpstream(req, res, upstream, req.headers, { routed: false }));
}

function handleMessages(req, res, options) {
  const started = Date.now();
  const chunks = [];
  let bytes = 0;
  let rejected = false;
  req.on('data', chunk => {
    if (rejected) return;
    bytes += chunk.length;
    if (bytes > options.maxBufferBytes) {
      rejected = true;
      res.writeHead(413, { 'content-type': 'application/json', connection: 'close' });
      res.end(JSON.stringify({ error: { message: 'request exceeded local routing buffer' } }));
      req.destroy();
      return;
    }
    chunks.push(chunk);
  });
  req.on('end', () => {
    if (rejected) return;
    const original = Buffer.concat(chunks);
    let output = original;
    let route = { routed: false, fromModel: '', toModel: '' };
    try {
      route = rewriteMessagesBody(JSON.parse(original.toString('utf8')), options);
      if (route.routed) output = Buffer.from(JSON.stringify(route.body));
    } catch {
      // Preserve malformed/non-JSON input; upstream owns validation.
    }
    const headers = { ...req.headers, 'content-length': String(output.length) };
    delete headers['transfer-encoding'];
    requestUpstream(req, res, options.upstream, headers, route, { started, usageLog: options.usageLog }).end(output);
  });
}

export function createProxyServer({ upstream = DEFAULT_UPSTREAM, sourceModels = ['gpt-5.6-sol'], compactionModel = DEFAULT_COMPACTION_MODEL, maxBufferBytes = DEFAULT_MAX_BUFFER_BYTES, usageLog = process.env.CLAUDEX_LOCAL_USAGE_LOG ?? DEFAULT_USAGE_LOG } = {}) {
  const options = { upstream, sourceModels, compactionModel, maxBufferBytes, usageLog };
  prepareUsageLog(usageLog);
  return http.createServer((req, res) => {
    if (req.method === 'POST' && req.url?.split('?')[0] === '/v1/messages') return handleMessages(req, res, options);
    streamUnchanged(req, res, upstream);
  });
}

function main() {
  const upstream = { hostname: process.env.CLAUDEX_LOCAL_UPSTREAM_HOST ?? DEFAULT_UPSTREAM.hostname, port: Number(process.env.CLAUDEX_LOCAL_UPSTREAM_PORT ?? DEFAULT_UPSTREAM.port) };
  const listen = { hostname: process.env.CLAUDEX_LOCAL_LISTEN_HOST ?? DEFAULT_LISTEN.hostname, port: Number(process.env.CLAUDEX_LOCAL_LISTEN_PORT ?? DEFAULT_LISTEN.port) };
  const compactionModel = process.env.CLAUDEX_LOCAL_COMPACTION_MODEL ?? DEFAULT_COMPACTION_MODEL;
  createProxyServer({ upstream, compactionModel }).listen(listen.port, listen.hostname, () => console.log(`claudex-local adapter listening on ${listen.hostname}:${listen.port}; compact -> ${compactionModel}`));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
