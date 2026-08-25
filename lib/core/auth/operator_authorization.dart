enum PlatformRole {
  administrator('platform_administrator'),
  catalogCurator('catalog_curator'),
  catalogReviewer('catalog_reviewer'),
  billingOperator('billing_operator');

  const PlatformRole(this.wireName);
  final String wireName;

  static PlatformRole? parse(String value) {
    for (final role in values) {
      if (role.wireName == value) return role;
    }
    return null;
  }
}

enum OperatorCapability {
  manageAccounts,
  manageAdministrators,
  reviewCatalog,
  curateCatalog,
  viewBilling,
  manageBilling,
}

final class OperatorAuthorization {
  const OperatorAuthorization._(this.roles, this.capabilities);

  factory OperatorAuthorization.fromWire(Iterable<Object?> wireRoles) {
    final roles = wireRoles
        .whereType<String>()
        .map(PlatformRole.parse)
        .whereType<PlatformRole>()
        .toSet();
    final capabilities = <OperatorCapability>{};
    if (roles.contains(PlatformRole.administrator)) {
      capabilities.addAll(OperatorCapability.values);
    }
    if (roles.contains(PlatformRole.catalogReviewer)) {
      capabilities.add(OperatorCapability.reviewCatalog);
    }
    if (roles.contains(PlatformRole.catalogCurator)) {
      capabilities.addAll(const <OperatorCapability>{
        OperatorCapability.reviewCatalog,
        OperatorCapability.curateCatalog,
      });
    }
    if (roles.contains(PlatformRole.billingOperator)) {
      capabilities.addAll(const <OperatorCapability>{
        OperatorCapability.viewBilling,
        OperatorCapability.manageBilling,
      });
    }
    return OperatorAuthorization._(
      Set<PlatformRole>.unmodifiable(roles),
      Set<OperatorCapability>.unmodifiable(capabilities),
    );
  }

  static const none = OperatorAuthorization._(<PlatformRole>{}, <OperatorCapability>{});

  final Set<PlatformRole> roles;
  final Set<OperatorCapability> capabilities;

  bool allows(OperatorCapability capability) => capabilities.contains(capability);
  bool get isOperator => capabilities.isNotEmpty;
}
