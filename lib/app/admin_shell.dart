import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/auth/operator_authorization.dart';
import '../core/auth/session_controller.dart';
import '../features/access/access_groups_page.dart';
import '../features/accounts/accounts_page.dart';
import '../features/administrators/platform_administrators_page.dart';
import '../features/billing/billing_page.dart';
import '../features/catalog/catalog_page.dart';
import '../features/geography/country_administration_page.dart';
import '../features/profile/account_profile_page.dart';
import '../features/profile/admin_profile_port.dart';
import '../features/workspace/operator_records_page.dart';

final class AdminShell extends StatefulWidget {
  const AdminShell({required this.api, required this.session, super.key});

  final ApiClient api;
  final SessionController session;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

final class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final Widget page;
}

class _AdminShellState extends State<AdminShell> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    final authorization = widget.session.authorization;
    final destinations = <_Destination>[
      _Destination(
        label: 'Your profile',
        icon: Icons.person_outline,
        page: AccountProfilePage(
          port: AdminProfilePort(widget.api),
          onChanged: widget.session.reloadProfile,
        ),
      ),
      if (authorization.has('groups.manage'))
        _Destination(
          label: 'Groups',
          icon: Icons.group_work_outlined,
          page: AccessGroupsPage(api: widget.api),
        ),
      if (authorization.has('homes.read'))
        _Destination(
          label: 'Homes',
          icon: Icons.home_outlined,
          page: OperatorRecordsPage(
            api: widget.api,
            authorization: authorization,
          ),
        ),
      if (authorization.has('countries.manage'))
        _Destination(
          label: 'Countries',
          icon: Icons.public,
          page: CountryAdministrationPage(
            api: widget.api,
            authorization: authorization,
          ),
        ),
      if (authorization.has('policies.manage'))
        _Destination(
          label: 'Privacy policies',
          icon: Icons.policy_outlined,
          page: CountryAdministrationPage(
            api: widget.api,
            authorization: authorization,
            policies: true,
          ),
        ),
      if (authorization.has('audit.read'))
        _Destination(
          label: 'Audit history',
          icon: Icons.history,
          page: OperatorRecordsPage(
            api: widget.api,
            authorization: authorization,
            audit: true,
          ),
        ),
      if (authorization.allows(OperatorCapability.manageAdministrators))
        _Destination(
          label: 'Administrators',
          icon: Icons.admin_panel_settings_outlined,
          page: PlatformAdministratorsPage(
            api: widget.api,
            session: widget.session,
          ),
        ),
      if (authorization.allows(OperatorCapability.manageAccounts))
        _Destination(
          label: 'Accounts',
          icon: Icons.manage_accounts_outlined,
          page: AccountsPage(api: widget.api, session: widget.session),
        ),
      if (authorization.allows(OperatorCapability.reviewCatalog) ||
          authorization.allows(OperatorCapability.curateCatalog))
        _Destination(
          label: 'Catalog',
          icon: Icons.inventory_2_outlined,
          page: CatalogPage(
            api: widget.api,
            session: widget.session,
            canReview: authorization.allows(OperatorCapability.reviewCatalog),
            canCurate: authorization.allows(OperatorCapability.curateCatalog),
          ),
        ),
      if (authorization.allows(OperatorCapability.viewBilling))
        _Destination(
          label: 'Billing',
          icon: Icons.receipt_long_outlined,
          page: BillingPage(api: widget.api, session: widget.session),
        ),
    ];
    if (_selected >= destinations.length) _selected = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Providentia administration'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                '${authorization.permissions.length} permissions',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.session.signOut,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: destinations.isEmpty
          ? const Center(child: Text('No operator capability is available.'))
          : Row(
              children: <Widget>[
                SizedBox(
                  width: 220,
                  child: ListView(
                    children: <Widget>[
                      for (var index = 0; index < destinations.length; index++)
                        ListTile(
                          leading: Icon(destinations[index].icon),
                          title: Text(destinations[index].label),
                          selected: _selected == index,
                          onTap: () => setState(() => _selected = index),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: destinations[_selected].page),
              ],
            ),
    );
  }
}
