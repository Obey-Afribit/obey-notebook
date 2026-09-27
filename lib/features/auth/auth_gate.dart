import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_controller.dart';
import '../../state/notebook_controller.dart';
import '../home/notebook_home_screen.dart';
import '../shared/ui.dart';
import 'sign_in_screen.dart';
import 'verify_email_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeController themeController = context.watch<ThemeController>();

    final Widget child;
    if (controller.isBootstrapping || themeController.isLoading) {
      child = const _Splash();
    } else if (!controller.isSignedIn) {
      child = const SignInScreen();
    } else if (controller.cloudConfigured && !controller.isVerified) {
      child = const VerifyEmailScreen();
    } else {
      child = const NotebookHomeScreen();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey<Type>(child.runtimeType), child: child),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            BrandMark(size: 76),
            SizedBox(height: 28),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ),
      ),
    );
  }
}
