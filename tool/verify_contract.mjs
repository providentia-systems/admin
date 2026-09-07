#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const expectedDigest =
  '764f1b850a150f805eb178bf85cba802ba6b3ee35dcfbfae24a179049a7d55a7';
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
assert(digest === expectedDigest, 'OpenAPI digest drifted from backend 2.0.0.');
assert(contract.openapi === '3.1.0', 'OpenAPI version must be 3.1.0.');
assert(contract.info?.version === '2.0.0', 'API version must be 2.0.0.');
assert(Object.keys(contract.paths ?? {}).length === 174, 'Expected 174 API paths.');

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
assert(operationCount === 208, 'Expected 208 API operations.');
assert(
  lock.artifacts?.['providentia-v1.json']?.sha256 === expectedDigest,
  'Backend contract lock digest does not match.',
);
assert(manifest.contractSha256 === expectedDigest, 'Generated manifest drifted.');
assert(manifest.repositoryRole === 'linux-admin-client', 'Generated facade role drifted.');
assert(manifest.operationCount === 73, 'Generated Admin operation count drifted.');
assert(
  generated.includes(`// Contract SHA-256: ${expectedDigest}`),
  'Generated Dart client is not bound to this contract.',
);
assert(!generated.includes('/api/v1/homes'), 'Generated Admin client exposes homes.');
assert(lock.apiVersion === '2.0.0', 'Contract lock API version drifted.');
assert(lock.version === '2.0.0', 'Contract lock publication version drifted.');
assert(lock.sha256 === expectedDigest, 'Contract lock publication digest drifted.');
assert(manifest.contractVersion === '2.0.0', 'Generated manifest API version drifted.');
assert(Object.keys(contract.components?.schemas ?? {}).length === 239, 'Expected 239 schemas.');
const allowedOperations = new Set(manifest.allowedOperationIds);
assert(allowedOperations.size === 73, 'Admin allowlist contains duplicate or missing operations.');
for (const operationId of allowedOperations) {
  assert(operationIds.has(operationId), `Admin operation ${operationId} is absent from the contract.`);
}
for (const [resource, pathItem] of Object.entries(contract.paths)) {
  for (const method of ['get', 'post', 'put', 'patch', 'delete']) {
    const operationId = pathItem[method]?.operationId;
    if (!allowedOperations.has(operationId)) continue;
    assert(!resource.startsWith('/api/v1/homes'), `Admin must not expose tenant route ${resource}.`);
    assert(!resource.includes('/login-links'), `Admin must not expose retired link route ${resource}.`);
  }
}
for (const operationId of ['listOperatorHomes', 'getOperatorHome', 'listOperatorHomeRecords',
  'getOperatorHomeImage', 'getOperatorUserAvatar', 'listAccessGroups', 'assignAccessGroup',
  'listAdministrators', 'reviewAdministrator', 'requestEmailCode', 'verifyEmailCode']) {
  assert(allowedOperations.has(operationId), `Missing authorized operator operation ${operationId}.`);
}


for (const [method, resource, operationId] of [
  ['post', '/api/v1/auth/email-codes', 'requestEmailCode'],
  ['post', '/api/v1/auth/email-codes/verify', 'verifyEmailCode'],
  ['get', '/api/v1/admin/access/catalog', 'getFeatureCatalog'],
  ['get', '/api/v1/admin/access/groups', 'listAccessGroups'],
  ['put', '/api/v1/admin/access/{scope}/{subjectId}', 'assignAccessGroup'],
  ['get', '/api/v1/admin/homes/{homeId}/records/{collection}', 'listOperatorHomeRecords'],
  ['post', '/api/v1/admin/administrators/{userId}/review', 'reviewAdministrator'],
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

// Password and link-approval authentication have been retired. Public numeric
// email-code verification and authenticated email alias verification are separate.
for (const resource of [
  '/api/v1/auth/login-links',
  '/api/v1/auth/login-links/{requestId}',
  '/api/v1/auth/login-links/{requestId}/proof',
  '/api/v1/auth/login-links/{requestId}/review',
  '/api/v1/auth/login-links/{requestId}/decision',
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
  'startLoginLink',
  'proveLoginLinkApproval',
  'reviewLoginLinkApproval',
  'decideLoginLinkApproval',
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

const challenge = contract.components?.schemas?.EmailCodeChallenge;
const verification = contract.components?.schemas?.EmailCodeVerification;
assert(challenge?.properties?.code === undefined, 'The email code must not be returned to the requesting client.');
assert(challenge?.properties?.resendAfterSeconds?.const === 60, 'OTP resend cooldown drifted.');
assert(verification?.properties?.code?.pattern === '^[0-9]{8}$', 'OTP must contain eight digits.');
for (const field of ['challengeId', 'bindingToken', 'code']) {
  assert(verification?.required?.includes(field), `Email-code verification requires ${field}.`);
}
assert(verification.properties.bindingToken.writeOnly === true, 'Binding proof must remain write-only.');
assert(verification.properties.code.writeOnly === true, 'Email code must remain write-only.');
assert(contract.components.schemas.CurrentUserBootstrap.required.includes('profile'),
  'Bootstrap must include the authoritative profile and administrator access.');

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

process.stdout.write(`Admin contract verified: 2.0.0 / ${digest}.\n`);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
