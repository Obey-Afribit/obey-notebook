import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/models/template_item.dart';
import 'local_store_service.dart';

class TemplateService {
  TemplateService({required LocalStoreService localStore})
      : _localStore = localStore;

  final LocalStoreService _localStore;

  Future<List<TemplateItem>> getTemplatesForUser(String ownerId) async {
    await _ensureBuiltIns(ownerId);
    return _localStore.readTemplatesForUser(ownerId);
  }

  Future<void> saveCustomTemplate(TemplateItem template) {
    return _localStore.upsertTemplate(template);
  }

  Future<List<TemplateItem>> fetchMarketplaceTemplates() async {
    const String marketplaceUrl =
        'https://example.com/universal-notebook/templates/community.json';

    try {
      final http.Response response = await http.get(Uri.parse(marketplaceUrl));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final List<dynamic> decoded = jsonDecode(response.body) as List<dynamic>;
        return decoded
            .whereType<Map>()
            .map(
              (Map<dynamic, dynamic> map) => TemplateItem(
                id: map['id'].toString(),
                title: map['title'].toString(),
                body: map['body'].toString(),
                isBuiltIn: false,
              ),
            )
            .toList(growable: false);
      }
    } catch (_) {
      // Falls back to bundled marketplace previews.
    }

    return const <TemplateItem>[
      TemplateItem(
        id: 'market_daily_planner',
        title: 'Daily Planner',
        body: 'Top 3 priorities:\n1.\n2.\n3.\n\nNotes:\n',
      ),
      TemplateItem(
        id: 'market_meeting',
        title: 'Meeting Notes',
        body: 'Agenda:\n\nDiscussion:\n\nDecisions:\n\nAction Items:\n',
      ),
    ];
  }

  Future<void> _ensureBuiltIns(String ownerId) async {
    if (_localStore.getBuiltInTemplatesLoaded()) {
      return;
    }

    final String raw =
        await rootBundle.loadString('assets/templates/starter_templates.json');
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;

    for (final dynamic entry in decoded) {
      final Map<String, dynamic> map =
          (entry as Map<dynamic, dynamic>).map(
        (dynamic key, dynamic value) => MapEntry(key.toString(), value),
      );

      await _localStore.upsertTemplate(
        TemplateItem(
          id: map['id'] as String,
          title: map['title'] as String,
          body: map['body'] as String,
          ownerId: ownerId,
          isBuiltIn: true,
        ),
      );
    }

    await _localStore.markBuiltInTemplatesLoaded();
  }
}
