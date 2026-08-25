// GENERATED FILE - DO NOT EDIT.
// Source: contracts/providentia-v1.json
// Contract SHA-256: 61d49a5b0c857b532e27cfc243a2701731f7b0f2c4d5f5ab39d3fb0636790cdd
// This facade deliberately excludes every household endpoint.

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
  'applyCatalogMerge': AdminApiOperation(
    operationId: 'applyCatalogMerge',
    method: 'POST',
    pathTemplate: '/api/v1/catalog-admin/merges',
  ),
  'cancelLoginLink': AdminApiOperation(
    operationId: 'cancelLoginLink',
    method: 'POST',
    pathTemplate: '/api/v1/auth/login-links/{requestId}/cancel',
  ),
  'createBillingPlan': AdminApiOperation(
    operationId: 'createBillingPlan',
    method: 'POST',
    pathTemplate: '/api/v1/operator/billing/plans',
  ),
  'createBillingPrice': AdminApiOperation(
    operationId: 'createBillingPrice',
    method: 'POST',
    pathTemplate: '/api/v1/operator/billing/plans/{planId}/prices',
  ),
  'createBillingPromotion': AdminApiOperation(
    operationId: 'createBillingPromotion',
    method: 'POST',
    pathTemplate: '/api/v1/operator/billing/promotions',
  ),
  'createHomeBillingOverride': AdminApiOperation(
    operationId: 'createHomeBillingOverride',
    method: 'POST',
    pathTemplate: '/api/v1/operator/billing/homes/{homeId}/overrides',
  ),
  'decideCatalogContribution': AdminApiOperation(
    operationId: 'decideCatalogContribution',
    method: 'PUT',
    pathTemplate: '/api/v1/catalog-contributions/{contributionId}/decision',
  ),
  'decideCatalogProposal': AdminApiOperation(
    operationId: 'decideCatalogProposal',
    method: 'POST',
    pathTemplate: '/api/v1/catalog-admin/proposals/{proposalId}/decision',
  ),
  'exchangeLoginLink': AdminApiOperation(
    operationId: 'exchangeLoginLink',
    method: 'POST',
    pathTemplate: '/api/v1/auth/login-links/{requestId}/exchange',
  ),
  'getCatalogProduct': AdminApiOperation(
    operationId: 'getCatalogProduct',
    method: 'GET',
    pathTemplate: '/api/v1/catalog/products/{productId}',
  ),
  'getCatalogProductImageContributionPreview': AdminApiOperation(
    operationId: 'getCatalogProductImageContributionPreview',
    method: 'GET',
    pathTemplate: '/api/v1/catalog-contributions/{contributionId}/image-preview',
  ),
  'getCatalogWorkbench': AdminApiOperation(
    operationId: 'getCatalogWorkbench',
    method: 'GET',
    pathTemplate: '/api/v1/catalog-admin/workbench',
  ),
  'getCurrentUser': AdminApiOperation(
    operationId: 'getCurrentUser',
    method: 'GET',
    pathTemplate: '/api/v1/me',
  ),
  'getLoginLinkStatus': AdminApiOperation(
    operationId: 'getLoginLinkStatus',
    method: 'POST',
    pathTemplate: '/api/v1/auth/login-links/{requestId}/status',
  ),
  'getOperatorAccount': AdminApiOperation(
    operationId: 'getOperatorAccount',
    method: 'GET',
    pathTemplate: '/api/v1/admin/accounts/{userId}',
  ),
  'grantOperatorAccountRole': AdminApiOperation(
    operationId: 'grantOperatorAccountRole',
    method: 'PUT',
    pathTemplate: '/api/v1/admin/accounts/{userId}/roles/{role}',
  ),
  'grantPlatformAdministrator': AdminApiOperation(
    operationId: 'grantPlatformAdministrator',
    method: 'POST',
    pathTemplate: '/api/v1/platform/administrators',
  ),
  'keepExistingCatalogConflict': AdminApiOperation(
    operationId: 'keepExistingCatalogConflict',
    method: 'POST',
    pathTemplate: '/api/v1/catalog-admin/conflicts/{conflictId}/keep-existing',
  ),
  'listCatalogContributionReviewQueue': AdminApiOperation(
    operationId: 'listCatalogContributionReviewQueue',
    method: 'GET',
    pathTemplate: '/api/v1/catalog-contributions/review',
  ),
  'listOperatorAccounts': AdminApiOperation(
    operationId: 'listOperatorAccounts',
    method: 'GET',
    pathTemplate: '/api/v1/admin/accounts',
  ),
  'listOperatorBillingPlans': AdminApiOperation(
    operationId: 'listOperatorBillingPlans',
    method: 'GET',
    pathTemplate: '/api/v1/operator/billing/plans',
  ),
  'listPlatformAdministrators': AdminApiOperation(
    operationId: 'listPlatformAdministrators',
    method: 'GET',
    pathTemplate: '/api/v1/platform/administrators',
  ),
  'listPublishedCatalogCategories': AdminApiOperation(
    operationId: 'listPublishedCatalogCategories',
    method: 'GET',
    pathTemplate: '/api/v1/catalog/categories',
  ),
  'logout': AdminApiOperation(
    operationId: 'logout',
    method: 'POST',
    pathTemplate: '/api/v1/auth/logout',
  ),
  'previewCatalogMerge': AdminApiOperation(
    operationId: 'previewCatalogMerge',
    method: 'POST',
    pathTemplate: '/api/v1/catalog-admin/merges/preview',
  ),
  'putBillingEntitlement': AdminApiOperation(
    operationId: 'putBillingEntitlement',
    method: 'PUT',
    pathTemplate: '/api/v1/operator/billing/plans/{planId}/entitlements/{featureKey}',
  ),
  'putBillingProviderPriceReference': AdminApiOperation(
    operationId: 'putBillingProviderPriceReference',
    method: 'PUT',
    pathTemplate: '/api/v1/operator/billing/prices/{priceId}/providers/{provider}',
  ),
  'putCatalogContributionProposal': AdminApiOperation(
    operationId: 'putCatalogContributionProposal',
    method: 'PUT',
    pathTemplate: '/api/v1/catalog-contributions/{contributionId}/proposal',
  ),
  'putCatalogIcon': AdminApiOperation(
    operationId: 'putCatalogIcon',
    method: 'PUT',
    pathTemplate: '/api/v1/catalog-admin/icons/{targetType}/{targetId}',
  ),
  'putCatalogProductImageContributionPublication': AdminApiOperation(
    operationId: 'putCatalogProductImageContributionPublication',
    method: 'PUT',
    pathTemplate: '/api/v1/catalog-contributions/{contributionId}/image-publication',
  ),
  'refreshSession': AdminApiOperation(
    operationId: 'refreshSession',
    method: 'POST',
    pathTemplate: '/api/v1/auth/refresh',
  ),
  'reverseCatalogMerge': AdminApiOperation(
    operationId: 'reverseCatalogMerge',
    method: 'POST',
    pathTemplate: '/api/v1/catalog-admin/merges/{mergeId}/reverse',
  ),
  'revokeHomeBillingOverride': AdminApiOperation(
    operationId: 'revokeHomeBillingOverride',
    method: 'DELETE',
    pathTemplate: '/api/v1/operator/billing/overrides/{overrideId}',
  ),
  'revokeOperatorAccountRole': AdminApiOperation(
    operationId: 'revokeOperatorAccountRole',
    method: 'DELETE',
    pathTemplate: '/api/v1/admin/accounts/{userId}/roles/{role}',
  ),
  'revokePlatformAdministrator': AdminApiOperation(
    operationId: 'revokePlatformAdministrator',
    method: 'POST',
    pathTemplate: '/api/v1/platform/administrators/{administratorId}/revoke',
  ),
  'searchCatalogProducts': AdminApiOperation(
    operationId: 'searchCatalogProducts',
    method: 'GET',
    pathTemplate: '/api/v1/catalog/products',
  ),
  'setBillingPriceStatus': AdminApiOperation(
    operationId: 'setBillingPriceStatus',
    method: 'PUT',
    pathTemplate: '/api/v1/operator/billing/prices/{priceId}/status',
  ),
  'startLoginLink': AdminApiOperation(
    operationId: 'startLoginLink',
    method: 'POST',
    pathTemplate: '/api/v1/auth/login-links',
  ),
  'updateBillingPlan': AdminApiOperation(
    operationId: 'updateBillingPlan',
    method: 'PUT',
    pathTemplate: '/api/v1/operator/billing/plans/{planId}',
  ),
  'updateOperatorAccountStatus': AdminApiOperation(
    operationId: 'updateOperatorAccountStatus',
    method: 'PATCH',
    pathTemplate: '/api/v1/admin/accounts/{userId}/status',
  ),
};

AdminApiOperation requireAdminApiOperation(String operationId) {
  final operation = adminApiOperations[operationId];
  if (operation == null) {
    throw ArgumentError.value(operationId, 'operationId', 'Not allowed in Admin');
  }
  return operation;
}
