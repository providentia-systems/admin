#!/usr/bin/env python3
"""Apply catalog editor improvements using existing permissions and endpoints."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess

# Match the backend-owned additive contract change byte for byte.
archive = Path('contracts/source/providentia-v1.json.gz')
old_zip = archive.read_bytes()
old_json = gzip.decompress(old_zip)
contract = json.loads(old_json)
operation = contract['paths']['/api/v1/catalog-admin/entities/{entityType}']['get']
parameters = operation.setdefault('parameters', [])
if not any(p.get('name') == 'q' and p.get('in') == 'query' for p in parameters):
    parameters.append({'name': 'q', 'in': 'query', 'required': False,
        'description': 'Literal, case-insensitive identity search applied before offset pagination. Empty text lists all authorized records.',
        'schema': {'type': 'string', 'maxLength': 191, 'default': ''}})
    new_json = (json.dumps(contract, ensure_ascii=False, indent=2) + '\n').encode()
    new_zip = gzip.compress(new_json, mtime=0)
    archive.write_bytes(new_zip)
    Path('contracts/providentia-v1.json').write_bytes(new_json)
    replacements = {hashlib.sha256(old_json).hexdigest(): hashlib.sha256(new_json).hexdigest(),
                    hashlib.sha256(old_zip).hexdigest(): hashlib.sha256(new_zip).hexdigest()}
    for filename in subprocess.check_output(['git', 'ls-files'], text=True).splitlines():
        p = Path(filename)
        if not p.is_file() or p == archive or filename.endswith('providentia-v1.json') or 'handover-next.py' in filename:
            continue
        try:
            text = p.read_text()
        except (UnicodeError, OSError):
            continue
        updated = text
        for before, after in replacements.items():
            updated = updated.replace(before, after)
        if updated != text:
            p.write_text(updated)
            print('Updated contract digest pin:', filename)
    print('Paired contract hashes:', json.dumps(replacements))

p = Path('lib/features/catalog/catalog_maintenance_repository.dart')
s = p.read_text()
if 'String query = ' not in s:
    s = s.replace('    int offset = 0,', "    int offset = 0,\n    String query = '',", 1)
    s = s.replace("        'offset': '$offset',", "        'offset': '$offset',\n        if (query.trim().isNotEmpty) 'q': query.trim(),", 1)
p.write_text(s)

# A reason remains visible and explicit, but ordinary corrections do not need
# repetitive typing. Selecting Other still requires actual explanatory text.
Path('lib/features/catalog/catalog_reason_field.dart').write_text('''import 'package:flutter/material.dart';

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
        ? widget.controller.text : 'Other';
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
        items: [for (final reason in _reasons)
          DropdownMenuItem(value: reason,
              child: Text(reason, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: !widget.enabled ? null : (value) {
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
              labelText: 'Explain the reason', helperText: 'Required when Other is selected.'),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter a reason.' : null,
        ),
      ],
    ],
  );
}
''')
p = Path('lib/features/catalog/catalog_maintenance_page.dart')
s = p.read_text()
if "import 'catalog_reason_field.dart';" not in s:
    s = s.replace("import 'catalog_maintenance_repository.dart';", "import 'catalog_maintenance_repository.dart';\nimport 'catalog_reason_field.dart';")
    s = s.replace('  int _offset = 0;', '''  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _contexts = <String, ({String query, int offset, double scroll})>{};
  int _offset = 0;''', 1)
    s = s.replace('    widget.session.removeListener(_authorizationChanged);', '    widget.session.removeListener(_authorizationChanged);\n    _query.dispose();\n    _scroll.dispose();', 1)
    s = s.replace('        productId: widget.productId,\n      );', '        productId: widget.productId,\n        query: _query.text,\n      );', 1)
    s = s.replace('    final epoch = widget.session.authorizationEpoch;\n    await showDialog<void>(', '    if (!widget.canCurate || _busy) return;\n    final epoch = widget.session.authorizationEpoch;\n    await showDialog<void>(', 1)
    s = s.replace('    await showDialog<void>(\n      context: context,', '    await showDialog<void>(\n      context: context,\n      barrierDismissible: false,', 1)
    pos = s.index('  @override\n  Widget build(BuildContext context) => Scaffold(')
    s = s[:pos] + '''  void _selectType(String type) {
    if (_busy || type == _type) return;
    _contexts[_type] = (query: _query.text, offset: _offset,
        scroll: _scroll.hasClients ? _scroll.offset : 0);
    final previous = _contexts[type];
    setState(() {
      _type = type;
      _query.text = previous?.query ?? '';
      _offset = previous?.offset ?? 0;
    });
    unawaited(_load().then((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo((previous?.scroll ?? 0).clamp(0, _scroll.position.maxScrollExtent));
      }
    }));
  }

  void _search() {
    if (_busy) return;
    if (_query.text.runes.length > 191) {
      setState(() => _error = 'Search text must not exceed 191 characters.');
      return;
    }
    setState(() => _offset = 0);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_load());
  }

''' + s[pos:]
    a = s.index('          Row(\n            children: [')
    b = s.index('          if (_busy)', a)
    s = s[:a] + '''          const SizedBox(height: 24),
          if (widget.productId == null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 16, runSpacing: 12, children: [
                ChoiceChip(label: const Text('Products'), selected: _type == 'product',
                    onSelected: _busy ? null : (_) => _selectType('product')),
                ChoiceChip(label: const Text('Categories'), selected: _type == 'category',
                    onSelected: _busy ? null : (_) => _selectType('category')),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 16, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 240, child: DropdownButtonFormField<String>(
                  key: ValueKey(_type),
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Catalog entity'),
                  items: [for (final type in catalogEntityFields.keys)
                    if (widget.productId == null || type != 'identity-rule')
                      DropdownMenuItem(value: type, child: Text(type)),
                  ],
                  onChanged: _busy ? null : (value) {
                    if (value != null) _selectType(value);
                  },
                )),
                if (widget.canCurate && (widget.productId == null ||
                    !const {'product', 'category', 'unit'}.contains(_type)))
                  FilledButton.icon(onPressed: _busy ? null : () => _edit(),
                      icon: const Icon(Icons.add), label: Text('Add $_type')),
                IconButton(onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('catalog-entity-search'),
            controller: _query,
            enabled: !_busy,
            textInputAction: TextInputAction.search,
            maxLength: 191,
            decoration: InputDecoration(
              labelText: 'Search $_type records',
              helperText: 'Searches all matching records, including archived identities.',
              suffixIcon: IconButton(onPressed: _busy ? null : _search,
                  tooltip: 'Search catalog records', icon: const Icon(Icons.search)),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 16),
''' + s[b:]
    s = s.replace('            child: ListView(\n              children:', "            child: ListView(\n              controller: _scroll,\n              children:", 1)
    s = s.replace('                  ListTile(\n                    title:', "                  ListTile(\n                    key: ValueKey(row.id),\n                    title:", 1)
    s = s.replace('            children: [\n              TextButton(', '            children: [\n              TextButton(', 1)
    # Guard unsaved intent without introducing another editor or mutation path.
    marker = '  final Map<String, List<CatalogEntity>> _references = {};'
    s = s.replace(marker, marker + '''
  late final Map<String, String> _initialFields;
  bool _allowExit = false;
  bool _confirmingExit = false;
  bool get _dirty => _fields.entries.any((entry) =>
      entry.value.text != _initialFields[entry.key]);
''')
    marker = '    widget.session.addListener(_revoke);'
    s = s.replace(marker, '''    _initialFields = {for (final entry in _fields.entries) entry.key: entry.value.text};
    for (final field in _fields.values) { field.addListener(_fieldChanged); }
''' + marker, 1)
    pos = s.index('  void _revoke()')
    s = s[:pos] + '''  void _fieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _close() async {
    if (_busy || _confirmingExit) return;
    if (_dirty) {
      _confirmingExit = true;
      final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Your catalog changes have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard changes')),
        ],
      ));
      _confirmingExit = false;
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowExit = true);
    Navigator.pop(context);
  }

''' + s[pos:]
    s = s.replace('    if (_reason.text.trim().isEmpty) {', '    if (_reason.text.trim().isEmpty || _reason.text.runes.length > 500) {', 1)
    s = s.replace("setState(() => _error = 'Enter an audit reason.');", "setState(() => _error = 'Enter an audit reason of no more than 500 characters.');", 1)
    s = s.replace('        Navigator.pop(context);', '        setState(() => _allowExit = true);\n        Navigator.pop(context);', 1)
    s = s.replace('  Widget build(BuildContext context) => AlertDialog(\n', '''  Widget build(BuildContext context) => PopScope(
    canPop: _allowExit || (!_busy && !_dirty),
    onPopInvokedWithResult: (didPop, _) { if (!didPop) unawaited(_close()); },
    child: AlertDialog(
''', 1)
    s = s.replace('      width: 520,\n      child: SingleChildScrollView(', '''      width: 560,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight:
            (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * .65),
        child: SingleChildScrollView(''', 1)
    s = s.replace('            for (final entry in _fields.entries)\n              if (entry.key.endsWith(\'Id\'))', '''            for (final entry in _fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: entry.key.endsWith('Id') ?''', 1)
    s = s.replace('                )\n              else\n                TextField(', '                )\n              : TextField(', 1)
    old = '''                ),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Audit reason'),
            ),'''
    new = '''                ),
              ),
            const SizedBox(height: 8),
            CatalogReasonField(controller: _reason,
                creating: widget.entity == null, enabled: !_busy),'''
    assert old in s
    s = s.replace(old, new, 1)
    s = s.replace('''    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),''', '''    actions: [
      TextButton(
        onPressed: _busy ? null : _close,''', 1)
    # Close both newly added wrappers at their corresponding structural boundary.
    s = s.replace('''    actions: [
      TextButton(
        onPressed: _busy ? null : _close,''', '''    actions: [
      TextButton(
        onPressed: _busy ? null : _close,''')
    s = s.replace('''        ),
      ),
    ),
    actions: [''', '''        ),
      ),
      ),
    ),
    actions: [''', 1)
    s = s.replace('''    ],
  );
  String _label''', '''    ],
    ),
  );
  String _label''', 1)
    p.write_text(s)

Path('test/features/catalog_reason_field_test.dart').write_text('''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/catalog/catalog_reason_field.dart';

void main() {
  testWidgets('ordinary edits have a visible default and Other requires text', (tester) async {
    final reason = TextEditingController();
    addTearDown(reason.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CatalogReasonField(
      controller: reason, creating: false,
    ))));
    expect(reason.text, 'Correct catalog details');
    await tester.tap(find.byKey(const Key('catalog-reason-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    expect(reason.text, isEmpty);
    final input = find.byKey(const Key('catalog-reason-other'));
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Owner-reviewed identity correction');
    expect(reason.text, 'Owner-reviewed identity correction');
    expect(tester.widget<TextFormField>(input).validator!('  '), 'Enter a reason.');
  });

  testWidgets('creation reasons are contextual and existing custom text is preserved', (tester) async {
    final reason = TextEditingController(text: 'Existing explanation');
    addTearDown(reason.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CatalogReasonField(
      controller: reason, creating: true, enabled: false,
    ))));
    expect(reason.text, 'Existing explanation');
    expect(find.byKey(const Key('catalog-reason-other')), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byKey(const Key('catalog-reason-other'))).enabled, isFalse);
  });
}
''')
Path('docs/catalog-editor-workflow.md').write_text('''# Direct catalog maintenance

The existing Manage catalog entities screen provides direct Products and
Categories choices, server-side search, paged results and row-to-editor access.
Add product/category uses the same existing revision-checked maintenance API.
Switching entity types retains each type's query and page; saving returns to
that list rather than a different search workflow. Packs, variants, aliases,
barcodes, units and rules remain available without duplicating editor logic.

Editor fields have 16-pixel spacing, bounded scrollable content and the existing
wrapping dialog actions. Closing a changed editor requires an explicit discard
choice. Unknown mutation outcomes still require reload before retrying.

Catalog reasons use contextual choices; Other requires a nonblank explanation,
limited to the existing 500-character contract. These controls do not weaken
revision, authorization or audit requirements. Unchanged global identities and
household products remain separate resources.
''')
print('Direct catalog editor search, context, spacing, reasons and discard guards applied.')
