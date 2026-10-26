#!/usr/bin/env node

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

export function validateCompatibilityManifest(manifest) {
  assert.equal(manifest.schemaVersion, 1, 'Unsupported backend compatibility manifest.');
  assert.equal(manifest.repository, 'providentia-systems/backend', 'Unexpected paired backend repository.');
  assert.match(manifest.revision, /^[0-9a-f]{40}$/, 'The backend must use a full immutable revision.');
  assert.equal(manifest.revision.length, 40, 'The backend revision must contain exactly 40 characters.');
  assert.match(manifest.apiVersion, /^\d+\.\d+\.\d+$/, 'Invalid supported API version.');
  assert.equal(manifest.apiVersion.trim(), manifest.apiVersion, 'API version contains whitespace.');
  for (const field of ['openapiSha256', 'archiveSha256', 'lockSha256']) {
    assert.match(manifest[field], /^[0-9a-f]{64}$/, `Invalid ${field}.`);
    assert.equal(manifest[field].length, 64, `Invalid ${field} length.`);
  }
  for (const field of ['pathCount', 'operationCount', 'schemaCount', 'adminOperationCount']) {
    assert(Number.isInteger(manifest[field]) && manifest[field] > 0, `Invalid ${field}.`);
  }
  return manifest;
}

export async function verifyBackendCompatibility(backendRoot, adminRoot = repositoryRoot) {
  const manifest = validateCompatibilityManifest(JSON.parse(await readFile(
    path.join(adminRoot, 'contracts/backend-compatibility.json'), 'utf8',
  )));
  const revision = execFileSync('git', ['-C', backendRoot, 'rev-parse', 'HEAD'], {
    encoding: 'utf8',
  }).trim();
  assert.equal(revision, manifest.revision, 'Paired backend revision does not match the immutable support pin.');
  for (const [adminPath, backendPath, digestField] of [
    ['contracts/providentia-v1.json', 'contracts/openapi/providentia-v1.json', 'openapiSha256'],
    ['contracts/source/providentia-v1.json.gz', 'contracts/source/providentia-v1.json.gz', 'archiveSha256'],
    ['contracts/contract.lock.json', 'contracts/openapi/contract.lock.json', 'lockSha256'],
  ]) {
    const [adminBytes, backendBytes] = await Promise.all([
      readFile(path.join(adminRoot, adminPath)),
      readFile(path.join(backendRoot, backendPath)),
    ]);
    assert.equal(sha256(adminBytes), manifest[digestField], `Admin ${adminPath} drifted from the support pin.`);
    assert.equal(sha256(backendBytes), manifest[digestField], `Backend ${backendPath} drifted from the support pin.`);
    assert(adminBytes.equals(backendBytes), `Paired artifact bytes differ: ${adminPath}.`);
  }
  const trackedChanges = execFileSync('git', ['-C', backendRoot, 'status', '--porcelain', '--untracked-files=no'], {
    encoding: 'utf8',
  }).trim();
  assert.equal(trackedChanges, '', 'Paired backend has tracked changes outside the pinned revision.');
  const untrackedRuntime = execFileSync('git', ['-C', backendRoot, 'ls-files', '--others', '--exclude-standard', '--',
    'src', 'migrations', 'config', 'public', 'contracts', 'tool', 'tools', 'tests', 'bin', 'composer.json', 'composer.lock'], {
    encoding: 'utf8',
  }).trim();
  assert.equal(untrackedRuntime, '', 'Paired backend has untracked runtime or compatibility inputs.');
  return {
    repository: manifest.repository,
    backendRevision: revision,
    apiVersion: manifest.apiVersion,
    contractSha256: manifest.openapiSha256,
    scope: 'Pinned source artifacts; authenticated and installed acceptance are separate gates.',
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 3) throw new Error('Usage: node tool/verify_backend_compatibility.mjs BACKEND_CHECKOUT');
  process.stdout.write(`${JSON.stringify(await verifyBackendCompatibility(path.resolve(process.argv[2])), null, 2)}\n`);
}
