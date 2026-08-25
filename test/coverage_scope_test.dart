import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/app/admin_shell.dart';
import 'package:providentia_admin/app/providentia_admin_app.dart';
import 'package:providentia_admin/app/theme.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/admin_approval_link.dart';
import 'package:providentia_admin/core/auth/credential_store.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/accounts/account_models.dart';
import 'package:providentia_admin/features/accounts/account_repository.dart';
import 'package:providentia_admin/features/accounts/accounts_page.dart';
import 'package:providentia_admin/features/administrators/platform_administration_controller.dart';
import 'package:providentia_admin/features/administrators/platform_administrator_models.dart';
import 'package:providentia_admin/features/administrators/platform_administrator_repository.dart';
import 'package:providentia_admin/features/administrators/platform_administrators_page.dart';
import 'package:providentia_admin/features/auth/admin_approval_controller.dart';
import 'package:providentia_admin/features/auth/admin_approval_page.dart';
import 'package:providentia_admin/features/auth/admin_approval_port.dart';
import 'package:providentia_admin/features/auth/login_page.dart';
import 'package:providentia_admin/features/billing/billing_page.dart';
import 'package:providentia_admin/features/billing/billing_repository.dart';
import 'package:providentia_admin/features/catalog/catalog_models.dart';
import 'package:providentia_admin/features/catalog/catalog_page.dart';
import 'package:providentia_admin/features/catalog/catalog_repository.dart';
import 'package:providentia_admin/main.dart' as admin_main;

void main() {
  test('coverage scope loads every handwritten production library', () {
    const productionTypes = <Type>[
      AdminShell,
      ProvidentiaAdminApp,
      ApiClient,
      ApiException,
      ApiResponse,
      SecureCredentialStore,
      AdminApprovalLink,
      PlatformRole,
      OperatorCapability,
      OperatorAuthorization,
      SessionPhase,
      LoginLinkChallenge,
      SessionController,
      OperatorAccount,
      OperatorHome,
      OperatorAccountPage,
      AccountRepository,
      AccountsPage,
      PlatformAdministrator,
      PlatformAdministrationSnapshot,
      PlatformAdministratorRepository,
      PlatformAdministrationController,
      PlatformAdministratorsPage,
      LoginPage,
      AdminApprovalController,
      AdminApprovalPhase,
      AdminApprovalPage,
      AdminApprovalProof,
      AdminApprovalReview,
      HttpAdminLoginApprovalPort,
      BillingPage,
      BillingPlan,
      BillingRepository,
      CatalogQueueItem,
      PublishedCategory,
      ModerationPreview,
      CatalogPage,
      CatalogRepository,
    ];

    expect(productionTypes, hasLength(38));
    expect(buildAdminTheme(), isA<ThemeData>());
    expect(admin_main.main, isA<Future<void> Function(List<String>)>());
  });
}
