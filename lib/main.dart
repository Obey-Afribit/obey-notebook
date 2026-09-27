import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_config.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_gate.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/local_store_service.dart';
import 'services/privacy_lock_service.dart';
import 'services/reminder_service.dart';
import 'services/share_service.dart';
import 'services/speech_service.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/template_service.dart';
import 'state/notebook_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web: plain URLs instead of "#/". Supabase puts auth tokens in the URL
  // fragment after a password-reset link, and hash routing would clash.
  usePathUrlStrategy();

  if (AppConfig.hasSupabase) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        // Accepts either an anon key or the newer publishable key.
        publishableKey: AppConfig.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          // Implicit flow so an emailed link works on any device. PKCE would
          // require opening the link on the same device that requested it,
          // which fails when a reset requested in the Android app is opened
          // from the phone's mail app (it launches the browser, not the APK).
          authFlowType: AuthFlowType.implicit,
        ),
      );
    } catch (_) {
      // If cloud init fails, the app continues in local-only mode.
    }
  }

  runApp(const UniversalNotebookApp());
}

class UniversalNotebookApp extends StatefulWidget {
  const UniversalNotebookApp({super.key});

  @override
  State<UniversalNotebookApp> createState() => _UniversalNotebookAppState();
}

class _UniversalNotebookAppState extends State<UniversalNotebookApp> {
  late final LocalStoreService _localStoreService;
  late final ThemeController _themeController;
  late final NotebookController _notebookController;

  @override
  void initState() {
    super.initState();

    _localStoreService = LocalStoreService();
    final AuthService authService = AuthService();
    _themeController = ThemeController(localStore: _localStoreService);

    _notebookController = NotebookController(
      authService: authService,
      localStoreService: _localStoreService,
      syncService: SyncService(
        localStore: _localStoreService,
        authService: authService,
      ),
      templateService: TemplateService(localStore: _localStoreService),
      themeController: _themeController,
      speechService: SpeechService(),
      reminderService: ReminderService(),
      shareService: ShareService(),
      privacyLockService: PrivacyLockService(),
      aiService: AiService(),
      storageService: const StorageService(),
    );

    _notebookController.initialize();
  }

  @override
  void dispose() {
    _notebookController.dispose();
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: _themeController),
        ChangeNotifierProvider<NotebookController>.value(
          value: _notebookController,
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (BuildContext context, ThemeController theme, _) {
          return MaterialApp(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: theme.lightTheme,
            darkTheme: theme.darkTheme,
            themeMode: theme.themeMode,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}
