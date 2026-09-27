import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/models/folder_item.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../state/notebook_controller.dart';
import '../shared/sheets.dart';
import '../shared/ui.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final NotebookController controller = context.watch<NotebookController>();
    final ThemeController themeController = context.watch<ThemeController>();
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ListView(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 28, compact ? 8 : 20, compact ? 8 : 28, 48),
      children: <Widget>[
        Row(
          children: <Widget>[
            if (compact)
              IconButton(
                tooltip: 'Menu',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu),
              ),
            if (compact) const SizedBox(width: 4),
            Text('Settings', style: theme.textTheme.headlineSmall),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ------------------------------------------------------------- account
                _Group(
                  title: 'Account',
                  children: <Widget>[
                    if (controller.cloudConfigured) ...<Widget>[
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: Text(
                            (controller.accountEmail ?? '?').substring(0, 1).toUpperCase(),
                          ),
                        ),
                        title: Text(controller.accountEmail ?? 'Signed in'),
                        subtitle: const Text('Your notes sync to this account'),
                        trailing: OutlinedButton(
                          onPressed: controller.isBusy ? null : controller.signOut,
                          child: const Text('Sign out'),
                        ),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.login),
                        title: const Text('Stay signed in'),
                        subtitle: const Text(
                          'When off, you sign in again each time the app starts.',
                        ),
                        value: controller.staySignedIn,
                        onChanged: controller.setStaySignedIn,
                      ),
                    ] else
                      const ListTile(
                        leading: Icon(Icons.phone_android_outlined),
                        title: Text('Local notebook'),
                        subtitle: Text(
                          'This build has no cloud sync, so notes stay on this device.',
                        ),
                      ),
                  ],
                ),

                // ------------------------------------------------------------- sync
                if (controller.cloudConfigured)
                  _Group(
                    title: 'Sync',
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                        child: Row(
                          children: <Widget>[
                            Expanded(child: SyncStatusPill(controller: controller)),
                            FilledButton.tonal(
                              onPressed: controller.syncState == SyncState.syncing
                                  ? null
                                  : () => controller.syncNow(),
                              child: const Text('Sync now'),
                            ),
                          ],
                        ),
                      ),
                      ListTile(
                        leading: Icon(
                          controller.liveSyncConnected ? Icons.bolt : Icons.schedule,
                        ),
                        title: Text(
                          controller.liveSyncConnected ? 'Live updates on' : 'Checking every 2 minutes',
                        ),
                        subtitle: const Text(
                          'Edits upload within seconds and appear on your other '
                          'devices automatically. Offline edits upload when you reconnect.',
                        ),
                      ),
                    ],
                  ),

                // ------------------------------------------------------------- appearance
                _Group(
                  title: 'Appearance',
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: SegmentedButton<ThemeMode>(
                        segments: const <ButtonSegment<ThemeMode>>[
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_outlined),
                            label: Text('Auto'),
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
                        onSelectionChanged: (Set<ThemeMode> s) =>
                            themeController.setThemeMode(s.first),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Accent', style: theme.textTheme.labelLarge),
                          const SizedBox(height: 4),
                          Text(
                            themeController.currentTheme.description,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: <Widget>[
                              for (final AppTheme preset in themeController.themes)
                                _Swatch(
                                  color: preset.seed,
                                  label: preset.name,
                                  selected: themeController.currentThemeId == preset.id,
                                  onTap: () => themeController.setTheme(preset.id),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ------------------------------------------------------------- editor
                _Group(
                  title: 'Editor',
                  children: <Widget>[
                    SwitchListTile(
                      secondary: const Icon(Icons.chrome_reader_mode_outlined),
                      title: const Text('Open notes in reading view'),
                      subtitle: const Text(
                        'Show notes formatted, with images and checklists. Tap the pencil to edit.',
                      ),
                      value: themeController.openInReadingView,
                      onChanged: themeController.setOpenInReadingView,
                    ),
                    ListTile(
                      leading: const Icon(Icons.format_size),
                      title: const Text('Text size'),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SegmentedButton<EditorTextSize>(
                            segments: <ButtonSegment<EditorTextSize>>[
                              for (final EditorTextSize size in EditorTextSize.values)
                                ButtonSegment<EditorTextSize>(
                                  value: size,
                                  label: Text(size.label),
                                ),
                            ],
                            selected: <EditorTextSize>{themeController.editorTextSize},
                            onSelectionChanged: (Set<EditorTextSize> s) =>
                                themeController.setEditorTextSize(s.first),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ------------------------------------------------------------- privacy
                _Group(
                  title: 'Folder locks',
                  children: <Widget>[
                    if (!controller.lockSupported)
                      const ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('Not available here'),
                        subtitle: Text(
                          'Folder locks use your device screen lock (fingerprint, face, '
                          'PIN or Windows Hello). Browsers and devices without one '
                          "can't use them.",
                        ),
                      )
                    else if (controller.folders.isEmpty)
                      const ListTile(title: Text('No folders yet.'))
                    else ...<Widget>[
                      const ListTile(
                        dense: true,
                        subtitle: Text(
                          'Locked folders are hidden from All notes and need your '
                          'screen lock to open. Locks apply to this device only.',
                        ),
                      ),
                      for (final FolderItem folder in controller.folders)
                        SwitchListTile(
                          secondary: Icon(
                            controller.lockedFolderIds.contains(folder.id)
                                ? Icons.lock
                                : Icons.lock_open_outlined,
                          ),
                          title: Text(folder.name),
                          value: controller.lockedFolderIds.contains(folder.id),
                          onChanged: (_) => controller.toggleFolderLock(folder.id),
                        ),
                    ],
                  ],
                ),

                // ------------------------------------------------------------- data
                _Group(
                  title: 'Your data',
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('Export everything'),
                      subtitle: const Text('Download all notes and folders as a JSON backup.'),
                      onTap: controller.isBusy ? null : controller.exportAllDataBackup,
                    ),
                    ListTile(
                      leading: Icon(Icons.person_remove_outlined, color: scheme.error),
                      title: Text('Delete account and data',
                          style: TextStyle(color: scheme.error)),
                      subtitle: const Text(
                        'Permanently removes your notes, images and account.',
                      ),
                      onTap: controller.isBusy
                          ? null
                          : () async {
                              if (await confirmAction(
                                context,
                                title: 'Delete your account?',
                                message: 'All notes, images and folders are deleted '
                                    'from every device. This cannot be undone.',
                                confirmLabel: 'Delete everything',
                                destructive: true,
                              )) {
                                await controller.deleteAccountAndData();
                              }
                            },
                    ),
                  ],
                ),

                // ------------------------------------------------------------- about
                _Group(
                  title: 'About',
                  children: <Widget>[
                    const ListTile(
                      leading: BrandMark(size: 36),
                      title: Text(AppConfig.appName),
                      subtitle: Text(
                        'Version ${AppConfig.appVersion}  |  Android, Windows and web',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.keyboard_outlined),
                      title: const Text('Keyboard shortcuts'),
                      onTap: () => _showShortcuts(context),
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

  void _showShortcuts(BuildContext context) {
    const List<(String, String)> keys = <(String, String)>[
      ('Ctrl + N', 'New note'),
      ('Ctrl + F  or  Ctrl + K', 'Search notes'),
      ('Esc', 'Clear search or selection, close a note'),
      ('Ctrl + click', 'Select notes'),
      ('Right-click', 'Note actions'),
      ('Ctrl + E', 'Switch between editing and reading'),
      ('Ctrl + B  /  Ctrl + I', 'Bold / italic'),
      ('Ctrl + K (editing)', 'Insert link'),
      ('Ctrl + S', 'Save now'),
      ('Ctrl + Z  /  Ctrl + Y', 'Undo / redo'),
    ];
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Keyboard shortcuts'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final (String combo, String what) in keys)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 190,
                          child: Text(
                            combo,
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: theme.colorScheme.primary),
                          ),
                        ),
                        Expanded(child: Text(what)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(title, padding: const EdgeInsets.fromLTRB(8, 22, 8, 8)),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
        ),
      ),
    );
  }
}
