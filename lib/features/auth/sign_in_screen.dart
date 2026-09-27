import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../state/notebook_controller.dart';
import '../shared/ui.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  bool _register = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit(NotebookController controller) async {
    if (controller.isBusy || !_formKey.currentState!.validate()) {
      return;
    }
    if (_register) {
      await controller.createAccountWithEmail(
        email: _email.text,
        password: _password.text,
      );
    } else {
      await controller.signInWithEmail(email: _email.text, password: _password.text);
    }
  }

  Future<void> _forgotPassword(NotebookController controller) async {
    final String? email = await showDialog<String>(
      context: context,
      builder: (_) => _ResetDialog(initialEmail: _email.text.trim()),
    );
    if (email != null && email.contains('@')) {
      await controller.sendPasswordReset(email);
    }
  }

  void _toggleMode(NotebookController controller) {
    controller.clearMessages();
    setState(() => _register = !_register);
  }

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();

    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= 920;
          final Widget form = controller.cloudConfigured
              ? _cloudForm(context, controller)
              : _localCard(context, controller);

          final Widget formArea = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!wide) ...<Widget>[
                      const Center(child: BrandMark(size: 72)),
                      const SizedBox(height: 16),
                      Text(
                        AppConfig.appName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 28),
                    ],
                    form,
                  ],
                ),
              ),
            ),
          );

          if (!wide) {
            return SafeArea(child: formArea);
          }
          return Row(
            children: <Widget>[
              const Expanded(flex: 5, child: _BrandPanel()),
              Expanded(flex: 6, child: SafeArea(child: formArea)),
            ],
          );
        },
      ),
    );
  }

  Widget _cloudForm(BuildContext context, NotebookController controller) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _register ? 'Create your account' : 'Welcome back',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _register
                  ? 'One account keeps your notes in sync on every device.'
                  : 'Sign in to pick up where you left off.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              validator: (String? value) {
                final String text = value?.trim() ?? '';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
                  return 'Enter a valid email address.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              focusNode: _passwordFocus,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: <String>[
                _register ? AutofillHints.newPassword : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                helperText: _register ? 'At least 6 characters' : null,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onFieldSubmitted: (_) => _submit(controller),
              validator: (String? value) {
                if ((value ?? '').length < 6) {
                  return 'Password must be at least 6 characters.';
                }
                return null;
              },
            ),
            if (!_register)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: controller.isBusy ? null : () => _forgotPassword(controller),
                  child: const Text('Forgot password?'),
                ),
              )
            else
              const SizedBox(height: 16),
            if (controller.error != null) ...<Widget>[
              _MessageBox(
                icon: Icons.error_outline,
                text: controller.error!,
                background: scheme.errorContainer,
                foreground: scheme.onErrorContainer,
              ),
              const SizedBox(height: 14),
            ],
            if (controller.notice != null) ...<Widget>[
              _MessageBox(
                icon: Icons.mark_email_read_outlined,
                text: controller.notice!,
                background: scheme.tertiaryContainer,
                foreground: scheme.onTertiaryContainer,
              ),
              const SizedBox(height: 14),
            ],
            FilledButton(
              onPressed: controller.isBusy ? null : () => _submit(controller),
              child: controller.isBusy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Text(_register ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  _register ? 'Already have an account?' : 'New here?',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                TextButton(
                  onPressed: controller.isBusy ? null : () => _toggleMode(controller),
                  child: Text(_register ? 'Sign in' : 'Create an account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _localCard(BuildContext context, NotebookController controller) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Your notebook', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'This build has no cloud sync configured, so notes are kept on this '
          'device only.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: controller.isBusy ? null : controller.continueInLocalMode,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Open notebook'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: controller.isBusy ? null : controller.retryCloudSetup,
          child: const Text('Retry cloud connection'),
        ),
        if (controller.error != null) ...<Widget>[
          const SizedBox(height: 14),
          _MessageBox(
            icon: Icons.error_outline,
            text: controller.error!,
            background: theme.colorScheme.errorContainer,
            foreground: theme.colorScheme.onErrorContainer,
          ),
        ],
      ],
    );
  }
}

class _ResetDialog extends StatefulWidget {
  const _ResetDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  late final TextEditingController _input =
      TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_reset),
      title: const Text('Reset your password'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              "We'll email you a link. It opens the web version of the notebook, "
              'where you choose a new password. Then sign in here with it.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              onSubmitted: (String value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_input.text),
          child: const Text('Send link'),
        ),
      ],
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: foreground, height: 1.4))),
        ],
      ),
    );
  }
}

/// Charcoal brand panel shown beside the form on wide screens.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    const Color ink = Color(0xFFF4EFE9);
    const Color muted = Color(0xFFB9B1A7);

    Widget point(IconData icon, String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: kBrandOrange.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: kBrandOrange, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: text.titleSmall?.copyWith(color: ink)),
                  const SizedBox(height: 3),
                  Text(body, style: text.bodyMedium?.copyWith(color: muted)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: kBrandCharcoal,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 48, 48, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const BrandMark(size: 44),
                  const SizedBox(width: 14),
                  Text(
                    AppConfig.appName,
                    style: text.titleLarge?.copyWith(color: ink),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'Think it.\nCapture it.\nFind it anywhere.',
                style: text.displaySmall?.copyWith(color: ink, height: 1.15),
              ),
              const SizedBox(height: 36),
              point(Icons.devices_outlined, 'On every device',
                  'Android, Windows and the web, kept in sync automatically.'),
              point(Icons.checklist, 'Lists that work',
                  'Checklists, reminders, colours, tags and folders.'),
              point(Icons.photo_camera_outlined, 'Photos in your notes',
                  'Snap or attach images right where you are writing.'),
              const Spacer(),
              Text(
                'Version ${AppConfig.appVersion}',
                style: text.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
