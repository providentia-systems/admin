import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/auth/operator_authorization.dart';
import '../core/auth/session_controller.dart';
import '../features/accounts/accounts_page.dart';
import '../features/billing/billing_page.dart';
import '../features/catalog/catalog_page.dart';

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
      if (authorization.allows(OperatorCapability.manageAccounts))
        _Destination(
          label: 'Accounts',
          icon: Icons.manage_accounts_outlined,
          page: AccountsPage(api: widget.api),
        ),
      if (authorization.allows(OperatorCapability.reviewCatalog) ||
          authorization.allows(OperatorCapability.curateCatalog))
        _Destination(
          label: 'Catalog',
          icon: Icons.inventory_2_outlined,
          page: CatalogPage(
            api: widget.api,
            canReview: authorization.allows(
              OperatorCapability.reviewCatalog,
            ),
            canCurate: authorization.allows(
              OperatorCapability.curateCatalog,
            ),
          ),
        ),
      if (authorization.allows(OperatorCapability.viewBilling))
        _Destination(
          label: 'Billing',
          icon: Icons.receipt_long_outlined,
          page: BillingPage(api: widget.api),
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
                '${authorization.roles.length} operator role(s)',
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
                NavigationRail(
                  selectedIndex: _selected,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (value) =>
                      setState(() => _selected = value),
                  destinations: destinations
                      .map(
                        (destination) => NavigationRailDestination(
                          icon: Icon(destination.icon),
                          label: Text(destination.label),
                        ),
                      )
                      .toList(growable: false),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: destinations[_selected].page),
              ],
            ),
    );
  }
}

