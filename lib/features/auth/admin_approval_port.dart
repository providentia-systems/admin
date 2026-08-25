import '../../core/api/api_client.dart';

final class AdminApprovalProof {
  const AdminApprovalProof({required this.requestId, required this.expiresAt});

  factory AdminApprovalProof.fromJson(
    Map<String, Object?> json, {
    required String expectedRequestId,
  }) {
    if (json['valid'] != true ||
        json['requestId'] != expectedRequestId ||
        json['applicationKind'] != 'admin') {
      throw const FormatException('Admin approval proof binding mismatch.');
    }
    final expiresAt = DateTime.parse(json['expiresAt']! as String).toUtc();
    if (!expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Admin approval proof expired.');
    }
    return AdminApprovalProof(
      requestId: expectedRequestId,
      expiresAt: expiresAt,
    );
  }

  final String requestId;
  final DateTime expiresAt;
}

final class AdminApprovalReview {
  const AdminApprovalReview({
    required this.requestId,
    required this.deviceName,
    required this.platform,
    required this.createdAt,
    required this.expiresAt,
  });

  factory AdminApprovalReview.fromJson(
    Map<String, Object?> json, {
    required String expectedRequestId,
  }) {
    final deviceName = json['deviceName'];
    final platform = json['platform'];
    if (json['requestId'] != expectedRequestId ||
        json['applicationKind'] != 'admin' ||
        deviceName is! String ||
        deviceName.isEmpty ||
        deviceName.length > 200 ||
        platform is! String ||
        platform.isEmpty ||
        platform.length > 64) {
      throw const FormatException('Admin approval review binding mismatch.');
    }
    final createdAt = DateTime.parse(json['createdAt']! as String).toUtc();
    final expiresAt = DateTime.parse(json['expiresAt']! as String).toUtc();
    if (!expiresAt.isAfter(DateTime.now().toUtc()) ||
        expiresAt.isBefore(createdAt)) {
      throw const FormatException('Admin approval review expiry was invalid.');
    }
    return AdminApprovalReview(
      requestId: expectedRequestId,
      deviceName: deviceName,
      platform: platform,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  final String requestId;
  final String deviceName;
  final String platform;
  final DateTime createdAt;
  final DateTime expiresAt;
}

abstract interface class AdminLoginApprovalPort {
  Future<AdminApprovalProof> prove({
    required String requestId,
    required String approvalToken,
  });
  Future<AdminApprovalReview> review({
    required String requestId,
    required String approvalToken,
  });
  Future<void> decide({
    required String requestId,
    required String approvalToken,
    required bool approve,
  });
}

final class HttpAdminLoginApprovalPort implements AdminLoginApprovalPort {
  const HttpAdminLoginApprovalPort(this._api);

  final AdminApi _api;

  Map<String, Object?> _proofBody(String approvalToken) => <String, Object?>{
    'applicationKind': 'admin',
    'approvalToken': approvalToken,
  };

  @override
  Future<AdminApprovalProof> prove({
    required String requestId,
    required String approvalToken,
  }) async {
    final response = await _api.postPublic(
      '/api/v1/auth/login-links/$requestId/proof',
      body: _proofBody(approvalToken),
    );
    return AdminApprovalProof.fromJson(
      response.jsonObject,
      expectedRequestId: requestId,
    );
  }

  @override
  Future<AdminApprovalReview> review({
    required String requestId,
    required String approvalToken,
  }) async {
    final response = await _api.postPublic(
      '/api/v1/auth/login-links/$requestId/review',
      body: _proofBody(approvalToken),
    );
    return AdminApprovalReview.fromJson(
      response.jsonObject,
      expectedRequestId: requestId,
    );
  }

  @override
  Future<void> decide({
    required String requestId,
    required String approvalToken,
    required bool approve,
  }) async {
    final response = await _api.postPublic(
      '/api/v1/auth/login-links/$requestId/decision',
      body: <String, Object?>{
        ..._proofBody(approvalToken),
        'decision': approve ? 'approve' : 'deny',
      },
    );
    final json = response.jsonObject;
    if (json['requestId'] != requestId ||
        json['applicationKind'] != 'admin' ||
        json['status'] != 'received') {
      throw const FormatException('Admin approval receipt binding mismatch.');
    }
  }
}
