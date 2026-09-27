import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../core/markdown_tools.dart';
import '../../core/models/note_item.dart';
import '../../core/models/template_item.dart';
import '../../state/notebook_controller.dart';
import '../notes/note_card.dart';
import '../shared/sheets.dart';
import '../shared/ui.dart';

/// Starter and custom templates. Tapping one creates a note from it.
class TemplatesView extends StatelessWidget {
  const TemplatesView({super.key, required this.compact});

  final bool compact;

  Future<void> _use(BuildContext context, TemplateItem template) async {
    final NotebookController controller = context.read<NotebookController>();
    final NoteItem note = await controller.createNoteFromTemplate(template);
    if (context.mounted) {
      await openNote(context, note.id, isNew: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeData theme = Theme.of(context);
    final List<TemplateItem> templates = controller.templates;

    final Widget header = Padding(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 28, compact ? 8 : 20, compact ? 12 : 28, 8),
      child: Row(
        children: <Widget>[
          if (compact)
            IconButton(
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          if (compact) const SizedBox(width: 4),
          Expanded(child: Text('Templates', style: theme.textTheme.headlineSmall)),
          FilledButton.tonalIcon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _TemplateDialog(),
            ),
            icon: const Icon(Icons.add),
            label: const Text('New template'),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 20 : 28, 0, 20, 8),
          child: Text(
            'Start a note from a ready-made layout, or save any note as a template from its menu.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: templates.isEmpty
              ? const EmptyState(
                  icon: Icons.dashboard_customize_outlined,
                  title: 'No templates yet',
                  message: 'Create one to reuse a layout you write often.',
                )
              : LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double gutter = compact ? 12 : 28;
                    final int columns = ((constraints.maxWidth - gutter * 2) / 260)
                        .floor()
                        .clamp(1, 5);
                    return MasonryGridView.count(
                      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 40),
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      itemCount: templates.length,
                      itemBuilder: (BuildContext context, int index) =>
                          _TemplateCard(
                        template: templates[index],
                        onUse: () => _use(context, templates[index]),
                        onDelete: templates[index].isBuiltIn
                            ? null
                            : () async {
                                if (await confirmAction(
                                  context,
                                  title: 'Delete template?',
                                  message:
                                      '"${templates[index].title}" will be removed. Notes made from it are not affected.',
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                )) {
                                  await controller
                                      .deleteCustomTemplate(templates[index].id);
                                }
                              },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onUse,
    this.onDelete,
  });

  final TemplateItem template;
  final VoidCallback onUse;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onUse,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    template.isBuiltIn
                        ? Icons.auto_awesome_outlined
                        : Icons.bookmark_outline,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(template.title, style: theme.textTheme.titleMedium),
                  ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: 'Delete template',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  MarkdownTools.previewText(template.body),
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Use template',
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog();

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New template'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Content (Markdown)',
                alignLabelWithHint: true,
                hintText: '## Section\n\n- [ ] Task',
              ),
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
          onPressed: () async {
            if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
              return;
            }
            await context.read<NotebookController>().saveCustomTemplate(
                  title: _title.text,
                  body: _body.text,
                );
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
