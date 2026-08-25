import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import 'billing_repository.dart';

final class BillingPage extends StatefulWidget {
  const BillingPage({required this.api, super.key});
  final AdminApi api;

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  late final BillingRepository _repository;
  List<BillingPlan>? _plans;
  Object? _error;

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
        if (_error case final error?)
          MaterialBanner(
            content: Text('Could not load billing plans: $error'),
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
    setState(() {
      _plans = null;
      _error = null;
    });
    try {
      final plans = await _repository.listPlans();
      if (mounted) setState(() => _plans = plans);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }
}

