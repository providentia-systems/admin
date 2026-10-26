import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

export function releaseProvenance({ revision, sourceDirty, version, apiOrigin,
  compatibility, contract, lock, runId = null }) {
  if (!/^[0-9a-f]{40}$/.test(revision) || typeof sourceDirty !== 'boolean') {
    throw new Error('Release evidence requires an exact application revision and source state.');
  }
  if (!/^\d+\.\d+\.\d+(?:[+-][0-9A-Za-z.-]+)?$/.test(version)) {
    throw new Error('Release evidence requires a semantic package version.');
  }
  let origin;
  try { origin = new URL(apiOrigin); } catch {
    throw new Error('Build API origin must be an HTTPS origin (HTTP only for loopback).');
  }
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname);
  if (!(origin.protocol === 'https:' || (origin.protocol === 'http:' && loopback)) ||
      origin.username || origin.password || origin.pathname !== '/' ||
      origin.search || origin.hash || origin.origin === 'null') {
    throw new Error('Build API origin must exclude credentials, paths, queries and fragments.');
  }
  const digest = sha256(contract);
  if (compatibility.repository !== 'providentia-systems/backend' ||
      !/^[0-9a-f]{40}$/.test(compatibility.revision) ||
      !/^[0-9a-f]{64}$/.test(compatibility.openapiSha256) ||
      compatibility.openapiSha256 !== digest ||
      lock.apiVersion !== compatibility.apiVersion ||
      lock.artifacts?.['providentia-v1.json']?.sha256 !== digest ||
      JSON.parse(contract).info?.version !== compatibility.apiVersion) {
    throw new Error('Build evidence does not match the supported backend contract.');
  }
  return {
    schemaVersion: 1,
    platform: 'linux-x64',
    applicationRevision: revision,
    sourceDirty,
    packageVersion: version,
    apiOrigin: origin.origin,
    backendRepository: compatibility.repository,
    supportedBackendRevision: compatibility.revision,
    apiVersion: compatibility.apiVersion,
    contractSha256: digest,
    workflowRunId: runId,
    // A build cannot establish the state of a deployed backend or an installation.
    deployedBackendRevision: null,
    migrationStatus: 'unverified',
    installedAcceptance: 'not-run',
    authenticatedAcceptance: 'not-run',
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const output = process.argv[2];
    if (!output || process.argv.length !== 3) {
      throw new Error('Usage: node tool/write_release_provenance.mjs OUTPUT_JSON');
    }
    const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
    const git = (...args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim();
    const compatibility = JSON.parse(await readFile(path.join(root, 'contracts/backend-compatibility.json'), 'utf8'));
    const archive = await readFile(path.join(root, 'contracts/source/providentia-v1.json.gz'));
    const lockBytes = await readFile(path.join(root, 'contracts/contract.lock.json'));
    if (sha256(archive) !== compatibility.archiveSha256 || sha256(lockBytes) !== compatibility.lockSha256) {
      throw new Error('Build evidence does not match the pinned backend archive and lock.');
    }
    const evidence = releaseProvenance({
      revision: git('rev-parse', 'HEAD'),
      sourceDirty: git('status', '--porcelain', '--untracked-files=no') !== '',
      version: process.env.PROVIDENTIA_RELEASE_VERSION || '0.1.0',
      apiOrigin: process.env.PROVIDENTIA_BUILD_API_ORIGIN,
      compatibility,
      contract: gunzipSync(archive),
      lock: JSON.parse(lockBytes),
      runId: process.env.GITHUB_RUN_ID || null,
    });
    await writeFile(output, `${JSON.stringify(evidence, null, 2)}\n`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
