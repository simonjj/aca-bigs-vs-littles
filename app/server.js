'use strict';

const http = require('node:http');
const { Agent, setGlobalDispatcher } = require('undici');

const port = Number.parseInt(process.env.PORT || '3000', 10);
const upstreamUrl = process.env.UPSTREAM_URL;
const waitMs = Number.parseInt(process.env.WAIT_MS || '40', 10);
const upstreamTimeoutMs = Number.parseInt(process.env.UPSTREAM_TIMEOUT_MS || '5000', 10);
const responseBody = Buffer.from('ok');

if (!upstreamUrl) {
  throw new Error('UPSTREAM_URL is required');
}

const parsedUpstreamUrl = new URL(upstreamUrl);
const publicUpstreamUrl = `${parsedUpstreamUrl.origin}${parsedUpstreamUrl.pathname}`;

setGlobalDispatcher(new Agent({
  connections: 512,
  pipelining: 1,
  keepAliveTimeout: 30_000,
  keepAliveMaxTimeout: 60_000
}));

const stats = {
  requests: 0,
  successes: 0,
  failures: 0,
  upstreamFailures: 0,
  active: 0,
  startedAt: new Date().toISOString()
};

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function sendJson(response, statusCode, body) {
  const payload = Buffer.from(JSON.stringify(body));
  response.writeHead(statusCode, {
    'content-type': 'application/json',
    'content-length': payload.length,
    'cache-control': 'no-store'
  });
  response.end(payload);
}

async function handleWork(response) {
  stats.requests += 1;
  stats.active += 1;

  try {
    const upstreamResponse = await fetch(upstreamUrl, {
      signal: AbortSignal.timeout(upstreamTimeoutMs)
    });

    if (!upstreamResponse.ok) {
      stats.upstreamFailures += 1;
      throw new Error(`upstream returned ${upstreamResponse.status}`);
    }

    await upstreamResponse.arrayBuffer();

    if (waitMs > 0) {
      await sleep(waitMs);
    }

    stats.successes += 1;
    response.writeHead(200, {
      'content-type': 'text/plain',
      'content-length': responseBody.length,
      'cache-control': 'no-store'
    });
    response.end(responseBody);
  } catch (error) {
    stats.failures += 1;
    sendJson(response, 502, {
      error: 'upstream_request_failed',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    stats.active -= 1;
  }
}

const server = http.createServer((request, response) => {
  if (request.method === 'GET' && request.url === '/work') {
    void handleWork(response);
    return;
  }

  if (request.method === 'GET' && (request.url === '/health' || request.url === '/ready')) {
    response.writeHead(200, {
      'content-type': 'text/plain',
      'content-length': responseBody.length
    });
    response.end(responseBody);
    return;
  }

  if (request.method === 'GET' && request.url === '/config') {
    sendJson(response, 200, {
      pid: process.pid,
      nodeVersion: process.version,
      upstreamUrl: publicUpstreamUrl,
      upstreamCredentialsPresent: parsedUpstreamUrl.search.length > 0,
      waitMs,
      upstreamTimeoutMs
    });
    return;
  }

  if (request.method === 'GET' && request.url === '/stats') {
    sendJson(response, 200, {
      ...stats,
      pid: process.pid,
      uptimeSeconds: Math.round(process.uptime())
    });
    return;
  }

  sendJson(response, 404, { error: 'not_found' });
});

server.keepAliveTimeout = 65_000;
server.headersTimeout = 66_000;
server.requestTimeout = 0;

server.listen(port, '0.0.0.0', () => {
  console.log(JSON.stringify({
    event: 'server_started',
    pid: process.pid,
    port,
    upstreamUrl: publicUpstreamUrl,
    upstreamCredentialsPresent: parsedUpstreamUrl.search.length > 0,
    waitMs
  }));
});

function shutdown(signal) {
  console.log(JSON.stringify({ event: 'shutdown', signal, pid: process.pid }));
  server.close((error) => {
    process.exit(error ? 1 : 0);
  });
  setTimeout(() => process.exit(1), 25_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
