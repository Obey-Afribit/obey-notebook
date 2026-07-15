import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/template_item.dart';
import '../../state/notebook_controller.dart';
import '../notes/note_editor_screen.dart';

class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              title: const Text('Templates'),
              subtitle: const Text(
                'Use starter templates or create your own reusable format.',
              ),
              trailing: FilledButton.icon(
                onPressed: () => _showCreateTemplateDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Custom'),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: <Widget>[
                  if (controller.templates.isEmpty)
                    const ListTile(title: Text('No templates yet.')),
                  ...controller.templates.map(
                    (TemplateItem template) => ListTile(
                      leading: Icon(
                        template.isBuiltIn
                            ? Icons.auto_awesome
                            : Icons.bookmark_outline,
                      ),
                      title: Text(template.title),
                      subtitle: Text(
                        template.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: FilledButton(
                        onPressed: () => _createFromTemplate(
                          context: context,
                          template: template,
                        ),
                        child: const Text('Use'),
                      ),
                    ),
                  ),
                  const Divider(height: 20),
                  const ListTile(
                    title: Text('Marketplace Templates'),
                    subtitle: Text('Download and import community formats.'),
                  ),
                  ...controller.marketplaceTemplates.map(
                    (TemplateItem template) => ListTile(
                      leading: const Icon(Icons.cloud_download_outlined),
                      title: Text(template.title),
                      subtitle: Text(
                        template.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: OutlinedButton(
                        onPressed: () =>
                            controller.importMarketplaceTemplate(template),
                        child: const Text('Import'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFromTemplate({
    required BuildContext context,
    required TemplateItem template,
  }) async {
    final NotebookController controller = context.read<NotebookController>();
    final note = await controller.createNoteFromTemplate(template: template);

    if (!context.mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(noteId: note.id),
      ),
    );
  }

  Future<void> _showCreateTemplateDialog(BuildContext context) async {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController bodyController = TextEditingController();
    final NotebookController controller = context.read<NotebookController>();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('New Custom Template'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Template title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Template body'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final String title = titleController.text.trim();
                final String body = bodyController.text.trim();
                if (title.isEmpty || body.isEmpty) {
                  return;
                }

                await controller.saveCustomTemplate(title: title, body: body);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    titleController.dispose();
    bodyController.dispose();
  }
}
