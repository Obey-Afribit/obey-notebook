import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/notebook_controller.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isRegisterMode = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(NotebookController controller) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    if (_isRegisterMode) {
      await controller.createAccountWithEmail(email: email, password: password);
    } else {
      await controller.signInWithEmail(email: email, password: password);
    }
  }

  Widget _buildCloudSignInCard(
    BuildContext context,
    NotebookController controller,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _isRegisterMode ? 'Create Account' : 'Sign In',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (String? value) {
              final String text = value?.trim() ?? '';
              if (text.isEmpty || !text.contains('@')) {
                return 'Enter a valid email address.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            validator: (String? value) {
              final String text = value ?? '';
              if (text.length < 6) {
                return 'Password must be at least 6 characters.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: controller.isBusy ? null : () => _submit(controller),
            child: Text(_isRegisterMode ? 'Register' : 'Sign In'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: controller.isBusy
                ? null
                : () {
                    setState(() {
                      _isRegisterMode = !_isRegisterMode;
                    });
                  },
            child: Text(
              _isRegisterMode
                  ? 'Already have an account? Sign in'
                  : 'No account yet? Register',
            ),
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
    );
  }

  Widget _buildOfflineModeCard(
    BuildContext context,
    NotebookController controller,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Continue In Local Mode',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Cloud sign-in is unavailable because cloud sync is not configured for this build. '
          'You can continue with local notebooks now and enable cloud sync later.',
        ),
        if ((controller.cloudStatusMessage ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                controller.cloudStatusMessage!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed:
              controller.isBusy ? null : () => controller.continueInLocalMode(),
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('Enter Local Notebook'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed:
              controller.isBusy ? null : () => controller.retryCloudSetup(),
          child: const Text('Retry Cloud Setup'),
        ),
        const SizedBox(height: 12),
        Text(
          'To enable cloud auth: pass SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define, then rebuild.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (controller.error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            controller.error!,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Universal Notebook')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: controller.cloudConfigured
                  ? _buildCloudSignInCard(context, controller)
                  : _buildOfflineModeCard(context, controller),
            ),
          ),
        ),
      ),
    );
  }
}
