import 'package:flutter/material.dart';

import '../core/auth/session_controller.dart';

/// Shared spacing for fields and validation content in administrator forms.
///
/// Text fields reserve different amounts of height for counters and validation
/// messages. A real gap between every child keeps those subtexts clear of the
/// next outlined border at every supported text scale and window width.
final class AdminFormFields extends StatelessWidget {
  const AdminFormFields({
    required this.children,
    this.spacing = 20,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    super.key,
  });

  final List<Widget> children;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: crossAxisAlignment,
    children: <Widget>[
      for (var index = 0; index < children.length; index++) ...<Widget>[
        if (index != 0) SizedBox(height: spacing),
        children[index],
      ],
    ],
  );
}

/// A bounded, always-discoverable viewport for wide operator data tables.
///
/// Both scrollbars stay visible on desktop. The short instruction also makes
/// horizontal navigation discoverable to keyboard, mouse-wheel and touchpad
/// users before they interact with the table.
final class AdminDataTableViewport extends StatefulWidget {
  const AdminDataTableViewport({required this.child, super.key});

  final Widget child;

  @override
  State<AdminDataTableViewport> createState() => _AdminDataTableViewportState();
}

class _AdminDataTableViewportState extends State<AdminDataTableViewport> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Semantics(
        label: 'Wide table navigation',
        child: const Row(
          key: ValueKey<String>('admin-table-scroll-hint'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.swap_horiz, size: 18),
            SizedBox(width: 6),
            Flexible(child: Text('Scroll horizontally to view every column.')),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: Scrollbar(
          key: const ValueKey<String>('admin-table-horizontal-scrollbar'),
          controller: _horizontal,
          thumbVisibility: true,
          trackVisibility: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            key: const ValueKey<String>('admin-table-horizontal-scroll-view'),
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: Scrollbar(
              controller: _vertical,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _vertical,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Keeps table values readable and copyable without truncating identifiers.
final class AdminTableCell extends StatelessWidget {
  const AdminTableCell({
    required this.value,
    this.identifier = false,
    super.key,
  });

  final String value;
  final bool identifier;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: identifier ? 260 : 96,
      maxWidth: identifier ? 420 : 320,
    ),
    child: SelectableText(value),
  );
}

bool isAdminIdentifierColumn(String key) {
  final normalized = key.replaceAll('-', '_').toLowerCase();
  return normalized == 'id' ||
      normalized.endsWith('_id') ||
      RegExp(r'Id$').hasMatch(key);
}

/// Shared confirmation for removing unused administrative configuration.
Future<String?> confirmAdministrativeRemoval(
  BuildContext context, {
  required String label,
  required String detail,
  SessionController? session,
}) {
  final epoch = session?.authorizationEpoch;
  var reason = '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      Widget confirmation() => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Remove $label?'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(detail),
                TextField(
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Audit reason'),
                  onChanged: (value) => setState(() => reason = value.trim()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: reason.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, reason),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (session == null) return confirmation();
      return AnimatedBuilder(
        animation: session,
        builder: (_, _) =>
            session.phase == SessionPhase.authenticated &&
                session.authorizationEpoch == epoch
            ? confirmation()
            : const SizedBox.shrink(),
      );
    },
  );
}
