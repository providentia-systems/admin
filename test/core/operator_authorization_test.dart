import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';
void main(){
 test('unknown flags cannot grant operator access',(){expect(OperatorAuthorization.fromPermissions(['home_owner','future.flag']).isOperator,isFalse);});
 test('catalog review does not grant curation or account access',(){final a=OperatorAuthorization.fromPermissions(['catalog.review']);expect(a.capabilities,{OperatorCapability.reviewCatalog});});
 test('administrator listing does not grant approval',(){final a=OperatorAuthorization.fromPermissions(['administrators.read']);expect(a.has('administrators.approve'),isFalse);expect(a.allows(OperatorCapability.manageAdministrators),isTrue);});
 test('billing access remains separate from people access',(){final a=OperatorAuthorization.fromPermissions(['billing.read','billing.manage']);expect(a.has('people.read'),isFalse);expect(a.capabilities,{OperatorCapability.viewBilling,OperatorCapability.manageBilling});});
}
