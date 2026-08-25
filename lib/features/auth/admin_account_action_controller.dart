import 'package:flutter/foundation.dart';

import '../../core/auth/admin_account_link.dart';
import 'admin_account_action_port.dart';

enum AdminAccountActionPhase {
  idle,
  processing,
  resetReady,
  resetting,
  verified,
  resetComplete,
  requestSent,
  failed,
  dismissed,
}

final class AdminAccountActionController extends ChangeNotifier {
  AdminAccountActionController(this._port);

  final AdminAccountActionPort _port;
  AdminAccountLink? _link;
  AdminAccountActionPhase _phase = AdminAccountActionPhase.idle;
  int _generation = 0;

  AdminAccountActionPhase get phase => _phase;
  bool get isVisible =>
      _phase != AdminAccountActionPhase.idle &&
      _phase != AdminAccountActionPhase.dismissed;
  bool get hasEphemeralCredential => _link?.hasCredential ?? false;

  Future<void> begin(Uri uri) async {
    final generation = ++_generation;
    _clearLink();
    try {
      final link = parseAdminAccountLink(uri);
      _link = link;
      if (link.action == AdminAccountLinkAction.passwordReset) {
        _phase = AdminAccountActionPhase.resetReady;
        notifyListeners();
        return;
      }
      _phase = AdminAccountActionPhase.processing;
      notifyListeners();
      await _port.verifyEmail(link.token);
      if (!_isCurrent(generation, link)) return;
      _clearLink();
      _phase = AdminAccountActionPhase.verified;
      notifyListeners();
    } on Object {
      if (generation != _generation) return;
      _clearLink();
      _phase = AdminAccountActionPhase.failed;
      notifyListeners();
    }
  }

  Future<void> completePasswordReset(String password) async {
    final link = _link;
    if (link == null ||
        link.action != AdminAccountLinkAction.passwordReset ||
        _phase != AdminAccountActionPhase.resetReady) {
      return;
    }
    if (password.length < 12 || password.length > 1024) {
      _clearLink();
      _phase = AdminAccountActionPhase.failed;
      notifyListeners();
      return;
    }
    final generation = _generation;
    _phase = AdminAccountActionPhase.resetting;
    notifyListeners();
    try {
      await _port.completePasswordReset(token: link.token, password: password);
      if (!_isCurrent(generation, link)) return;
      _clearLink();
      _phase = AdminAccountActionPhase.resetComplete;
      notifyListeners();
    } on Object {
      if (generation != _generation) return;
      _clearLink();
      _phase = AdminAccountActionPhase.failed;
      notifyListeners();
    }
  }

  Future<void> requestPasswordReset(String email) =>
      _request(email, reset: true);

  Future<void> resendVerification(String email) =>
      _request(email, reset: false);

  Future<void> _request(String email, {required bool reset}) async {
    final normalized = email.trim().toLowerCase();
    final generation = ++_generation;
    _clearLink();
    if (!_emailPattern.hasMatch(normalized)) {
      _phase = AdminAccountActionPhase.failed;
      notifyListeners();
      return;
    }
    _phase = AdminAccountActionPhase.processing;
    notifyListeners();
    try {
      if (reset) {
        await _port.requestPasswordReset(normalized);
      } else {
        await _port.resendVerification(normalized);
      }
      if (generation != _generation) return;
      _phase = AdminAccountActionPhase.requestSent;
      notifyListeners();
    } on Object {
      if (generation != _generation) return;
      _phase = AdminAccountActionPhase.failed;
      notifyListeners();
    }
  }

  void dismiss() {
    _generation += 1;
    _clearLink();
    _phase = AdminAccountActionPhase.dismissed;
    notifyListeners();
  }

  bool _isCurrent(int generation, AdminAccountLink link) =>
      generation == _generation && identical(link, _link);

  void _clearLink() {
    _link?.clear();
    _link = null;
  }

  @override
  void dispose() {
    _generation += 1;
    _clearLink();
    super.dispose();
  }
}

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
