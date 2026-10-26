import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { validateCompatibilityManifest, verifyBackendCompatibility } from './verify_backend_compatibility.mjs';

const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');

async function pairedFixture(t) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'providentia-paired-contract-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const admin = path.join(root, 'admin');
  const backend = path.join(root, 'backend');
  const artifacts = [
    ['contracts/providentia-v1.json', 'contracts/openapi/providentia-v1.json', 'openapiSha256', '{"info":{"version":"2.3.0"}}\n'],
    ['contracts/source/providentia-v1.json.gz', 'contracts/source/providentia-v1.json.gz', 'archiveSha256', 'synthetic archive'],
    ['contracts/contract.lock.json', 'contracts/openapi/contract.lock.json', 'lockSha256', '{"apiVersion":"2.3.0"}\n'],
  ];
  const manifest = {
    schemaVersion: 1,
    repository: 'providentia-systems/backend',
    apiVersion: '2.3.0',
    pathCount: 1,
    operationCount: 1,
    schemaCount: 1,
    adminOperationCount: 1,
  };
  for (const [adminPath, backendPath, field, bytes] of artifacts) {
    for (const [base, relative] of [[admin, adminPath], [backend, backendPath]]) {
      const file = path.join(base, relative);
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(file, bytes);
    }
    manifest[field] = digest(bytes);
  }
  await mkdir(path.join(backend, 'src'), { recursive: true });
  await writeFile(path.join(backend, 'src/runtime.php'), '<?php // synthetic runtime\n');
  execFileSync('git', ['init', '-q', backend]);
  execFileSync('git', ['-C', backend, 'add', '.']);
  execFileSync('git', ['-C', backend, '-c', 'user.name=Synthetic fixture', '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'Synthetic backend']);
  manifest.revision = execFileSync('git', ['-C', backend, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  await writeFile(path.join(admin, 'contracts/backend-compatibility.json'), JSON.stringify(manifest));
  return { admin, backend, manifest };
}

test('paired verification accepts exact immutable backend and contract bytes', async (t) => {
  const { admin, backend, manifest } = await pairedFixture(t);
  const summary = await verifyBackendCompatibility(backend, admin);
  assert.equal(summary.backendRevision, manifest.revision);
  assert.equal(summary.contractSha256, manifest.openapiSha256);
});

test('paired verification rejects mutable revisions and unrecognized repositories', async (t) => {
  const { manifest } = await pairedFixture(t);
  for (const revision of ['main', 'v2.3.0', 'a'.repeat(39), `${'a'.repeat(40)}\n`, `${'a'.repeat(40)}\nmalicious`]) {
    assert.throws(() => validateCompatibilityManifest({ ...manifest, revision }));
  }
  assert.throws(() => validateCompatibilityManifest({ ...manifest, repository: 'other/backend' }));
});

test('paired verification rejects mismatched backend revisions', async (t) => {
  const { admin, backend, manifest } = await pairedFixture(t);
  await writeFile(path.join(admin, 'contracts/backend-compatibility.json'), JSON.stringify({ ...manifest, revision: 'a'.repeat(40) }));
  await assert.rejects(verifyBackendCompatibility(backend, admin), /revision does not match/);
});

test('paired verification rejects backend or Admin artifact drift', async (t) => {
  const { admin, backend } = await pairedFixture(t);
  const backendFile = path.join(backend, 'contracts/openapi/providentia-v1.json');
  const original = await readFile(backendFile);
  await writeFile(backendFile, 'changed backend');
  await assert.rejects(verifyBackendCompatibility(backend, admin), /Backend .* drifted/);
  await writeFile(backendFile, original);
  await writeFile(path.join(admin, 'contracts/contract.lock.json'), 'changed lock');
  await assert.rejects(verifyBackendCompatibility(backend, admin), /Admin .* drifted/);
});


test('paired verification rejects dirty tracked runtime and untracked runtime inputs', async (t) => {
  const { admin, backend } = await pairedFixture(t);
  const runtime = path.join(backend, 'src/runtime.php');
  const original = await readFile(runtime);
  await writeFile(runtime, '<?php // changed runtime\n');
  await assert.rejects(verifyBackendCompatibility(backend, admin), /tracked changes/);
  await writeFile(runtime, original);
  await writeFile(path.join(backend, 'src/uncommitted.php'), '<?php // untracked runtime\n');
  await assert.rejects(verifyBackendCompatibility(backend, admin), /untracked runtime/);
});
