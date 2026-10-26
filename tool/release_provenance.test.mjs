import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { releaseProvenance } from './write_release_provenance.mjs';

const contract = Buffer.from('{"info":{"version":"2.3.0"}}\n');
const digest = createHash('sha256').update(contract).digest('hex');
const fixture = () => ({
  revision: 'a'.repeat(40), sourceDirty: false, version: '1.2.3',
  apiOrigin: 'https://api.example.invalid', contract,
  compatibility: { repository: 'providentia-systems/backend', revision: 'b'.repeat(40),
    apiVersion: '2.3.0', openapiSha256: digest },
  lock: { apiVersion: '2.3.0', artifacts: { 'providentia-v1.json': { sha256: digest } } },
});

test('release evidence records exact provenance without claiming installed acceptance', () => {
  const evidence = releaseProvenance(fixture());
  assert.equal(evidence.applicationRevision, 'a'.repeat(40));
  assert.equal(evidence.supportedBackendRevision, 'b'.repeat(40));
  assert.equal(evidence.contractSha256, digest);
  assert.equal(evidence.apiOrigin, 'https://api.example.invalid');
  assert.equal(evidence.migrationStatus, 'unverified');
  assert.equal(evidence.deployedBackendRevision, null);
  assert.equal(evidence.installedAcceptance, 'not-run');
  assert.equal(evidence.authenticatedAcceptance, 'not-run');
});

test('release evidence rejects credential-bearing and non-origin addresses', () => {
  for (const apiOrigin of [undefined, 'https://operator:secret@example.test',
    'https://example.test/?token=secret', 'https://example.test/#secret',
    'https://example.test/path', 'http://example.test', 'file:///tmp/backend']) {
    assert.throws(() => releaseProvenance({ ...fixture(), apiOrigin }));
  }
  assert.equal(releaseProvenance({ ...fixture(), apiOrigin: 'http://localhost:8080/' }).apiOrigin,
    'http://localhost:8080');
});

test('release evidence fails on contract, version or immutable revision drift', () => {
  for (const patch of [{ contract: Buffer.from('{}') }, { revision: 'main' },
    { version: '../unsafe' }, { lock: { apiVersion: '2.2.0' } },
    { compatibility: { ...fixture().compatibility, revision: 'main' } }]) {
    assert.throws(() => releaseProvenance({ ...fixture(), ...patch }));
  }
});
