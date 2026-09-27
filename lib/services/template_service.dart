import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/models/template_item.dart';
import 'local_store_service.dart';

/// Built-in starter templates (bundled) plus the user's own templates.
class TemplateService {
  TemplateService({required LocalStoreService localStore})
      : _localStore = localStore;

  final LocalStoreService _localStore;

  /// Bump when assets/templates/starter_templates.json changes, so existing
  /// installs replace their stored copies of the built-ins.
  static const int _builtInVersion = 2;
  static const String _versionKey = 'built_in_templates_version';

  Future<List<TemplateItem>> getTemplatesForUser(String ownerId) async {
    await _ensureBuiltIns(ownerId);
    final List<TemplateItem> templates =
        _localStore.readTemplatesForUser(ownerId);
    // Built-ins first (in bundle order is not preserved by Hive), then custom.
    templates.sort((TemplateItem a, TemplateItem b) {
      if (a.isBuiltIn != b.isBuiltIn) {
        return a.isBuiltIn ? -1 : 1;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return templates;
  }

  Future<void> saveCustomTemplate(TemplateItem template) {
    return _localStore.upsertTemplate(template);
  }

  Future<void> deleteCustomTemplate(String templateId) {
    return _localStore.deleteTemplate(templateId);
  }

  Future<void> _ensureBuiltIns(String ownerId) async {
    if ((_localStore.readSetting<int>(_versionKey) ?? 0) >= _builtInVersion) {
      return;
    }

    for (final String id in _localStore.readBuiltInTemplateIds()) {
      await _localStore.deleteTemplate(id);
    }

    final String raw =
        await rootBundle.loadString('assets/templates/starter_templates.json');
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;

    for (final dynamic entry in decoded) {
      final Map<String, dynamic> map = (entry as Map<dynamic, dynamic>).map(
        (dynamic key, dynamic value) => MapEntry(key.toString(), value),
      );

      await _localStore.upsertTemplate(
        TemplateItem(
          id: 'builtin_${map['id']}',
          title: map['title'] as String,
          body: map['body'] as String,
          ownerId: ownerId,
          isBuiltIn: true,
        ),
      );
    }

    await _localStore.saveSetting(_versionKey, _builtInVersion);
  }
}
