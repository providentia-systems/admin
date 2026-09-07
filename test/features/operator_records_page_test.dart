import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';
import 'package:providentia_admin/features/workspace/operator_image.dart';
import 'package:providentia_admin/features/workspace/operator_records_page.dart';

import '../support/fake_api.dart';

Uint8List _png() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4AWP4DwABAgEAff+B1AAAAABJRU5ErkJggg==',
);
ApiResponse _image(
  Uint8List bytes, {
  String type = 'image/png',
  String cache = 'private, no-store',
}) => ApiResponse(
  statusCode: 200,
  headers: {'content-type': type, 'cache-control': cache},
  bytes: bytes,
);
void main() {
  testWidgets(
    'home inspection uses operator routes and limits people collections to delegated access',
    (tester) async {
      final api = FakeApi((r) async {
        if (r.path.endsWith('/image')) {
          return ApiResponse(statusCode: 204, headers: {}, bytes: Uint8List(0));
        }
        if (r.path.endsWith('/homes')) {
          return jsonResponse({
            'data': [
              {'id': 'home-a', 'name': 'Family', 'description': 'Private home'},
            ],
          });
        }
        if (r.path.endsWith('/home-a')) {
          return jsonResponse({
            'id': 'home-a',
            'name': 'Family',
            'description': 'Private home',
            'access': {'groupName': 'Starter'},
          });
        }
        return jsonResponse({
          'data': [
            {'id': 'product', 'name': 'Rice', 'quantity': 5},
          ],
        });
      });
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperatorRecordsPage(
              api: api,
              authorization: OperatorAuthorization.fromPermissions([
                'homes.read',
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open Family'));
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Group: Starter'), findsOneWidget);
      expect(find.text('Change group'), findsNothing);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('memberships'), findsNothing);
      expect(find.text('invitations'), findsNothing);
      await tester.tap(find.text('stock').last);
      await tester.pumpAndSettle();
      expect(
        api.requests.last.path,
        '/api/v1/admin/homes/home-a/records/stock',
      );
      expect(
        api.requests.every((r) => !r.path.startsWith('/api/v1/homes')),
        isTrue,
      );
      await tester.tap(find.byTooltip('All homes'));
      await tester.pumpAndSettle();
      expect(find.text('Search homes'), findsOneWidget);
    },
  );
  testWidgets(
    'audit view displays backend projection and can reload after an error',
    (tester) async {
      var fail = true;
      final api = FakeApi((r) async {
        if (fail) {
          fail = false;
          throw const ApiException(
            statusCode: 503,
            message: 'Temporarily unavailable',
          );
        }
        return jsonResponse({
          'data': [
            {'action': 'group.assigned', 'subject_id': 'home-a'},
          ],
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperatorRecordsPage(
              api: api,
              authorization: OperatorAuthorization.fromPermissions([
                'audit.read',
              ]),
              audit: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Temporarily unavailable'), findsOneWidget);
      await tester.tap(find.byTooltip('Reload'));
      await tester.pumpAndSettle();
      expect(find.text('group.assigned'), findsOneWidget);
      expect(
        api.requests.every((r) => r.path == '/api/v1/admin/audit-events'),
        isTrue,
      );
    },
  );
  testWidgets(
    'operator image uses authenticated API and clears late responses after disposal',
    (tester) async {
      final response = Completer<ApiResponse>();
      final bytes = _png();
      final api = FakeApi((_) => response.future);
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorImage(
            api: api,
            path: '/api/v1/admin/users/user-a/avatar',
            label: 'Avatar',
            placeholder: Icons.person_outline,
          ),
        ),
      );
      expect(api.requests.single.path, '/api/v1/admin/users/user-a/avatar');
      await tester.pumpWidget(const SizedBox.shrink());
      response.complete(_image(bytes));
      await tester.pumpAndSettle();
      expect(bytes.every((b) => b == 0), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'operator image rejects HTML and cacheable media without rendering it',
    (tester) async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final api = FakeApi((_) async => _image(bytes, type: 'text/html'));
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorImage(
            api: api,
            path: '/api/v1/admin/homes/home-a/image',
            label: 'Home image',
            placeholder: Icons.home_outlined,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(bytes.every((b) => b == 0), isTrue);
    },
  );
}
