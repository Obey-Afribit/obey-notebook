import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../state/notebook_controller.dart';

/// Breakpoints shared by every screen.
class Breakpoints {
  const Breakpoints._();

  /// At or above this width the sidebar is permanent instead of a drawer.
  static const double sidebar = 900;

  /// At or above this width the editor offers a side-by-side split view.
  static const double split = 1100;
}

/// The secretary-bird app icon, used on the sign-in screen and sidebar.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Image.asset(
        'assets/icon/logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// Friendly placeholder for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small uppercase label above a group of items.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// "Just now", "5 min ago", "Yesterday", "3 Sep", "3 Sep 2025".
String relativeTime(DateTime time) {
  final DateTime local = time.toLocal();
  final DateTime now = DateTime.now();
  final Duration diff = now.difference(local);

  if (diff.inSeconds < 45 && !diff.isNegative) {
    return 'Just now';
  }
  if (diff.inMinutes < 60 && !diff.isNegative) {
    return '${diff.inMinutes.clamp(1, 59)} min ago';
  }
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(local.year, local.month, local.day);
  final int dayDelta = today.difference(day).inDays;
  if (dayDelta == 0) {
    return DateFormat.Hm().format(local);
  }
  if (dayDelta == 1) {
    return 'Yesterday';
  }
  if (local.year == now.year) {
    return DateFormat('d MMM').format(local);
  }
  return DateFormat('d MMM y').format(local);
}

/// Reminder label: "Today 18:00", "Tomorrow 09:00", "Mon 09:00", "3 Oct 09:00".
String reminderLabel(DateTime at) {
  final DateTime local = at.toLocal();
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(local.year, local.month, local.day);
  final int delta = day.difference(today).inDays;
  final String time = DateFormat.Hm().format(local);
  if (delta == 0) {
    return 'Today $time';
  }
  if (delta == 1) {
    return 'Tomorrow $time';
  }
  if (delta == -1) {
    return 'Yesterday $time';
  }
  if (delta > 1 && delta < 7) {
    return '${DateFormat.E().format(local)} $time';
  }
  if (local.year == now.year) {
    return '${DateFormat('d MMM').format(local)} $time';
  }
  return '${DateFormat('d MMM y').format(local)} $time';
}

/// Compact sync status, used in the sidebar and in the phone header.
class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({super.key, required this.controller, this.compact = false});

  final NotebookController controller;

  /// Icon only (with tooltip), for tight headers.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final _SyncLook look = _SyncLook.of(controller, scheme);

    final Widget icon = look.spinning
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: look.color),
          )
        : Icon(look.icon, size: 18, color: look.color);

    if (compact) {
      return IconButton(
        tooltip: look.label,
        onPressed: controller.cloudConfigured ? () => controller.syncNow() : null,
        icon: icon,
      );
    }

    return Tooltip(
      message: controller.cloudConfigured ? 'Sync now' : look.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: controller.cloudConfigured ? () => controller.syncNow() : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  look.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncLook {
  const _SyncLook(this.icon, this.color, this.label, {this.spinning = false});

  final IconData icon;
  final Color color;
  final String label;
  final bool spinning;

  static _SyncLook of(NotebookController c, ColorScheme scheme) {
    final int pending = c.pendingChanges;
    switch (c.syncState) {
      case SyncState.localOnly:
        return _SyncLook(Icons.phone_android_outlined, scheme.onSurfaceVariant,
            'Saved on this device');
      case SyncState.syncing:
        return _SyncLook(Icons.sync, scheme.primary, 'Syncing...',
            spinning: true);
      case SyncState.offline:
        return _SyncLook(
          Icons.cloud_off_outlined,
          scheme.onSurfaceVariant,
          pending > 0
              ? 'Offline, $pending change${pending == 1 ? '' : 's'} waiting'
              : 'Offline',
        );
      case SyncState.error:
        return _SyncLook(Icons.sync_problem_outlined, scheme.error,
            "Couldn't sync. Tap to retry");
      case SyncState.idle:
        if (pending > 0) {
          return _SyncLook(Icons.cloud_upload_outlined, scheme.primary,
              '$pending change${pending == 1 ? '' : 's'} to upload');
        }
        final DateTime? at = c.lastSyncedAt;
        return _SyncLook(
          Icons.cloud_done_outlined,
          scheme.tertiary,
          at == null ? 'Synced' : 'Synced ${relativeTime(at).toLowerCase()}',
        );
    }
  }
}
