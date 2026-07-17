import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_config.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_gate.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/local_store_service.dart';
import 'services/ocr_service.dart';
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

  if (AppConfig.hasSupabase) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        // Accepts either an anon key or the newer publishable key.
        publishableKey: AppConfig.supabaseAnonKey,
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
  late final AuthService _authService;
  late final SyncService _syncService;
  late final TemplateService _templateService;
  late final ThemeController _themeController;
  late final SpeechService _speechService;
  late final OcrService _ocrService;
  late final ReminderService _reminderService;
  late final ShareService _shareService;
  late final PrivacyLockService _privacyLockService;
  late final AiService _aiService;
  late final StorageService _storageService;
  late final NotebookController _notebookController;

  @override
  void initState() {
    super.initState();

    _localStoreService = LocalStoreService();
    _authService = AuthService();
    _syncService = SyncService(
      localStore: _localStoreService,
      authService: _authService,
    );
    _templateService = TemplateService(localStore: _localStoreService);
    _themeController = ThemeController(localStore: _localStoreService);
    _speechService = SpeechService();
    _ocrService = OcrService();
    _reminderService = ReminderService();
    _shareService = ShareService();
    _privacyLockService = PrivacyLockService();
    _aiService = AiService();
    _storageService = const StorageService();

    _notebookController = NotebookController(
      authService: _authService,
      localStoreService: _localStoreService,
      syncService: _syncService,
      templateService: _templateService,
      themeController: _themeController,
      speechService: _speechService,
      ocrService: _ocrService,
      reminderService: _reminderService,
      shareService: _shareService,
      privacyLockService: _privacyLockService,
      aiService: _aiService,
      storageService: _storageService,
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
            title: 'Universal Notebook',
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
