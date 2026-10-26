import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/app/admin_layout.dart';
import 'package:providentia_admin/app/theme.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/workspace/operator_image.dart';
import 'package:providentia_admin/features/workspace/operator_records_page.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

Future<SessionController> _session() async {
  final store = MemoryCredentialStore(installationId: memoryInstallationId)
    ..session = memoryStoredSession();
  final session = SessionController(
    credentialStore: store,
    api: FakeApi(
      (_) async => jsonResponse({
        'userId': store.session['userId'],
        'profile': {
          'administratorAccess': {
            'features': {'homes.read': true, 'audit.read': true},
          },
        },
      }),
    ),
  );
  await session.restore();
  addTearDown(session.dispose);
  return session;
}

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
  test(
    'identifier columns include snake/camel IDs without false positives',
    () {
      expect(isAdminIdentifierColumn('id'), isTrue);
      expect(isAdminIdentifierColumn('subject_id'), isTrue);
      expect(isAdminIdentifierColumn('homeId'), isTrue);
      expect(isAdminIdentifierColumn('paid'), isFalse);
      expect(isAdminIdentifierColumn('valid'), isFalse);
    },
  );

  for (final size in <Size>[const Size(720, 700), const Size(1440, 900)]) {
    testWidgets(
      'operator table exposes complete identifiers and horizontal navigation at ${size.width.toInt()}px',
      (tester) async {
        const completeId =
            '018f47ec-49f8-7c70-9f9b-1234567890ab-complete-identifier';
        final api = FakeApi(
          (_) async => jsonResponse({
            'data': [
              {
                'id': completeId,
                'subject_id': '018f47ec-49f8-7c70-9f9b-fedcba098765-subject',
                'action': 'group.assigned',
                'actor': 'operator@example.test',
                'country': 'Namibia',
                'scope': 'home',
                'revision': 42,
                'occurred_at': '2026-09-10T00:00:00Z',
                'metadata': {
                  'safe': true,
                  'reason': 'Regression coverage for wide operator tables',
                },
              },
            ],
          }),
        );
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAdminTheme(),
            home: Scaffold(
              body: OperatorRecordsPage(
                session: await _session(),
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

        expect(find.byType(AdminDataTableViewport), findsOneWidget);
        expect(
          find.text('Scroll horizontally to view every column.'),
          findsOneWidget,
        );
        expect(find.text(completeId), findsOneWidget);
        final identifierCell = tester
            .widgetList<AdminTableCell>(find.byType(AdminTableCell))
            .singleWhere((cell) => cell.value == completeId);
        expect(identifierCell.identifier, isTrue);

        final horizontal = tester.widget<Scrollbar>(
          find.byKey(
            const ValueKey<String>('admin-table-horizontal-scrollbar'),
          ),
        );
        expect(horizontal.thumbVisibility, isTrue);
        expect(horizontal.trackVisibility, isTrue);
        expect(horizontal.controller!.position.maxScrollExtent, greaterThan(0));
        horizontal.controller!.jumpTo(
          horizontal.controller!.position.maxScrollExtent,
        );
        await tester.pump();
        expect(horizontal.controller!.offset, greaterThan(0));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(720, 700), const Size(1440, 900)]) {
    testWidgets(
      'household product identity precedes raw overrides at ${size.width}px',
      (tester) async {
        final api = FakeApi((request) async {
          if (request.path.endsWith('/image')) {
            return ApiResponse(
              statusCode: 204,
              headers: {},
              bytes: Uint8List(0),
            );
          }
          if (request.path.endsWith('/homes')) {
            return jsonResponse({
              'data': [
                {'id': 'home-a', 'name': 'Family'},
              ],
            });
          }
          if (request.path.endsWith('/home-a')) {
            return jsonResponse({'id': 'home-a', 'name': 'Family'});
          }
          return jsonResponse({
            'data': [
              {
                'id': 'linked',
                'home_id': 'home-a',
                'product_id': 'catalog-rice',
                'private_name': null,
                'original_pack_text': null,
                'name': 'Basmati rice',
                'brand': 'Test brand',
                'pack_text': '5 kg bag',
                'category_name': 'Food',
                'category_scope': 'Global',
                'catalog_reference': 'Catalog linked',
              },
              {
                'id': 'private',
                'home_id': 'home-a',
                'product_id': null,
                'private_name': 'Garden beans',
                'original_pack_text': 'Harvest basket',
                'name': 'Garden beans',
                'brand': '',
                'pack_text': 'Harvest basket',
                'category_name': 'My pantry',
                'category_scope': 'Local',
                'catalog_reference': 'Private product',
              },
              {
                'id': 'broken',
                'home_id': 'home-a',
                'product_id': 'missing-product-id',
                'private_name': null,
                'original_pack_text': null,
                'name': 'Unresolved product',
                'brand': '',
                'pack_text': 'Not specified',
                'category_name': 'Uncategorized',
                'category_scope': '',
                'catalog_reference': 'Missing catalog product',
              },
            ],
          });
        });
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAdminTheme(),
            home: Scaffold(
              body: OperatorRecordsPage(
                session: await _session(),
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
        final table = tester.widget<DataTable>(find.byType(DataTable));
        expect(
          table.columns.take(6).map((column) => (column.label as Text).data),
          [
            'Product',
            'Brand',
            'Pack',
            'Category',
            'Category Scope',
            'Catalog Reference',
          ],
        );
        expect(find.text('Basmati rice'), findsOneWidget);
        expect(find.text('5 kg bag'), findsOneWidget);
        expect(find.text('Garden beans'), findsWidgets);
        expect(find.text('My pantry'), findsOneWidget);
        expect(find.text('Missing catalog product'), findsOneWidget);
        expect(find.text('missing-product-id'), findsOneWidget);
        expect(find.text('No private override'), findsNWidgets(4));
        expect(find.text('Private name override'), findsOneWidget);
        expect(find.text('Private pack override'), findsOneWidget);
        expect(find.text('Edit record'), findsNothing);
        expect(
          api.requests.where((request) => request.method != 'GET'),
          isEmpty,
        );
        expect(
          api.requests
              .where((request) => request.path.contains('/records/'))
              .single
              .path,
          '/api/v1/admin/homes/home-a/records/products',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(720, 700), const Size(1440, 900)]) {
    testWidgets(
      'stock leads with resolved identity and preserves every signed decimal at ${size.width}px',
      (tester) async {
        final api = FakeApi((request) async {
          if (request.path.endsWith('/image')) {
            return ApiResponse(
              statusCode: 204,
              headers: {},
              bytes: Uint8List(0),
            );
          }
          if (request.path.endsWith('/homes')) {
            return jsonResponse({
              'data': [
                {'id': 'home-a', 'name': 'Family'},
              ],
            });
          }
          if (request.path.endsWith('/home-a')) {
            return jsonResponse({'id': 'home-a', 'name': 'Family'});
          }
          if (request.path.endsWith('/records/products')) {
            // This incomplete page must never be used to join stock metadata.
            return jsonResponse({
              'data': [
                {
                  'id': 'linked',
                  'name': 'Stale product page',
                  'category_name': 'Category from incomplete products page',
                },
              ],
            });
          }
          return jsonResponse({
            'data': [
              {
                'home_id': 'home-a',
                'home_product_id': 'linked',
                'quantity': '-1.23456789',
                'revision': 14,
                'last_movement_id': 'movement-linked',
                'checkpoint_id': 'checkpoint-linked',
                'updated_at': '2026-10-26T09:00:00Z',
                'name': 'Basmati rice',
                'brand': 'Test brand',
                'pack_text': '5 kg bag',
                'unit': 'kg',
                'category_name': 'Food',
                'category_scope': 'Global',
                'catalog_reference': 'Catalog linked',
                'home_product_status': 'active',
                'uncertain': true,
                'pending_quantity': '-0.00000001',
              },
              {
                'home_id': 'home-a',
                'home_product_id': 'private',
                'quantity': '0.00000000',
                'revision': 2,
                'name': 'Garden beans',
                'pack_text': '',
                'unit': 'each',
                'catalog_reference': 'Private product',
                'home_product_status': 'active',
                'uncertain': 0,
              },
              {
                'home_id': 'home-a',
                'home_product_id': 'archived',
                'quantity': '0.12500000',
                'revision': 5,
                'name': 'Archived flour',
                'pack_text': '2 kg bag',
                'unit': 'each',
                'catalog_reference': 'Catalog linked',
                'home_product_status': 'archived',
                'catalog_product_status': 'archived',
                'catalog_pack_status': 'archived',
                'uncertain': '0',
              },
              {
                'home_id': 'home-a',
                'home_product_id': 'missing-home-product',
                'quantity': '-5.00000000',
                'revision': 3,
                'name': null,
                'pack_text': null,
                'unit': null,
                'category_name': null,
                'catalog_reference': 'Missing home product',
              },
              {
                'home_id': 'home-a',
                'home_product_id': 'legacy-without-metadata',
                'quantity': '0.00000001',
                'revision': 1,
              },
            ],
          });
        });
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAdminTheme(),
            home: Scaffold(
              body: OperatorRecordsPage(
                session: await _session(),
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
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('stock').last);
        await tester.pumpAndSettle();

        final table = tester.widget<DataTable>(find.byType(DataTable));
        expect(
          table.columns.take(7).map((column) => (column.label as Text).data),
          [
            'Product',
            'Pack',
            'Stock unit',
            'Quantity',
            'Evidence',
            'Balance revision',
            'Product reference',
          ],
        );
        expect(table.rows, hasLength(5));
        expect(find.text('Home ID'), findsOneWidget);
        expect(find.text('Household product ID'), findsOneWidget);
        expect(find.text('Catalog product status'), findsOneWidget);
        expect(find.text('Catalog pack status'), findsOneWidget);
        expect(find.text('Basmati rice'), findsOneWidget);
        expect(find.text('5 kg bag'), findsOneWidget);
        expect(find.text('Garden beans'), findsOneWidget);
        expect(find.text('Archived flour'), findsOneWidget);
        expect(find.text('archived'), findsWidgets);
        expect(find.text('Missing home product'), findsOneWidget);
        expect(find.text('Unresolved product'), findsNWidgets(2));
        expect(find.text('Metadata unavailable'), findsOneWidget);
        expect(find.text('Not specified'), findsNWidgets(3));
        expect(find.text('Stale product page'), findsNothing);
        expect(
          find.text('Category from incomplete products page'),
          findsNothing,
        );
        expect(find.text('Unresolved evidence'), findsOneWidget);
        expect(find.text('No unresolved evidence'), findsNWidgets(2));
        for (final quantity in [
          '-1.23456789',
          '0.00000000',
          '0.12500000',
          '-5.00000000',
          '0.00000001',
          '-0.00000001',
        ]) {
          expect(find.text(quantity), findsOneWidget);
        }
        expect(find.text('missing-home-product'), findsOneWidget);
        expect(find.text('movement-linked'), findsOneWidget);
        expect(find.text('checkpoint-linked'), findsOneWidget);
        expect(find.text('2026-10-26T09:00:00Z'), findsOneWidget);
        expect(find.text('Showing 1–5'), findsOneWidget);
        expect(find.text('Edit record'), findsNothing);
        expect(
          api.requests.where((request) => request.method != 'GET'),
          isEmpty,
        );
        expect(
          api.requests.where(
            (request) => request.path.endsWith('/records/products'),
          ),
          hasLength(1),
        );
        final horizontal = tester.widget<Scrollbar>(
          find.byKey(
            const ValueKey<String>('admin-table-horizontal-scrollbar'),
          ),
        );
        expect(horizontal.controller!.position.maxScrollExtent, greaterThan(0));
        horizontal.controller!.jumpTo(
          horizontal.controller!.position.maxScrollExtent,
        );
        await tester.pump();
        expect(horizontal.controller!.offset, greaterThan(0));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('stock paging retains 100-row balance membership and offsets', (
    tester,
  ) async {
    final api = FakeApi((request) async {
      if (request.path.endsWith('/image')) {
        return ApiResponse(statusCode: 204, headers: {}, bytes: Uint8List(0));
      }
      if (request.path.endsWith('/homes')) {
        return jsonResponse({
          'data': [
            {'id': 'home-a', 'name': 'Family'},
          ],
        });
      }
      if (request.path.endsWith('/home-a')) {
        return jsonResponse({'id': 'home-a', 'name': 'Family'});
      }
      if (request.path.endsWith('/records/products')) {
        return jsonResponse({'data': <Object?>[]});
      }
      final offset = int.parse(request.query!['offset']!);
      return jsonResponse({
        'data': [
          for (var index = offset; index < (offset == 0 ? 100 : 101); index++)
            {
              'home_product_id': 'balance-$index',
              'name': 'Product $index',
              'pack_text': 'Not specified',
              'unit': 'each',
              'quantity': index.isEven ? '0.00000000' : '-0.50000000',
              'revision': index + 1,
              'uncertain': false,
              'catalog_reference': 'Private product',
            },
        ],
      });
    });
    await tester.binding.setSurfaceSize(const Size(720, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperatorRecordsPage(
            session: await _session(),
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
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('stock').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DataTable>(find.byType(DataTable)).rows,
      hasLength(100),
    );
    expect(find.text('Showing 1–100'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows, hasLength(1));
    expect(find.text('Product 100'), findsOneWidget);
    expect(find.text('Showing 101–101'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Next'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DataTable>(find.byType(DataTable)).rows,
      hasLength(100),
    );
    expect(
      api.requests
          .where((request) => request.path.endsWith('/records/stock'))
          .map((request) => request.query!['offset']),
      ['0', '100', '0'],
    );
    expect(tester.takeException(), isNull);
  });

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
              session: await _session(),
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
              session: await _session(),
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
