import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';

void main() {
  group('OperatorAuthorization', () {
    test('maps every backend role to only its bounded capabilities', () {
      final authorization = OperatorAuthorization.fromWire(const <Object?>[
        'platform_administrator',
        'catalog_reviewer',
        'catalog_curator',
        'billing_operator',
      ]);

      expect(authorization.roles, hasLength(4));
      expect(authorization.capabilities, containsAll(OperatorCapability.values));
    });

    test('ignores unknown roles rather than broadening access', () {
      final authorization = OperatorAuthorization.fromWire(const <Object?>[
        'home_owner',
        'future_unknown_role',
      ]);

      expect(authorization.isOperator, isFalse);
      expect(authorization.roles, isEmpty);
      expect(authorization.capabilities, isEmpty);
    });

    test('catalog reviewer cannot curate or manage accounts', () {
      final authorization = OperatorAuthorization.fromWire(const <Object?>[
        'catalog_reviewer',
      ]);

      expect(authorization.allows(OperatorCapability.reviewCatalog), isTrue);
      expect(authorization.allows(OperatorCapability.curateCatalog), isFalse);
      expect(authorization.allows(OperatorCapability.manageAccounts), isFalse);
    });

    test('administrator mirrors backend super-operator capabilities', () {
      final authorization = OperatorAuthorization.fromWire(const <Object?>[
        'platform_administrator',
      ]);

      expect(authorization.capabilities, containsAll(OperatorCapability.values));
    });

    test('curator may review and curate but not manage accounts', () {
      final authorization = OperatorAuthorization.fromWire(const <Object?>[
        'catalog_curator',
      ]);

      expect(authorization.allows(OperatorCapability.reviewCatalog), isTrue);
      expect(authorization.allows(OperatorCapability.curateCatalog), isTrue);
      expect(authorization.allows(OperatorCapability.manageAccounts), isFalse);
    });
  });
}
