import 'package:flutter/material.dart';

import '../../services/local_store_service.dart';
import '../../services/theme_pack_service.dart';
import '../models/theme_pack.dart';
import 'color_hex.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({
    required LocalStoreService localStore,
    required ThemePackService themePackService,
  })  : _localStore = localStore,
        _themePackService = themePackService;

  final LocalStoreService _localStore;
  final ThemePackService _themePackService;

  final Map<String, ThemePack> _availableThemes = <String, ThemePack>{};
  final Map<String, String> _downloadFallbackAssets = <String, String>{};

  ThemePack? _currentTheme;
  bool _isLoading = true;
  String? _error;

  ThemePack? get currentTheme => _currentTheme;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<ThemePack> get availableThemes =>
      _availableThemes.values.toList(growable: false);

  Future<void> initialize() async {
    _isLoading = true;
    _availableThemes.clear();
    _downloadFallbackAssets.clear();
    notifyListeners();

    try {
      final Map<String, dynamic> catalog =
          await _themePackService.loadCatalog();
      final List<dynamic> themes =
          catalog['themes'] as List<dynamic>? ?? const <dynamic>[];

      for (final dynamic rawTheme in themes) {
        final Map<String, dynamic> entry =
            (rawTheme as Map<dynamic, dynamic>).map(
          (dynamic key, dynamic value) => MapEntry(key.toString(), value),
        );

        final bool isBuiltIn = entry['isBuiltIn'] == true;
        if (isBuiltIn) {
          final ThemePack builtIn = await _themePackService.loadBuiltInTheme(
            entry['assetPath'] as String,
          );
          _availableThemes[builtIn.id] = builtIn;
          continue;
        }

        final String id = entry['id'] as String;
        final String? fallbackAssetPath = entry['fallbackAssetPath'] as String?;
        if ((fallbackAssetPath ?? '').isNotEmpty) {
          _downloadFallbackAssets[id] = fallbackAssetPath!;
        }

        _availableThemes[id] = ThemePack(
          id: id,
          name: entry['name'] as String,
          description: entry['description'] as String? ?? '',
          seedColorHex: '#1E1E1E',
          backgroundTopHex: '#111111',
          backgroundBottomHex: '#1B1B1B',
          accentHex: '#00E5FF',
          isBuiltIn: false,
          downloadUrl: entry['downloadUrl'] as String?,
        );
      }

      final List<ThemePack> downloaded = _localStore.readDownloadedThemes();
      for (final ThemePack pack in downloaded) {
        _availableThemes[pack.id] = pack;
      }

      final String selectedThemeId = _localStore.readSelectedThemeId() ??
          (catalog['defaultTheme'] as String? ?? 'aurora');

      _currentTheme =
          _availableThemes[selectedThemeId] ?? _availableThemes.values.first;
      _error = null;
    } catch (error) {
      _error = error.toString();
      _currentTheme ??= const ThemePack(
        id: 'fallback',
        name: 'Fallback',
        seedColorHex: '#3DD6D0',
        backgroundTopHex: '#081126',
        backgroundBottomHex: '#133B5C',
        accentHex: '#8E7CFF',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setTheme(String themeId) async {
    final ThemePack? selected = _availableThemes[themeId];
    if (selected == null) {
      return;
    }

    _currentTheme = selected;
    await _localStore.saveSelectedThemeId(themeId);
    notifyListeners();
  }

  Future<void> downloadTheme(String themeId) async {
    final ThemePack? entry = _availableThemes[themeId];
    if (entry == null || entry.downloadUrl == null) {
      return;
    }

    try {
      final ThemePack downloaded = await _themePackService.downloadTheme(
        id: entry.id,
        name: entry.name,
        downloadUrl: entry.downloadUrl!,
        fallbackAssetPath: _downloadFallbackAssets[entry.id],
      );

      _availableThemes[downloaded.id] = downloaded;
      await _localStore.saveDownloadedTheme(downloaded);
      _error = null;
      notifyListeners();
    } catch (error) {
      _error = 'Failed to load theme ${entry.name}: $error';
      notifyListeners();
      rethrow;
    }
  }

  ThemeData buildThemeData() {
    final ThemePack active = _currentTheme ??
        const ThemePack(
          id: 'aurora',
          name: 'Aurora',
          seedColorHex: '#3DD6D0',
          backgroundTopHex: '#081126',
          backgroundBottomHex: '#133B5C',
          accentHex: '#8E7CFF',
        );

    final Color seed = colorFromHex(active.seedColorHex);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: colorFromHex(active.backgroundTopHex),
      appBarTheme: AppBarTheme(
        backgroundColor: colorFromHex(active.backgroundTopHex),
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: colorFromHex(active.backgroundBottomHex).withValues(alpha: 0.85),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  BoxDecoration buildBackgroundDecoration() {
    final ThemePack active = _currentTheme ??
        const ThemePack(
          id: 'aurora',
          name: 'Aurora',
          seedColorHex: '#3DD6D0',
          backgroundTopHex: '#081126',
          backgroundBottomHex: '#133B5C',
          accentHex: '#8E7CFF',
        );

    return BoxDecoration(
      gradient: LinearGradient(
        colors: <Color>[
          colorFromHex(active.backgroundTopHex),
          colorFromHex(active.backgroundBottomHex),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
  }
}
