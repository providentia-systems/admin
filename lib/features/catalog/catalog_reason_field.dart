import 'package:flutter/material.dart';

class CatalogReasonField extends StatefulWidget {
  const CatalogReasonField({
    required this.controller,
    required this.creating,
    this.enabled = true,
    super.key,
  });
  final TextEditingController controller;
  final bool creating;
  final bool enabled;

  @override
  State<CatalogReasonField> createState() => _CatalogReasonFieldState();
}

class _CatalogReasonFieldState extends State<CatalogReasonField> {
  late final List<String> _reasons = [
    if (widget.creating) 'Add catalog identity' else 'Correct catalog details',
    'Correct a spelling mistake',
    'Update category assignment',
    'Archive an unused identity',
    'Restore an archived identity',
    'Other',
  ];
  late String _selected;

  @override
  void initState() {
    super.initState();
    if (widget.controller.text.isEmpty) {
      widget.controller.text = _reasons.first;
    }
    _selected = _reasons.contains(widget.controller.text)
        ? widget.controller.text
        : 'Other';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      DropdownButtonFormField<String>(
        key: const Key('catalog-reason-choice'),
        initialValue: _selected,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Reason for this change'),
        items: [
          for (final reason in _reasons)
            DropdownMenuItem(
              value: reason,
              child: Text(reason, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: !widget.enabled
            ? null
            : (value) {
                if (value == null) return;
                setState(() {
                  _selected = value;
                  widget.controller.text = value == 'Other' ? '' : value;
                });
              },
      ),
      if (_selected == 'Other') ...[
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('catalog-reason-other'),
          controller: widget.controller,
          enabled: widget.enabled,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Explain the reason',
            helperText: 'Required when Other is selected.',
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Enter a reason.' : null,
        ),
      ],
    ],
  );
}
