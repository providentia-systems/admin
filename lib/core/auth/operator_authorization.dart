enum OperatorCapability {
  manageAccounts,
  manageAdministrators,
  reviewCatalog,
  curateCatalog,
  viewBilling,
  manageBilling,
}

final class OperatorAuthorization {
  const OperatorAuthorization._(this.permissions, this.capabilities);

  factory OperatorAuthorization.fromPermissions(Iterable<String> values) {
    const known = <String>{'accounts.read', 'accounts.manage', 'accounts.assign', 'people.read', 'homes.read', 'homes.assign', 'homes.manage', 'administrators.read', 'administrators.approve', 'administrators.manage', 'groups.manage', 'countries.manage', 'policies.manage', 'catalog.read', 'catalog.review', 'catalog.curate', 'billing.read', 'billing.manage', 'audit.read'};
    final permissions = values.where(known.contains).toSet();
    final mapping = <OperatorCapability, String>{
      OperatorCapability.manageAccounts: 'accounts.read',
      OperatorCapability.manageAdministrators: 'administrators.read',
      OperatorCapability.reviewCatalog: 'catalog.review',
      OperatorCapability.curateCatalog: 'catalog.curate',
      OperatorCapability.viewBilling: 'billing.read',
      OperatorCapability.manageBilling: 'billing.manage',
    };
    return OperatorAuthorization._(
      Set<String>.unmodifiable(permissions),
      Set<OperatorCapability>.unmodifiable(
        mapping.entries
            .where((entry) => permissions.contains(entry.value))
            .map((entry) => entry.key),
      ),
    );
  }

  static const none = OperatorAuthorization._(
    <String>{},
    <OperatorCapability>{},
  );
  final Set<String> permissions;
  final Set<OperatorCapability> capabilities;
  bool allows(OperatorCapability capability) =>
      capabilities.contains(capability);
  bool has(String permission) => permissions.contains(permission);
  bool get isOperator => permissions.isNotEmpty;
}
