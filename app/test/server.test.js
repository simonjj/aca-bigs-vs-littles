'use strict';

const assert = require('node:assert/strict');
const http = require('node:http');
const { spawn } = require('node:child_process');
const { after, before, test } = require('node:test');

const appPort = 20_000 + Math.floor(Math.random() * 5_000);
const upstreamPort = appPort + 1;
const secret = 'not-for-logs';
let appProcess;
let upstreamServer;
let startupOutput = '';

function waitForStartup(child) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`App did not start. Output: ${startupOutput}`)), 10_000);

    child.stdout.on('data', (chunk) => {
      startupOutput += chunk.toString();
      if (startupOutput.includes('"event":"server_started"')) {
        clearTimeout(timeout);
        resolve();
      }
    });

    child.stderr.on('data', (chunk) => {
      startupOutput += chunk.toString();
    });

    child.once('exit', (code) => {
      clearTimeout(timeout);
      reject(new Error(`App exited before startup with code ${code}. Output: ${startupOutput}`));
    });
  });
}

before(async () => {
  upstreamServer = http.createServer((_request, response) => {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end('{"status":"ok"}');
  });

  await new Promise((resolve) => upstreamServer.listen(upstreamPort, '127.0.0.1', resolve));

  appProcess = spawn(process.execPath, ['server.js'], {
    cwd: require('node:path').resolve(__dirname, '..'),
    env: {
      ...process.env,
      PORT: String(appPort),
      UPSTREAM_URL: `http://127.0.0.1:${upstreamPort}/payload.json?sig=${secret}`,
      WAIT_MS: '1',
      UPSTREAM_TIMEOUT_MS: '1000'
    },
    stdio: ['ignore', 'pipe', 'pipe']
  });

  await waitForStartup(appProcess);
});

after(async () => {
  if (appProcess && appProcess.exitCode === null) {
    appProcess.kill('SIGTERM');
    await new Promise((resolve) => appProcess.once('exit', resolve));
  }

  if (upstreamServer) {
    await new Promise((resolve) => upstreamServer.close(resolve));
  }
});

test('health and work endpoints succeed', async () => {
  const health = await fetch(`http://127.0.0.1:${appPort}/health`);
  const work = await fetch(`http://127.0.0.1:${appPort}/work`);

  assert.equal(health.status, 200);
  assert.equal(await health.text(), 'ok');
  assert.equal(work.status, 200);
  assert.equal(await work.text(), 'ok');
});

test('config and startup logs redact upstream credentials', async () => {
  const response = await fetch(`http://127.0.0.1:${appPort}/config`);
  const config = await response.json();

  assert.equal(response.status, 200);
  assert.equal(config.upstreamUrl, `http://127.0.0.1:${upstreamPort}/payload.json`);
  assert.equal(config.upstreamCredentialsPresent, true);
  assert.equal(startupOutput.includes(secret), false);
  assert.equal(JSON.stringify(config).includes(secret), false);
});
