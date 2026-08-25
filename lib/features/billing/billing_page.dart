import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import 'billing_repository.dart';

final class BillingPage extends StatefulWidget {
  const BillingPage({required this.api, required this.session, super.key});
  final AdminApi api;
  final SessionController session;

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  late final BillingRepository _repository;
  List<BillingPlan>? _plans;
  var _hasError = false;

  @override
  void initState() {
    super.initState();
    _repository = BillingRepository(widget.api);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Billing', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Free stabilization phase'),
            subtitle: Text(
              'Billing enforcement is disabled by backend configuration. Plans are shown for architecture validation only; users are not subscription-gated.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_hasError)
          MaterialBanner(
            content: const Text('The billing plan list could not be loaded.'),
            actions: <Widget>[
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          )
        else if (_plans == null)
          const LinearProgressIndicator()
        else
          Expanded(
            child: Card(
              child: ListView.separated(
                itemCount: _plans!.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final plan = _plans![index];
                  return ListTile(
                    leading: const Icon(Icons.sell_outlined),
                    title: Text(plan.name),
                    subtitle: Text('${plan.code} • revision ${plan.revision}'),
                    trailing: Chip(label: Text(plan.status)),
                  );
                },
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _load() async {
    final epoch = widget.session.authorizationEpoch;
    setState(() {
      _plans = null;
      _hasError = false;
    });
    try {
      final plans = await _repository.listPlans();
      if (_isAuthorized(epoch)) setState(() => _plans = plans);
    } on Object {
      if (_isAuthorized(epoch)) setState(() => _hasError = true);
    }
  }

  bool _isAuthorized(int epoch) =>
      mounted &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorizationEpoch == epoch;
}
