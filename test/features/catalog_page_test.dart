import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/catalog/catalog_models.dart';
import 'package:providentia_admin/features/catalog/catalog_page.dart';

const _storePricePayload = <String, Object?>{
  'productId': '0198f4e1-7abc-7def-8abc-0123456789ab',
  'packId': '0198f4e2-7abc-7def-8abc-0123456789ab',
  'storeName': 'Central Market',
  'storeLocation': 'Windhoek',
  'price': '12.50',
  'currency': 'NAD',
  'observedOn': '2026-08-24',
};

CatalogQueueItem _item({
  required String type,
  required String status,
  Map<String, Object?>? payload,
}) => CatalogQueueItem.fromJson(<String, Object?>{
  'id': '0198f4e3-7abc-7def-8abc-0123456789ab',
  'type': type,
  'status': status,
  'revision': 3,
  'payload': payload ?? const <String, Object?>{},
});

Widget _detail(CatalogQueueItem item, {ValueChanged<bool>? onDecision}) =>
    MaterialApp(
      home: Scaffold(
        body: CatalogModerationDetail(
          item: item,
          isContribution: true,
          canReview: true,
          canCurate: true,
          preview: null,
          onDecision: onDecision ?? (_) {},
          onPreview: () {},
          onLinkProposal: () {},
          onPublishImage: () {},
        ),
      ),
    );

void main() {
  testWidgets('renders labeled store-price facts and revision decisions', (
    tester,
  ) async {
    final decisions = <bool>[];
    await tester.pumpWidget(
      _detail(
        _item(
          type: 'store_price',
          status: 'pending',
          payload: _storePricePayload,
        ),
        onDecision: decisions.add,
      ),
    );

    expect(find.text('Central Market · NAD 12.50'), findsOneWidget);
    expect(find.text('Store: Central Market'), findsOneWidget);
    expect(find.text('Location: Windhoek'), findsOneWidget);
    expect(find.text('Price: NAD 12.50'), findsOneWidget);
    expect(find.text('Observed on: 2026-08-24'), findsOneWidget);
    expect(
      find.text('Product ID: 0198f4e1-7abc-7def-8abc-0123456789ab'),
      findsOneWidget,
    );
    expect(
      find.text('Pack ID: 0198f4e2-7abc-7def-8abc-0123456789ab'),
      findsOneWidget,
    );
    expect(find.textContaining('payload:'), findsNothing);
    expect(find.byKey(const Key('link-product-proposal')), findsNothing);
    expect(find.byKey(const Key('publish-verified-image')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('approve-moderation-item')),
    );
    await tester.tap(find.byKey(const Key('approve-moderation-item')));
    await tester.tap(find.byKey(const Key('reject-moderation-item')));
    expect(decisions, <bool>[true, false]);
  });

  testWidgets('approved store price exposes no incompatible curator action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _detail(
        _item(
          type: 'store_price',
          status: 'approved',
          payload: _storePricePayload,
        ),
      ),
    );

    expect(find.byKey(const Key('approve-moderation-item')), findsNothing);
    expect(find.byKey(const Key('reject-moderation-item')), findsNothing);
    expect(find.byKey(const Key('link-product-proposal')), findsNothing);
    expect(find.byKey(const Key('publish-verified-image')), findsNothing);
    expect(
      find.byKey(const Key('store-price-publication-boundary')),
      findsOneWidget,
    );
  });

  testWidgets('curator actions are exact to compatible contribution type', (
    tester,
  ) async {
    await tester.pumpWidget(
      _detail(_item(type: 'product_identity', status: 'approved')),
    );
    expect(find.byKey(const Key('link-product-proposal')), findsOneWidget);
    expect(find.byKey(const Key('publish-verified-image')), findsNothing);

    await tester.pumpWidget(
      _detail(_item(type: 'product_image', status: 'approved')),
    );
    expect(find.byKey(const Key('link-product-proposal')), findsNothing);
    expect(find.byKey(const Key('publish-verified-image')), findsOneWidget);
  });
}
