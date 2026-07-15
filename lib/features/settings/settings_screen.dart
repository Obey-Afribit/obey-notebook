import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/folder_item.dart';
import '../../core/models/theme_pack.dart';
import '../../core/theme/theme_controller.dart';
import '../../state/notebook_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeController themeController = context.watch<ThemeController>();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Card(
          child: ListTile(
            title: const Text('Stay Signed In'),
            subtitle: const Text('Keep session active across app restarts.'),
            trailing: Switch(
              value: controller.staySignedIn,
              onChanged: controller.setStaySignedIn,
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Sync'),
            subtitle: const Text(
              'Offline notes sync automatically when internet is available.',
            ),
            trailing: FilledButton(
              onPressed: controller.isBusy ? null : controller.syncNow,
              child: const Text('Sync Now'),
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Themes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      themeController.availableThemes.map((ThemePack pack) {
                    final bool isSelected =
                        themeController.currentTheme?.id == pack.id;
                    final bool isPlaceholder = !pack.isBuiltIn &&
                        pack.downloadUrl != null &&
                        pack.seedColorHex == '#1E1E1E';

                    return SizedBox(
                      width: 240,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                pack.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                pack.description.isEmpty
                                    ? 'Theme pack for notebook visuals.'
                                    : pack.description,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  if (isPlaceholder)
                                    OutlinedButton(
                                      onPressed: () =>
                                          controller.downloadThemePack(pack.id),
                                      child: const Text('Download'),
                                    )
                                  else
                                    FilledButton(
                                      onPressed: () =>
                                          controller.setTheme(pack.id),
                                      child: Text(
                                        isSelected ? 'Selected' : 'Use Theme',
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
                if (themeController.error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    themeController.error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
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
