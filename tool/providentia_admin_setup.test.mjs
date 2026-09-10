#!/usr/bin/env node

import assert from 'node:assert/strict';
import { accessSync, constants, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const root = resolve(import.meta.dirname, '..');
const script = resolve(root, 'tools', 'providentia-admin.sh');
const setupGuide = resolve(root, 'docs', 'setup-ubuntu.md');

function run(...arguments_) {
  return spawnSync('bash', [script, ...arguments_], {
    cwd: root,
    encoding: 'utf8',
    env: { ...process.env, PROVIDENTIA_API_BASE_URL: '' },
  });
}

test('guided setup is executable and help has no build side effects', () => {
  accessSync(script, constants.X_OK);
  const syntax = spawnSync('bash', ['-n', script], { encoding: 'utf8' });
  assert.equal(syntax.status, 0, syntax.stderr);
  const help = run('--help');
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /--api-url URL/);
  assert.match(help.stdout, /--no-launch/);
  assert.doesNotMatch(help.stdout, /Building Providentia Admin/);
});

test('public HTTPS and loopback development origins normalize safely', () => {
  for (const [input, expected] of [
    ['https://api.example.com/', 'https://api.example.com'],
    ['https://api.example.com:8443', 'https://api.example.com:8443'],
    ['http://localhost:8080/', 'http://localhost:8080'],
    ['http://127.0.0.1:8080', 'http://127.0.0.1:8080'],
    ['http://[::1]:8080', 'http://[::1]:8080'],
  ]) {
    const result = run('--validate-url', input);
    assert.equal(result.status, 0, `${input}: ${result.stderr}`);
    assert.ok(result.stdout.trim().endsWith(expected), result.stdout);
  }
});

test('unsafe or malformed backend values fail before setup', () => {
  for (const input of [
    'http://api.example.com',
    'https://user:password@api.example.com',
    'https://api.example.com/api',
    'https://api.example.com?mode=admin',
    'https://api.example.com#fragment',
    'https://api.example.com:0',
    'https://api.example.com:65536',
    'https://api.example.com:',
    'https://-invalid.example.com',
    'https://999.1.1.1',
  ]) {
    const result = run('--validate-url', input);
    assert.equal(result.status, 64, `${input}: ${result.stdout}${result.stderr}`);
    assert.match(result.stderr, /Invalid backend origin/);
    assert.doesNotMatch(result.stdout, /Building Providentia Admin/);
  }
});

test('build uses pinned repository bootstrap and the Admin desktop binary', () => {
  const source = readFileSync(script, 'utf8');
  assert.match(source, /tools\/agent-setup\.sh/);
  assert.match(source, /tool\/verify_contract\.mjs/);
  assert.match(source, /generate_admin_api_client\.mjs --check/);
  assert.match(source, /flutter build linux --release/);
  assert.match(
    source,
    /build\/linux\/x64\/release\/bundle\/providentia_admin/,
  );
  assert.match(source, /normal D-Bus keyring session/);
  assert.doesNotMatch(source, /MYSQL_PASSWORD|MARIADB_PASSWORD|DATABASE_URL/);
  assert.doesNotMatch(source, /OPENAI_API_KEY|ANTHROPIC_API_KEY/);
});

test('setup guide uses the released backend container and safe UFW ordering', () => {
  const guide = readFileSync(setupGuide, 'utf8');
  const sshRule = guide.indexOf(
    'sudo ufw allow from YOUR_ADMIN_PUBLIC_IP to any port 22 proto tcp',
  );
  const secondSession = guide.indexOf('second independent SSH session');
  const defaultPolicy = guide.indexOf('sudo ufw default deny incoming');
  const enableFirewall = guide.indexOf('sudo ufw enable');

  assert.ok(sshRule >= 0, 'missing restricted SSH rule');
  assert.ok(secondSession > sshRule, 'second-session check must follow SSH rule');
  assert.ok(
    defaultPolicy > secondSession,
    'default policy must follow the second-session check',
  );
  assert.ok(
    enableFirewall > defaultPolicy,
    'UFW enablement must follow safe rule preparation',
  );
  assert.match(
    guide,
    /docker compose --env-file \/etc\/providentia\/production\.env[\s\S]*exec -T api php bin\/providentia system:owner/,
  );
  assert.doesNotMatch(guide, /^php bin\/providentia system:owner/m);
});
