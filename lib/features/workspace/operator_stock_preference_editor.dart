import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import 'operator_stock_preference_repository.dart';

final class OperatorStockPreferenceEditor extends StatefulWidget {
  const OperatorStockPreferenceEditor({
    required this.repository,
    required this.session,
    required this.homeId,
    required this.homeProductId,
    super.key,
  });
  final OperatorStockPreferenceRepository repository;
  final SessionController session;
  final String homeId;
  final String homeProductId;
  @override
  State<OperatorStockPreferenceEditor> createState() =>
      _OperatorStockPreferenceEditorState();
}

class _OperatorStockPreferenceEditorState
    extends State<OperatorStockPreferenceEditor> {
  late final _epoch = widget.session.authorizationEpoch;
  final _minimum = TextEditingController();
  final _lead = TextEditingController();
  final _coverage = TextEditingController();
  final _snooze = TextEditingController();
  final _reason = TextEditingController();
  OperatorStockPreference? _current;
  bool _alwaysKeep = false;
  bool _neverSuggest = false;
  String? _preferredPack;
  bool _busy = true;
  bool _reloadRequired = false;
  String? _error;
  bool get _authorized =>
      mounted &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorizationEpoch == _epoch &&
      widget.session.authorization.has('homes.manage');

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_authorizationChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.session.removeListener(_authorizationChanged);
    for (final controller in [_minimum, _lead, _coverage, _snooze, _reason]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _authorizationChanged() {
    if (!_authorized) {
      for (final controller in [_minimum, _lead, _coverage, _snooze, _reason]) {
        controller.clear();
      }
      setState(() {
        _current = null;
        _preferredPack = null;
        _alwaysKeep = false;
        _neverSuggest = false;
        _error = null;
        _reloadRequired = true;
      });
    }
  }

  Future<void> _load() async {
    try {
      final preference = await widget.repository.load(
        widget.homeId,
        widget.homeProductId,
      );
      if (!_authorized) return;
      _minimum.text = preference.minimumQuantity ?? '';
      _lead.text = '${preference.leadTimeDays}';
      _coverage.text = preference.targetCoverageDays?.toString() ?? '';
      _snooze.text = preference.snoozeUntil ?? '';
      setState(() {
        _current = preference;
        _alwaysKeep = preference.alwaysKeep;
        _neverSuggest = preference.neverSuggest;
        _preferredPack = preference.preferredPackId;
        _busy = false;
      });
    } on Object {
      if (!_authorized) return;
      setState(() {
        _busy = false;
        _reloadRequired = true;
        _error = 'Stock preferences could not be loaded. Close and reload.';
      });
    }
  }

  void _reset() {
    _minimum.clear();
    _lead.text = '0';
    _coverage.clear();
    _snooze.clear();
    setState(() {
      _alwaysKeep = false;
      _neverSuggest = false;
      _preferredPack = null;
    });
  }

  Future<void> _save() async {
    final current = _current;
    if (!_authorized || _busy || _reloadRequired || current == null) return;
    final minimum = _minimum.text.trim();
    final lead = int.tryParse(_lead.text.trim());
    final coverage = _coverage.text.trim().isEmpty
        ? null
        : int.tryParse(_coverage.text.trim());
    final snooze = _snooze.text.trim();
    final date = snooze.isEmpty ? null : DateTime.tryParse(snooze);
    String? error;
    if (_reason.text.trim().isEmpty) {
      error = 'Enter an audit reason.';
    } else if (minimum.isNotEmpty &&
        !RegExp(r'^(?:0|[1-9]\d{0,8})(?:\.\d{1,8})?$').hasMatch(minimum)) {
      error =
          'Enter a non-negative minimum quantity with up to eight decimal places.';
    } else if (lead == null ||
        lead < 0 ||
        lead > 365 ||
        (_coverage.text.trim().isNotEmpty &&
            (coverage == null || coverage < 1 || coverage > 365))) {
      error = 'Lead time must be 0–365 days and target coverage 1–365 days.';
    } else if (snooze.isNotEmpty &&
        (date == null || date.toIso8601String().substring(0, 10) != snooze)) {
      error = 'Enter a valid snooze date as YYYY-MM-DD.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        homeId: widget.homeId,
        homeProductId: widget.homeProductId,
        reason: _reason.text,
        preference: OperatorStockPreference(
          revision: current.revision,
          minimumQuantity: minimum.isEmpty ? null : minimum,
          alwaysKeep: _alwaysKeep,
          neverSuggest: _neverSuggest,
          preferredPackId: _preferredPack,
          leadTimeDays: lead!,
          targetCoverageDays: coverage,
          snoozeUntil: snooze.isEmpty ? null : snooze,
          packOptions: current.packOptions,
        ),
      );
      if (mounted && _authorized) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!_authorized) return;
      setState(() {
        _busy = false;
        _reloadRequired =
            error is! ApiException ||
            error.isConflict ||
            error.statusCode >= 500;
        _error = error is ApiException
            ? error.message
            : 'The save result could not be confirmed.';
        if (_reloadRequired) {
          _error = '$_error Close and reload before retrying.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) return const SizedBox.shrink();
    final enabled = !_busy && !_reloadRequired && _current != null;
    final packs = _current?.packOptions ?? const <String, String>{};
    return AlertDialog(
      title: const Text('Stock preferences'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Set the stock minimum and replenishment preferences for this household product. Quantities use the product’s inventory unit.',
              ),
              TextField(
                controller: _minimum,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Minimum quantity (optional)',
                ),
              ),
              SwitchListTile(
                title: const Text('Always keep in stock'),
                value: _alwaysKeep,
                onChanged: enabled
                    ? (value) => setState(() => _alwaysKeep = value)
                    : null,
              ),
              SwitchListTile(
                title: const Text('Never suggest'),
                value: _neverSuggest,
                onChanged: enabled
                    ? (value) => setState(() => _neverSuggest = value)
                    : null,
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(_preferredPack),
                initialValue: _preferredPack ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Preferred pack'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('No preference'),
                  ),
                  for (final pack in packs.entries)
                    DropdownMenuItem(value: pack.key, child: Text(pack.value)),
                  if (_preferredPack != null &&
                      !packs.containsKey(_preferredPack))
                    DropdownMenuItem(
                      value: _preferredPack,
                      child: const Text(
                        'Previously selected pack (unavailable)',
                      ),
                    ),
                ],
                onChanged: enabled
                    ? (value) => setState(
                        () => _preferredPack = value == '' ? null : value,
                      )
                    : null,
              ),
              TextField(
                controller: _lead,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Lead time (days)',
                ),
              ),
              TextField(
                controller: _coverage,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Target coverage (days, optional)',
                ),
              ),
              TextField(
                controller: _snooze,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Snooze until (YYYY-MM-DD, optional)',
                ),
              ),
              TextField(
                controller: _reason,
                enabled: enabled,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Audit reason'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: enabled ? _reset : null,
          child: const Text('Reset to defaults'),
        ),
        FilledButton(
          onPressed: enabled ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
