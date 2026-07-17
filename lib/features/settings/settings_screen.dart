import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../backup/backup_service.dart';
import '../import_ics/import_ics_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportBackup() async {
    final service = ref.read(backupServiceProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save to file'),
              onTap: () => Navigator.pop(sheetContext, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              subtitle: const Text('Send to Drive, email, ...'),
              onTap: () => Navigator.pop(sheetContext, 'share'),
            ),
          ],
        ),
      ),
    );
    try {
      if (choice == 'save') {
        final path = await service.exportToFile();
        if (path != null) _toast('Backup saved');
      } else if (choice == 'share') {
        await service.shareBackup();
      }
    } catch (e) {
      _toast('Backup failed: $e');
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
            'This replaces ALL current lists and tasks with the backup. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final restored = await ref.read(backupServiceProvider).restoreFromFile();
      if (restored) _toast('Backup restored');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Restore failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.read(notificationServiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _section(theme, 'Data'),
          ListTile(
            leading: const Icon(Icons.event_available),
            title: const Text('Import from Google Calendar'),
            subtitle: const Text('Bring events in from an exported .ics file'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ImportIcsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export backup'),
            subtitle: const Text('Save all lists and tasks as a JSON file'),
            onTap: _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore backup'),
            subtitle: const Text('Replace everything with a backup file'),
            onTap: _restoreBackup,
          ),
          const Divider(),
          _section(theme, 'Notifications'),
          FutureBuilder(
            future: Future.wait([
              notifications.notificationsEnabled(),
              notifications.exactAlarmsAllowed(),
            ]),
            builder: (context, snapshot) {
              final enabled = snapshot.data?[0] ?? true;
              final exact = snapshot.data?[1] ?? true;
              final ok = enabled && exact;
              return ListTile(
                leading: Icon(
                  ok ? Icons.notifications_active : Icons.notifications_off,
                  color: ok ? null : theme.colorScheme.error,
                ),
                title: Text(ok
                    ? 'Alarms are ready'
                    : !enabled
                        ? 'Notifications are off'
                        : 'Exact alarms are off'),
                subtitle: Text(ok
                    ? 'Task alarms will ring at the exact time'
                    : 'Tap to grant permission so alarms can ring'),
                onTap: ok
                    ? null
                    : () async {
                        await notifications.requestPermissions();
                        setState(() {});
                      },
              );
            },
          ),
          const Divider(),
          _section(theme, 'About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Taskley'),
            subtitle: Text('Version 0.2.1 · offline to-do app\ncreated by Radley'),
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: theme.textTheme.titleSmall!
                .copyWith(color: theme.colorScheme.primary)),
      );
}
