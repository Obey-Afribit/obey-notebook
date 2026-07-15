import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/notebook_controller.dart';

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Email')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Check your inbox and click the verification link.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You must verify your email before using sync and sharing.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: controller.isBusy
                        ? null
                        : controller.refreshVerificationStatus,
                    child: const Text('I Have Verified, Continue'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: controller.isBusy
                        ? null
                        : controller.resendVerificationEmail,
                    child: const Text('Resend Verification Email'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed:
                        controller.isBusy ? null : controller.signOut,
                    child: const Text('Sign Out'),
                  ),
                  if (controller.error != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      controller.error!,
                      style: const TextStyle(color: Colors.redAccent),
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
