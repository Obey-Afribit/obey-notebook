import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/folder_item.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../state/notebook_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeController themeController = context.watch<ThemeController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _AppearanceCard(themeController: themeController),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('Stay signed in'),
            subtitle: const Text('Keep session active across app restarts.'),
            trailing: Switch(
              value: controller.staySignedIn,
              onChanged: controller.setStaySignedIn,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('Sync'),
            subtitle: const Text(
              'Offline notes sync automatically when internet is available.',
            ),
            trailing: FilledButton(
              onPressed: controller.isBusy ? null : controller.syncNow,
              child: const Text('Sync now'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Folder Privacy Lock',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...controller.folders.map(
                  (FolderItem folder) => SwitchListTile(
                    title: Text(folder.name),
                    value: controller.lockedFolderIds.contains(folder.id),
                    onChanged: (_) => controller.toggleFolderLock(folder.id),
                    secondary: const Icon(Icons.lock_outline),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  controller.cloudConfigured
                      ? 'Cloud Mode Active'
                      : 'Local-Only Mode Active',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  controller.cloudConfigured
                      ? 'Email verification and cloud sync are enabled.'
                      : 'Cloud auth is unavailable in this build. Continue using local mode or configure cloud sync.',
                ),
                if ((controller.cloudStatusMessage ?? '')
                    .isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    controller.cloudStatusMessage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (controller.cloudConfigured)
                      OutlinedButton(
                        onPressed:
                            controller.isBusy ? null : controller.signOut,
                        child: const Text('Sign Out'),
                      )
                    else
                      OutlinedButton(
                        onPressed: controller.isBusy
                            ? null
                            : controller.retryCloudSetup,
                        child: const Text('Retry Cloud Setup'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Privacy and Data',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Active notes: ${controller.filteredNotes.length} | '
                  'Archived: ${controller.archivedNotes.length} | '
                  'Trash: ${controller.trashNotes.length}',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: controller.isBusy
                          ? null
                          : controller.exportAllDataBackup,
                      child: const Text('Export My Data (JSON)'),
                    ),
                    FilledButton.tonal(
                      onPressed: controller.isBusy
                          ? null
                          : () async {
                              final bool? confirm = await showDialog<bool>(
                                context: context,
                                builder: (BuildContext dialogContext) {
                                  return AlertDialog(
                                    title:
                                        const Text('Delete account and data?'),
                                    content: const Text(
                                      'This action removes local data and attempts to delete the cloud account if configured.',
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext)
                                                .pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext)
                                                .pop(true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  );
                                },
                              );

                              if (confirm != true) {
                                return;
                              }

                              await controller.deleteAccountAndData();
                            },
                      child: const Text('Delete Account and Data'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Appearance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Text('Mode', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('System'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
              ],
              selected: <ThemeMode>{themeController.themeMode},
              onSelectionChanged: (Set<ThemeMode> selection) =>
                  themeController.setThemeMode(selection.first),
            ),
            const SizedBox(height: 20),
            Text('Accent color', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: themeController.themes.map((AppTheme theme) {
                final bool isSelected =
                    themeController.currentThemeId == theme.id;
                return _SwatchButton(
                  color: theme.seed,
                  label: theme.name,
                  selected: isSelected,
                  outline: scheme.outlineVariant,
                  onTap: () => themeController.setTheme(theme.id),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.color,
    required this.label,
    required this.selected,
    required this.outline,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final Color outline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? color : outline.withValues(alpha: 0.5),
              width: selected ? 3 : 1,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }
}
