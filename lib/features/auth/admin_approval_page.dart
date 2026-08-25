import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_approval_controller.dart';

final class AdminApprovalPage extends StatelessWidget {
  const AdminApprovalPage({required this.controller, super.key});

  final AdminApprovalController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Administrator sign-in approval')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _content(context),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) => switch (controller.phase) {
    AdminApprovalPhase.loading || AdminApprovalPhase.deciding => const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text('Checking the secure administrator sign-in request…'),
      ],
    ),
    AdminApprovalPhase.reviewReady => _review(context),
    AdminApprovalPhase.approved => _outcome(
      context,
      icon: Icons.verified_user,
      message: 'Administrator sign-in approved.',
    ),
    AdminApprovalPhase.denied => _outcome(
      context,
      icon: Icons.block,
      message: 'Administrator sign-in denied.',
    ),
    AdminApprovalPhase.failed => _outcome(
      context,
      icon: Icons.gpp_bad,
      message: 'This administrator sign-in link cannot be used.',
    ),
    AdminApprovalPhase.idle ||
    AdminApprovalPhase.dismissed => const SizedBox.shrink(),
  };

  Widget _review(BuildContext context) {
    final review = controller.review!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Review sign-in request',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        Text('Device: ${review.deviceName}'),
        Text('Platform: ${review.platform}'),
        Text('Requested: ${review.createdAt.toLocal()}'),
        Text('Expires: ${review.expiresAt.toLocal()}'),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            OutlinedButton(
              key: const Key('deny-admin-login'),
              onPressed: () => unawaited(controller.decide(approve: false)),
              child: const Text('Deny'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const Key('approve-admin-login'),
              onPressed: () => unawaited(controller.decide(approve: true)),
              icon: const Icon(Icons.verified_user),
              label: const Text('Approve'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _outcome(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 48),
      const SizedBox(height: 16),
      Text(message, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 24),
      FilledButton(onPressed: controller.dismiss, child: const Text('Close')),
    ],
  );
}
