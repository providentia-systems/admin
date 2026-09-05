// GENERATED FILE - DO NOT EDIT.
// Source: contracts/providentia-v1.json
// Contract SHA-256: 764f1b850a150f805eb178bf85cba802ba6b3ee35dcfbfae24a179049a7d55a7
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
  'applyCatalogMerge': AdminApiOperation(
    operationId: 'applyCatalogMerge',
    method: 'POST',
    pathTemplate: '/api/v1/catalog-admin/merges',
  ),
  'assignAccessGroup': AdminApiOperation(
    operationId: 'assignAccessGroup',
    method: 'PUT',
    pathTemplate: '/api/v1/admin/access/{scope}/{subjectId}',
  ),
  'completeAccountOnboarding': AdminApiOperation(
    operationId: 'completeAccountOnboarding',
    method: 'POST',
    pathTemplate: '/api/v1/me/onboarding',
  ),
  'createAccessGroup': AdminApiOperation(
    operationId: 'createAccessGroup',
    method: 'POST',
    pathTemplate: '/api/v1/admin/access/groups',
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
  'createPrivacyPolicy': AdminApiOperation(
    operationId: 'createPrivacyPolicy',
    method: 'POST',
    pathTemplate: '/api/v1/admin/privacy-policies',
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
  'deleteOwnAvatar': AdminApiOperation(
    operationId: 'deleteOwnAvatar',
    method: 'DELETE',
    pathTemplate: '/api/v1/me/avatar',
  ),
  'getAccessAssignment': AdminApiOperation(
    operationId: 'getAccessAssignment',
    method: 'GET',
    pathTemplate: '/api/v1/admin/access/{scope}/{subjectId}',
  ),
  'getAccountProfile': AdminApiOperation(
    operationId: 'getAccountProfile',
    method: 'GET',
    pathTemplate: '/api/v1/me/profile',
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
  'getCountryConfiguration': AdminApiOperation(
    operationId: 'getCountryConfiguration',
    method: 'GET',
    pathTemplate: '/api/v1/admin/countries/{countryCode}',
  ),
  'getCountryPrivacyPolicy': AdminApiOperation(
    operationId: 'getCountryPrivacyPolicy',
    method: 'GET',
    pathTemplate: '/api/v1/countries/{countryCode}/policy',
  ),
  'getCurrentUser': AdminApiOperation(
    operationId: 'getCurrentUser',
    method: 'GET',
    pathTemplate: '/api/v1/me',
  ),
  'getFeatureCatalog': AdminApiOperation(
    operationId: 'getFeatureCatalog',
    method: 'GET',
    pathTemplate: '/api/v1/admin/access/catalog',
  ),
  'getOperatorAccount': AdminApiOperation(
    operationId: 'getOperatorAccount',
    method: 'GET',
    pathTemplate: '/api/v1/admin/accounts/{userId}',
  ),
  'getOperatorHome': AdminApiOperation(
    operationId: 'getOperatorHome',
    method: 'GET',
    pathTemplate: '/api/v1/admin/homes/{homeId}',
  ),
  'getOperatorHomeImage': AdminApiOperation(
    operationId: 'getOperatorHomeImage',
    method: 'GET',
    pathTemplate: '/api/v1/admin/homes/{homeId}/image',
  ),
  'getOperatorUserAvatar': AdminApiOperation(
    operationId: 'getOperatorUserAvatar',
    method: 'GET',
    pathTemplate: '/api/v1/admin/users/{userId}/avatar',
  ),
  'getOwnAvatar': AdminApiOperation(
    operationId: 'getOwnAvatar',
    method: 'GET',
    pathTemplate: '/api/v1/me/avatar',
  ),
  'getUserAvatar': AdminApiOperation(
    operationId: 'getUserAvatar',
    method: 'GET',
    pathTemplate: '/api/v1/users/{userId}/avatar',
  ),
  'keepExistingCatalogConflict': AdminApiOperation(
    operationId: 'keepExistingCatalogConflict',
    method: 'POST',
    pathTemplate: '/api/v1/catalog-admin/conflicts/{conflictId}/keep-existing',
  ),
  'listAccessGroups': AdminApiOperation(
    operationId: 'listAccessGroups',
    method: 'GET',
    pathTemplate: '/api/v1/admin/access/groups',
  ),
  'listAdministrators': AdminApiOperation(
    operationId: 'listAdministrators',
    method: 'GET',
    pathTemplate: '/api/v1/admin/administrators',
  ),
  'listAvailableCountries': AdminApiOperation(
    operationId: 'listAvailableCountries',
    method: 'GET',
    pathTemplate: '/api/v1/countries',
  ),
  'listCatalogContributionReviewQueue': AdminApiOperation(
    operationId: 'listCatalogContributionReviewQueue',
    method: 'GET',
    pathTemplate: '/api/v1/catalog-contributions/review',
  ),
  'listCountryCities': AdminApiOperation(
    operationId: 'listCountryCities',
    method: 'GET',
    pathTemplate: '/api/v1/countries/{countryCode}/cities',
  ),
  'listCountryStates': AdminApiOperation(
    operationId: 'listCountryStates',
    method: 'GET',
    pathTemplate: '/api/v1/countries/{countryCode}/states',
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
  'listOperatorCountries': AdminApiOperation(
    operationId: 'listOperatorCountries',
    method: 'GET',
    pathTemplate: '/api/v1/admin/countries',
  ),
  'listOperatorHomeRecords': AdminApiOperation(
    operationId: 'listOperatorHomeRecords',
    method: 'GET',
    pathTemplate: '/api/v1/admin/homes/{homeId}/records/{collection}',
  ),
  'listOperatorHomes': AdminApiOperation(
    operationId: 'listOperatorHomes',
    method: 'GET',
    pathTemplate: '/api/v1/admin/homes',
  ),
  'listPlatformAuditEvents': AdminApiOperation(
    operationId: 'listPlatformAuditEvents',
    method: 'GET',
    pathTemplate: '/api/v1/admin/audit-events',
  ),
  'listPrivacyPolicies': AdminApiOperation(
    operationId: 'listPrivacyPolicies',
    method: 'GET',
    pathTemplate: '/api/v1/admin/privacy-policies',
  ),
  'listPublishedCatalogCategories': AdminApiOperation(
    operationId: 'listPublishedCatalogCategories',
    method: 'GET',
    pathTemplate: '/api/v1/catalog/categories',
  ),
  'listReferenceUpdates': AdminApiOperation(
    operationId: 'listReferenceUpdates',
    method: 'GET',
    pathTemplate: '/api/v1/admin/reference-updates',
  ),
  'logout': AdminApiOperation(
    operationId: 'logout',
    method: 'POST',
    pathTemplate: '/api/v1/auth/logout',
  ),
  'makeAccountEmailPrimary': AdminApiOperation(
    operationId: 'makeAccountEmailPrimary',
    method: 'POST',
    pathTemplate: '/api/v1/me/emails/{emailId}/primary',
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
  'putOwnAvatar': AdminApiOperation(
    operationId: 'putOwnAvatar',
    method: 'PUT',
    pathTemplate: '/api/v1/me/avatar',
  ),
  'refreshSession': AdminApiOperation(
    operationId: 'refreshSession',
    method: 'POST',
    pathTemplate: '/api/v1/auth/refresh',
  ),
  'removeAccountEmail': AdminApiOperation(
    operationId: 'removeAccountEmail',
    method: 'POST',
    pathTemplate: '/api/v1/me/emails/{emailId}/remove',
  ),
  'requestAccountEmailCode': AdminApiOperation(
    operationId: 'requestAccountEmailCode',
    method: 'POST',
    pathTemplate: '/api/v1/me/emails/codes',
  ),
  'requestEmailCode': AdminApiOperation(
    operationId: 'requestEmailCode',
    method: 'POST',
    pathTemplate: '/api/v1/auth/email-codes',
  ),
  'requestReferenceUpdate': AdminApiOperation(
    operationId: 'requestReferenceUpdate',
    method: 'POST',
    pathTemplate: '/api/v1/admin/reference-updates',
  ),
  'requestSecurityCode': AdminApiOperation(
    operationId: 'requestSecurityCode',
    method: 'POST',
    pathTemplate: '/api/v1/me/security-codes',
  ),
  'reverseCatalogMerge': AdminApiOperation(
    operationId: 'reverseCatalogMerge',
    method: 'POST',
    pathTemplate: '/api/v1/catalog-admin/merges/{mergeId}/reverse',
  ),
  'reviewAdministrator': AdminApiOperation(
    operationId: 'reviewAdministrator',
    method: 'POST',
    pathTemplate: '/api/v1/admin/administrators/{userId}/review',
  ),
  'revokeHomeBillingOverride': AdminApiOperation(
    operationId: 'revokeHomeBillingOverride',
    method: 'DELETE',
    pathTemplate: '/api/v1/operator/billing/overrides/{overrideId}',
  ),
  'searchCatalogProducts': AdminApiOperation(
    operationId: 'searchCatalogProducts',
    method: 'GET',
    pathTemplate: '/api/v1/catalog/products',
  ),
  'selectGravatar': AdminApiOperation(
    operationId: 'selectGravatar',
    method: 'POST',
    pathTemplate: '/api/v1/me/avatar/gravatar',
  ),
  'setBillingPriceStatus': AdminApiOperation(
    operationId: 'setBillingPriceStatus',
    method: 'PUT',
    pathTemplate: '/api/v1/operator/billing/prices/{priceId}/status',
  ),
  'updateAccessGroup': AdminApiOperation(
    operationId: 'updateAccessGroup',
    method: 'PUT',
    pathTemplate: '/api/v1/admin/access/groups/{groupId}',
  ),
  'updateAccountProfile': AdminApiOperation(
    operationId: 'updateAccountProfile',
    method: 'PATCH',
    pathTemplate: '/api/v1/me/profile',
  ),
  'updateBillingPlan': AdminApiOperation(
    operationId: 'updateBillingPlan',
    method: 'PUT',
    pathTemplate: '/api/v1/operator/billing/plans/{planId}',
  ),
  'updateCountryConfiguration': AdminApiOperation(
    operationId: 'updateCountryConfiguration',
    method: 'PUT',
    pathTemplate: '/api/v1/admin/countries/{countryCode}',
  ),
  'updateOperatorAccountStatus': AdminApiOperation(
    operationId: 'updateOperatorAccountStatus',
    method: 'PATCH',
    pathTemplate: '/api/v1/admin/accounts/{userId}/status',
  ),
  'updatePrivacyPolicy': AdminApiOperation(
    operationId: 'updatePrivacyPolicy',
    method: 'PUT',
    pathTemplate: '/api/v1/admin/privacy-policies/{policyId}',
  ),
  'verifyAccountEmail': AdminApiOperation(
    operationId: 'verifyAccountEmail',
    method: 'POST',
    pathTemplate: '/api/v1/me/emails/verify',
  ),
  'verifyEmailCode': AdminApiOperation(
    operationId: 'verifyEmailCode',
    method: 'POST',
    pathTemplate: '/api/v1/auth/email-codes/verify',
  ),
  'verifySecurityCode': AdminApiOperation(
    operationId: 'verifySecurityCode',
    method: 'POST',
    pathTemplate: '/api/v1/me/security-codes/verify',
  ),
};

AdminApiOperation requireAdminApiOperation(String operationId) {
  final operation = adminApiOperations[operationId];
  if (operation == null) {
    throw ArgumentError.value(operationId, 'operationId', 'Not allowed in Admin');
  }
  return operation;
}
