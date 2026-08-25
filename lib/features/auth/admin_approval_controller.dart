import 'package:flutter/foundation.dart';

import '../../core/auth/admin_approval_link.dart';
import 'admin_approval_port.dart';

enum AdminApprovalPhase {
  idle,
  loading,
  reviewReady,
  deciding,
  approved,
  denied,
  failed,
  dismissed,
}

final class AdminApprovalController extends ChangeNotifier {
  AdminApprovalController(this._port);

  final AdminLoginApprovalPort _port;
  AdminApprovalLink? _link;
  AdminApprovalReview? _review;
  AdminApprovalPhase _phase = AdminApprovalPhase.idle;
  int _generation = 0;

  AdminApprovalPhase get phase => _phase;
  AdminApprovalReview? get review => _review;
  bool get isVisible =>
      _phase != AdminApprovalPhase.idle &&
      _phase != AdminApprovalPhase.dismissed;
  bool get hasEphemeralCredential => _link?.hasCredential ?? false;

  Future<void> begin(Uri uri) async {
    final generation = ++_generation;
    _clearLink();
    _review = null;
    try {
      final link = parseAdminApprovalLink(uri);
      _link = link;
      _phase = AdminApprovalPhase.loading;
      notifyListeners();
      await _port.prove(
        requestId: link.requestId,
        approvalToken: link.approvalToken,
      );
      if (!_isCurrent(generation, link)) return;
      final review = await _port.review(
        requestId: link.requestId,
        approvalToken: link.approvalToken,
      );
      if (!_isCurrent(generation, link)) return;
      _review = review;
      _phase = AdminApprovalPhase.reviewReady;
      notifyListeners();
    } on Object {
      if (generation != _generation) return;
      _clearLink();
      _review = null;
      _phase = AdminApprovalPhase.failed;
      notifyListeners();
    }
  }

  Future<void> decide({required bool approve}) async {
    final link = _link;
    if (link == null || _phase != AdminApprovalPhase.reviewReady) return;
    final generation = _generation;
    _phase = AdminApprovalPhase.deciding;
    notifyListeners();
    try {
      await _port.decide(
        requestId: link.requestId,
        approvalToken: link.approvalToken,
        approve: approve,
      );
      if (!_isCurrent(generation, link)) return;
      _clearLink();
      _review = null;
      _phase = approve
          ? AdminApprovalPhase.approved
          : AdminApprovalPhase.denied;
      notifyListeners();
    } on Object {
      if (generation != _generation) return;
      _clearLink();
      _review = null;
      _phase = AdminApprovalPhase.failed;
      notifyListeners();
    }
  }

  void dismiss() {
    _generation += 1;
    _clearLink();
    _review = null;
    _phase = AdminApprovalPhase.dismissed;
    notifyListeners();
  }

  bool _isCurrent(int generation, AdminApprovalLink link) =>
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
