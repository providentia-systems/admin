import 'package:flutter/material.dart';

import 'catalog_operations_models.dart';

/// Persistent, typed projection of the existing public product detail response.
class CatalogProductInspection extends StatelessWidget {
  const CatalogProductInspection({
    required this.product,
    required this.onManage,
    this.onAddPack,
    this.onEditPack,
    super.key,
  });
  final CatalogProductDetail product;
  final VoidCallback onManage;
  final VoidCallback? onAddPack;
  final ValueChanged<CatalogPackSummary>? onEditPack;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          product.canonicalName,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text('Brand: ${product.brand.isEmpty ? 'Missing' : product.brand}'),
        Text('Category: ${product.category}'),
        SelectableText('Product: ${product.id}'),
        Text('Published · product revision ${product.revision}'),
        if (product.redirected)
          SelectableText('Redirected from ${product.requestedId}'),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: onManage,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Manage product, packs and identities'),
        ),
        const SizedBox(height: 16),
        Text(
          'Published packs (${product.packs.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (onAddPack != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const Key('add-canonical-pack'),
              onPressed: onAddPack,
              icon: const Icon(Icons.add),
              label: const Text('Add pack size'),
            ),
          ),
          const Text(
            'Keep one product with separate pack options, such as 1 kg and 4 kg.',
          ),
        ],
        if (product.packs.isEmpty)
          const Text(
            'No selectable published pack. Add a pack size to this product.',
          ),
        for (final pack in product.packs)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.packText,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SelectableText('Pack: ${pack.id}'),
                  Text(
                    'Multiplicity: ${pack.multiplicity} · revision ${pack.revision}',
                  ),
                  Text('Amount: ${pack.amount ?? 'Unspecified'}'),
                  Text(
                    'Normalized base amount: ${pack.normalizedBaseAmount ?? 'Unspecified'}',
                  ),
                  if (onEditPack != null)
                    TextButton.icon(
                      key: Key('edit-canonical-pack-${pack.id}'),
                      onPressed: () => onEditPack!(pack),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit pack size'),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Public icons (${product.icons.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (product.icons.isEmpty) const Text('No public icon.'),
        for (final icon in product.icons)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(icon.altText),
            subtitle: SelectableText(
              '${icon.mediaType} · revision ${icon.revision}\n${icon.assetDigest}',
            ),
          ),
        const Text(
          'Related aliases, variants, barcodes, units and archived identities are in the product master. Conflict review and reversible merge history remain in their existing workbenches.',
        ),
      ],
    ),
  );
}
