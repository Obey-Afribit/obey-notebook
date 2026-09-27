import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/notebook_controller.dart';
import '../shared/ui.dart';

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: BrandMark(size: 64)),
                  const SizedBox(height: 24),
                  Icon(Icons.mark_email_unread_outlined, size: 44, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Confirm your email',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a link to ${controller.accountEmail ?? 'your inbox'}. '
                    'Open it, then come back and continue.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: controller.isBusy ? null : controller.refreshVerificationStatus,
                    child: const Text("I've confirmed, continue"),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: controller.isBusy ? null : controller.resendVerificationEmail,
                    child: const Text('Send the email again'),
                  ),
                  TextButton(
                    onPressed: controller.isBusy ? null : controller.signOut,
                    child: const Text('Use a different account'),
                  ),
                  if (controller.error != null || controller.notice != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      controller.error ?? controller.notice!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: controller.error != null ? scheme.error : scheme.tertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
