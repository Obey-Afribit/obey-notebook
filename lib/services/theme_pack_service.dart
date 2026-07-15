import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/models/theme_pack.dart';

class ThemePackService {
  Future<Map<String, dynamic>> loadCatalog() async {
    final String raw =
        await rootBundle.loadString('assets/theme_packs/catalog.json');
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    return decoded;
  }

  Future<ThemePack> loadBuiltInTheme(String assetPath) async {
    final String raw = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;

    return _toThemePack(decoded, fallbackBuiltIn: true);
  }

  Future<ThemePack> downloadTheme({
    required String id,
    required String name,
    required String downloadUrl,
    String? fallbackAssetPath,
  }) async {
    Map<String, dynamic>? decoded;
    Object? failure;

    if (downloadUrl.trim().isNotEmpty) {
      try {
        final http.Response response = await http.get(Uri.parse(downloadUrl));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('HTTP ${response.statusCode}');
        }

        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (error) {
        failure = error;
      }
    }

    if (decoded == null && (fallbackAssetPath ?? '').isNotEmpty) {
      try {
        final String fallbackRaw =
            await rootBundle.loadString(fallbackAssetPath!);
        decoded = jsonDecode(fallbackRaw) as Map<String, dynamic>;
      } catch (error) {
        failure = error;
      }
    }

    if (decoded == null) {
      throw Exception('Failed to load theme $id: $failure');
    }

    return _toThemePack(
      decoded,
      forceId: id,
      forceName: name,
      fallbackBuiltIn: false,
      fallbackUrl: downloadUrl,
    );
  }

  ThemePack _toThemePack(
    Map<String, dynamic> map, {
    String? forceId,
    String? forceName,
    String? fallbackUrl,
    required bool fallbackBuiltIn,
  }) {
    return ThemePack(
      id: forceId ?? map['id'] as String,
      name: forceName ?? map['name'] as String,
      description: map['description'] as String? ?? '',
      seedColorHex: map['seedColor'] as String? ??
          map['seedColorHex'] as String? ??
          '#3DD6D0',
      backgroundTopHex: map['backgroundTop'] as String? ??
          map['backgroundTopHex'] as String? ??
          '#081126',
      backgroundBottomHex: map['backgroundBottom'] as String? ??
          map['backgroundBottomHex'] as String? ??
          '#133B5C',
      accentHex:
          map['accent'] as String? ?? map['accentHex'] as String? ?? '#8E7CFF',
      isBuiltIn: map['isBuiltIn'] as bool? ?? fallbackBuiltIn,
      downloadUrl: map['downloadUrl'] as String? ?? fallbackUrl,
    );
  }
}
