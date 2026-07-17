import http from 'node:http';
import { pathToFileURL } from 'node:url';

export const DEFAULT_UPSTREAM = Object.freeze({ hostname: '127.0.0.1', port: 8317 });
export const DEFAULT_LISTEN = Object.freeze({ hostname: '127.0.0.1', port: 8318 });
export const DEFAULT_COMPACTION_MODEL = 'gpt-5.6-luna';
export const DEFAULT_MAX_BUFFER_BYTES = 256 * 1024 * 1024;

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

function requestUpstream(req, res, upstream, headers, route) {
  const proxy = http.request({ hostname: upstream.hostname, port: upstream.port, method: req.method, path: req.url, headers: { ...headers, host: `${upstream.hostname}:${upstream.port}` } }, upstreamResponse => {
    const responseHeaders = { ...upstreamResponse.headers };
    if (route.routed) {
      responseHeaders['x-claudex-local-route'] = 'compaction';
      responseHeaders['x-claudex-local-original-model'] = route.fromModel;
      responseHeaders['x-claudex-local-routed-model'] = route.toModel;
    }
    res.writeHead(upstreamResponse.statusCode ?? 502, responseHeaders);
    upstreamResponse.pipe(res);
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
    requestUpstream(req, res, options.upstream, headers, route).end(output);
  });
}

export function createProxyServer({ upstream = DEFAULT_UPSTREAM, sourceModels = ['gpt-5.6-sol'], compactionModel = DEFAULT_COMPACTION_MODEL, maxBufferBytes = DEFAULT_MAX_BUFFER_BYTES } = {}) {
  const options = { upstream, sourceModels, compactionModel, maxBufferBytes };
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
