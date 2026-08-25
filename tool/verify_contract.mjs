#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const expectedDigest =
  'fb7f18cc8d2e0f7aaf3ec9f1bd3039316c6f44af0023110936778a8d616a6759';
const contractBytes = await readFile(
  path.join(root, 'contracts', 'providentia-v1.json'),
);
const contract = JSON.parse(contractBytes.toString('utf8'));
const lock = JSON.parse(
  await readFile(path.join(root, 'contracts', 'contract.lock.json'), 'utf8'),
);
const manifest = JSON.parse(
  await readFile(
    path.join(
      root,
      'contracts',
      'generated',
      'providentia_api_client',
      'generation-manifest.json',
    ),
    'utf8',
  ),
);
const generated = await readFile(
  path.join(
    root,
    'contracts',
    'generated',
    'providentia_api_client',
    'lib',
    'providentia_api_client.dart',
  ),
  'utf8',
);

const digest = createHash('sha256').update(contractBytes).digest('hex');
assert(digest === expectedDigest, 'OpenAPI digest drifted from backend 1.18.0.');
assert(contract.openapi === '3.1.0', 'OpenAPI version must be 3.1.0.');
assert(contract.info?.version === '1.18.0', 'API version must be 1.18.0.');
assert(Object.keys(contract.paths ?? {}).length === 154, 'Expected 154 API paths.');

let operationCount = 0;
for (const value of Object.values(contract.paths ?? {})) {
  for (const method of ['get', 'post', 'put', 'patch', 'delete']) {
    if (value?.[method]) operationCount += 1;
  }
}
assert(operationCount === 177, 'Expected 177 API operations.');
assert(
  lock.artifacts?.['providentia-v1.json']?.sha256 === expectedDigest,
  'Backend contract lock digest does not match.',
);
assert(manifest.contractSha256 === expectedDigest, 'Generated manifest drifted.');
assert(manifest.repositoryRole === 'linux-admin-client', 'Generated facade role drifted.');
assert(manifest.operationCount === 47, 'Generated Admin operation count drifted.');
assert(
  generated.includes(`// Contract SHA-256: ${expectedDigest}`),
  'Generated Dart client is not bound to this contract.',
);
assert(!generated.includes('/api/v1/homes'), 'Generated Admin client exposes homes.');
assert(!generated.includes('stock'), 'Generated Admin client exposes stock.');

for (const [method, resource, operationId] of [
  ['post', '/api/v1/auth/login-links', 'startLoginLink'],
  ['post', '/api/v1/auth/login-links/{requestId}/proof', 'proveLoginLinkApproval'],
  ['post', '/api/v1/auth/login-links/{requestId}/review', 'reviewLoginLinkApproval'],
  ['post', '/api/v1/auth/login-links/{requestId}/decision', 'decideLoginLinkApproval'],
  ['post', '/api/v1/auth/verify-email', 'verifyEmail'],
  ['post', '/api/v1/auth/verify-email/resend', 'resendEmailVerification'],
  ['post', '/api/v1/auth/password-reset/request', 'requestPasswordReset'],
  ['post', '/api/v1/auth/password-reset/complete', 'completePasswordReset'],
  ['get', '/api/v1/me', 'getCurrentUser'],
  ['get', '/api/v1/admin/accounts', 'listOperatorAccounts'],
  ['patch', '/api/v1/admin/accounts/{userId}/status', 'updateOperatorAccountStatus'],
  ['get', '/api/v1/catalog-admin/workbench', 'getCatalogWorkbench'],
  ['get', '/api/v1/catalog-contributions/review', 'listCatalogContributionReviewQueue'],
  ['get', '/api/v1/catalog-contributions/{contributionId}/image-preview', 'getCatalogProductImageContributionPreview'],
  ['get', '/api/v1/operator/billing/plans', 'listOperatorBillingPlans'],
]) {
  assert(
    contract.paths?.[resource]?.[method]?.operationId === operationId,
    `Missing ${method.toUpperCase()} ${resource} (${operationId}).`,
  );
}

for (const schemaName of [
  'ApplicationTokenRequest',
  'ApplicationEmailRequest',
  'PasswordResetCompleteRequest',
]) {
  const schema = contract.components?.schemas?.[schemaName];
  assert(
    schema?.required?.includes('applicationKind'),
    `${schemaName} must remain application-bound.`,
  );
}

process.stdout.write(`Admin contract verified: 1.18.0 / ${digest}.\n`);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
