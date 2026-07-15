import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_controller.dart';
import '../../state/notebook_controller.dart';
import '../home/notebook_home_screen.dart';
import 'sign_in_screen.dart';
import 'verify_email_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeController themeController = context.watch<ThemeController>();

    if (controller.isBootstrapping || themeController.isLoading) {
      return const _LoadingScreen();
    }

    if (!controller.isSignedIn) {
      return const SignInScreen();
    }

    if (controller.cloudConfigured && !controller.isVerified) {
      return const VerifyEmailScreen();
    }

    return const NotebookHomeScreen();
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
