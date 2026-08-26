#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const expectedDigest =
  '7e13d550e7a4438297766f654fadbd1e75894efac989229da6fcd0d9f7f97dda';
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
assert(digest === expectedDigest, 'OpenAPI digest drifted from backend 1.19.0.');
assert(contract.openapi === '3.1.0', 'OpenAPI version must be 3.1.0.');
assert(contract.info?.version === '1.19.0', 'API version must be 1.19.0.');
assert(Object.keys(contract.paths ?? {}).length === 148, 'Expected 148 API paths.');

let operationCount = 0;
const operationIds = new Set();
for (const value of Object.values(contract.paths ?? {})) {
  for (const method of ['get', 'post', 'put', 'patch', 'delete']) {
    if (value?.[method]) {
      operationCount += 1;
      operationIds.add(value[method].operationId);
    }
  }
}
assert(operationCount === 172, 'Expected 172 API operations.');
assert(
  lock.artifacts?.['providentia-v1.json']?.sha256 === expectedDigest,
  'Backend contract lock digest does not match.',
);
assert(manifest.contractSha256 === expectedDigest, 'Generated manifest drifted.');
assert(manifest.repositoryRole === 'linux-admin-client', 'Generated facade role drifted.');
assert(manifest.operationCount === 43, 'Generated Admin operation count drifted.');
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

// Zero-password contract: the account-password and standalone-verification
// surface was removed in 1.19.0 and must never return.
for (const resource of [
  '/api/v1/auth/register',
  '/api/v1/auth/login',
  '/api/v1/auth/verify-email',
  '/api/v1/auth/verify-email/resend',
  '/api/v1/auth/password-reset/request',
  '/api/v1/auth/password-reset/complete',
]) {
  assert(
    contract.paths?.[resource] === undefined,
    `${resource} must not exist in the zero-password contract.`,
  );
}
for (const operationId of [
  'registerAccount',
  'login',
  'verifyEmail',
  'resendEmailVerification',
  'requestPasswordReset',
  'completePasswordReset',
]) {
  assert(
    !operationIds.has(operationId),
    `Operation ${operationId} must not exist in the zero-password contract.`,
  );
}
for (const schemaName of [
  'RegisterRequest',
  'RegisterResponse',
  'LoginRequest',
  'PasswordResetCompleteRequest',
  'ApplicationEmailRequest',
  'ApplicationTokenRequest',
]) {
  assert(
    contract.components?.schemas?.[schemaName] === undefined,
    `${schemaName} must not exist in the zero-password contract.`,
  );
}
assert(
  !JSON.stringify(contract.components?.schemas ?? {}).includes('"password"'),
  'No schema may carry a human-account password property.',
);

// Durable trusted-device sessions: the idle/refresh bounds are nullable and
// null means the session lives until explicit sign-out or revocation.
const credentials = contract.components?.schemas?.SessionCredentials;
for (const field of ['refreshExpiresAt', 'idleExpiresAt', 'refreshIdleTtlSeconds']) {
  const type = credentials?.properties?.[field]?.type;
  assert(
    Array.isArray(type) && type.includes('null'),
    `SessionCredentials.${field} must be nullable for durable sessions.`,
  );
  assert(
    credentials?.required?.includes(field),
    `SessionCredentials.${field} must stay a required (nullable) property.`,
  );
}
const idleTtl = credentials?.properties?.refreshIdleTtlSeconds;
assert(
  idleTtl?.minimum === 900 && idleTtl?.maximum === 5184000,
  'Bounded session idle TTL must stay within 900..5184000 seconds.',
);

// The new owner-driven member removal stays a household route: present in the
// contract, permanently excluded from the Admin facade.
assert(
  contract.paths?.['/api/v1/homes/{homeId}/memberships/{userId}']?.delete
    ?.operationId === 'removeHomeMembership',
  'Missing DELETE /api/v1/homes/{homeId}/memberships/{userId}.',
);
assert(
  !generated.includes('removeHomeMembership'),
  'Generated Admin client must not expose removeHomeMembership.',
);

process.stdout.write(`Admin contract verified: 1.19.0 / ${digest}.\n`);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
