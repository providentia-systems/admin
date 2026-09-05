#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const contractPath = path.join(root, 'contracts', 'providentia-v1.json');
const outputRoot = path.join(
  root,
  'contracts',
  'generated',
  'providentia_api_client',
);
const contractBytes = await readFile(contractPath);
const contract = JSON.parse(contractBytes.toString('utf8'));
const digest = createHash('sha256').update(contractBytes).digest('hex');
const check = process.argv.includes('--check');

const allowed = new Set([
  'requestEmailCode',
  'verifyEmailCode',
  'getAccountProfile',
  'updateAccountProfile',
  'completeAccountOnboarding',
  'requestAccountEmailCode',
  'verifyAccountEmail',
  'makeAccountEmailPrimary',
  'removeAccountEmail',
  'requestSecurityCode',
  'verifySecurityCode',
  'getFeatureCatalog',
  'listAccessGroups',
  'createAccessGroup',
  'updateAccessGroup',
  'assignAccessGroup',
  'getAccessAssignment',
  'listAvailableCountries',
  'getCountryPrivacyPolicy',
  'listCountryStates',
  'listCountryCities',
  'listOperatorCountries',
  'getCountryConfiguration',
  'updateCountryConfiguration',
  'listPrivacyPolicies',
  'createPrivacyPolicy',
  'updatePrivacyPolicy',
  'listReferenceUpdates',
  'requestReferenceUpdate',
  'listOperatorHomes',
  'getOperatorHome',
  'listOperatorHomeRecords',
  'listAdministrators',
  'reviewAdministrator',
  'listPlatformAuditEvents',
  'getOwnAvatar',
  'putOwnAvatar',
  'deleteOwnAvatar',
  'getUserAvatar',
  'getOperatorHomeImage',
  'getOperatorUserAvatar',
  'selectGravatar',
  'refreshSession',
  'logout',
  'getCurrentUser',
  'searchCatalogProducts',
  'getCatalogProduct',
  'listPublishedCatalogCategories',
  'listCatalogContributionReviewQueue',
  'decideCatalogContribution',
  'putCatalogContributionProposal',
  'getCatalogProductImageContributionPreview',
  'putCatalogProductImageContributionPublication',
  'getCatalogWorkbench',
  'decideCatalogProposal',
  'keepExistingCatalogConflict',
  'putCatalogIcon',
  'previewCatalogMerge',
  'applyCatalogMerge',
  'reverseCatalogMerge',
  'listOperatorAccounts',
  'getOperatorAccount',
  'updateOperatorAccountStatus',
  'listOperatorBillingPlans',
  'createBillingPlan',
  'updateBillingPlan',
  'createBillingPrice',
  'setBillingPriceStatus',
  'putBillingProviderPriceReference',
  'putBillingEntitlement',
  'createBillingPromotion',
  'createHomeBillingOverride',
  'revokeHomeBillingOverride',
]);

const operations = [];
for (const [resource, pathItem] of Object.entries(contract.paths ?? {})) {
  for (const method of ['get', 'post', 'put', 'patch', 'delete']) {
    const operation = pathItem?.[method];
    if (operation && allowed.has(operation.operationId)) {
      operations.push({
        operationId: operation.operationId,
        method: method.toUpperCase(),
        resource,
      });
    }
  }
}
operations.sort((a, b) => a.operationId.localeCompare(b.operationId));
if (operations.length !== allowed.size) {
  const found = new Set(operations.map(value => value.operationId));
  const missing = [...allowed].filter(value => !found.has(value));
  throw new Error(`Admin operation allowlist is stale: ${missing.join(', ')}`);
}
if (operations.some(value => value.resource.startsWith('/api/v1/homes'))) {
  throw new Error('Admin generated client cannot contain household routes.');
}

const outputs = new Map([
  [path.join(outputRoot, 'pubspec.yaml'), pubspec()],
  [path.join(outputRoot, 'lib', 'providentia_api_client.dart'), dart()],
  [
    path.join(outputRoot, 'generation-manifest.json'),
    `${JSON.stringify({
      generator: 'tool/generate_admin_api_client.mjs',
      generatorVersion: 1,
      repositoryRole: 'linux-admin-client',
      contract: '../../providentia-v1.json',
      contractVersion: contract.info.version,
      contractSha256: digest,
      operationCount: operations.length,
      allowedOperationIds: operations.map(value => value.operationId),
      generatedFiles: ['pubspec.yaml', 'lib/providentia_api_client.dart'],
      generatedCodeMustNotBeEdited: true,
    }, null, 2)}\n`,
  ],
]);

if (check) {
  const stale = [];
  for (const [file, expected] of outputs) {
    try {
      if ((await readFile(file, 'utf8')) !== expected) stale.push(relative(file));
    } catch {
      stale.push(relative(file));
    }
  }
  if (stale.length > 0) {
    throw new Error(`Generated Admin API facade is stale:\n${stale.join('\n')}`);
  }
  process.stdout.write(`Admin API allowlist verified (${operations.length} operations).\n`);
} else {
  for (const [file, content] of outputs) {
    await mkdir(path.dirname(file), {recursive: true});
    await writeFile(file, content, 'utf8');
  }
  process.stdout.write(`Generated Admin API allowlist (${operations.length} operations).\n`);
}

function pubspec() {
  return `# GENERATED FILE - DO NOT EDIT.
name: providentia_api_client
description: Generated allowlisted Admin API facade for Providentia.
publish_to: none
version: 1.0.0

environment:
  sdk: '>=3.12.2 <3.13.0'
`;
}

function dart() {
  const entries = operations
    .map(value => `  '${value.operationId}': AdminApiOperation(
    operationId: '${value.operationId}',
    method: '${value.method}',
    pathTemplate: '${value.resource}',
  ),`)
    .join('\n');
  return `// GENERATED FILE - DO NOT EDIT.
// Source: contracts/providentia-v1.json
// Contract SHA-256: ${digest}
// Home records use explicitly authorized operator endpoints; tenant mutation routes are excluded.

library;

final class AdminApiOperation {
  const AdminApiOperation({
    required this.operationId,
    required this.method,
    required this.pathTemplate,
  });

  final String operationId;
  final String method;
  final String pathTemplate;
}

const adminApiOperations = <String, AdminApiOperation>{
${entries}
};

AdminApiOperation requireAdminApiOperation(String operationId) {
  final operation = adminApiOperations[operationId];
  if (operation == null) {
    throw ArgumentError.value(operationId, 'operationId', 'Not allowed in Admin');
  }
  return operation;
}
`;
}

function relative(file) {
  return path.relative(root, file).split(path.sep).join('/');
}
