import 'package:flutter/foundation.dart';

import 'platform_administrator_models.dart';
import 'platform_administrator_repository.dart';

final class PlatformAdministrationController extends ChangeNotifier {
  PlatformAdministrationController(this._port)
    : _snapshot = PlatformAdministrationSnapshot();

  final PlatformAdministrationPort _port;
  PlatformAdministrationSnapshot _snapshot;
  int _generation = 0;
  bool _disposed = false;

  PlatformAdministrationSnapshot get snapshot => _snapshot;

  Future<void> load() async {
    final generation = ++_generation;
    _set(
      PlatformAdministrationSnapshot(
        loading: true,
        administrators: _snapshot.administrators,
      ),
    );
    await _loadForGeneration(generation);
  }

  Future<void> grant(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      _failure('Enter a valid email address.');
      return;
    }
    final generation = ++_generation;
    _set(
      PlatformAdministrationSnapshot(
        loading: true,
        administrators: _snapshot.administrators,
      ),
    );
    try {
      await _port.grant(normalized);
      if (_isCurrent(generation)) await _loadForGeneration(generation);
    } on PlatformAdministrationFailure catch (error) {
      await _handleFailure(generation, error);
    } on Object {
      if (_isCurrent(generation)) {
        _failure('The administrator grant could not be completed safely.');
      }
    }
  }

  Future<void> revoke(PlatformAdministrator administrator) async {
    final generation = ++_generation;
    _set(
      PlatformAdministrationSnapshot(
        loading: true,
        administrators: _snapshot.administrators,
      ),
    );
    try {
      await _port.revoke(
        administratorId: administrator.id,
        expectedRevision: administrator.revision,
      );
      if (_isCurrent(generation)) await _loadForGeneration(generation);
    } on PlatformAdministrationFailure catch (error) {
      await _handleFailure(generation, error);
    } on Object {
      if (_isCurrent(generation)) {
        _failure('The administrator revoke could not be completed safely.');
      }
    }
  }

  Future<void> _loadForGeneration(int generation) async {
    try {
      final administrators = await _port.list();
      if (_isCurrent(generation)) {
        _set(PlatformAdministrationSnapshot(administrators: administrators));
      }
    } on PlatformAdministrationFailure catch (error) {
      if (_isCurrent(generation)) _failure(error.safeMessage);
    } on Object {
      if (_isCurrent(generation)) {
        _failure('Administrator details could not be loaded safely.');
      }
    }
  }

  Future<void> _handleFailure(
    int generation,
    PlatformAdministrationFailure error,
  ) async {
    if (!_isCurrent(generation)) return;
    if (error.kind == PlatformAdministrationFailureKind.conflict) {
      try {
        final administrators = await _port.list();
        if (_isCurrent(generation)) {
          _set(
            PlatformAdministrationSnapshot(
              administrators: administrators,
              safeMessage: error.safeMessage,
            ),
          );
        }
        return;
      } on Object {
        // Preserve the conflict-safe message without exposing transport data.
      }
    }
    if (_isCurrent(generation)) _failure(error.safeMessage);
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _failure(String safeMessage) => _set(
    PlatformAdministrationSnapshot(
      administrators: _snapshot.administrators,
      safeMessage: safeMessage,
    ),
  );

  void _set(PlatformAdministrationSnapshot snapshot) {
    if (_disposed) return;
    _snapshot = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
