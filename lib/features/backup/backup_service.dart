import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/providers.dart';

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(
    ref.watch(databaseProvider), ref.watch(notificationServiceProvider)));

class BackupService {
  BackupService(this._db, this._notifications);

  final AppDatabase _db;
  final NotificationService _notifications;

  String _fileName() =>
      'taskley-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.json';

  Future<Uint8List> _encode() async {
    final data = await _db.exportData();
    return utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
  }

  /// Saves the backup through the system file picker. Returns the chosen
  /// location, or null if the user cancelled.
  Future<String?> exportToFile() async {
    return FilePicker.platform.saveFile(
      fileName: _fileName(),
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: await _encode(),
    );
  }

  /// Picks a backup file and replaces all data with it. Returns false if the
  /// user cancelled the picker. Throws [FormatException] on invalid files.
  Future<bool> restoreFromFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final bytes = result?.files.singleOrNull?.bytes;
    if (bytes == null) return false;
    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('Not a valid backup file');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Not a valid backup file');
    }
    await _db.importData(decoded);
    await _notifications.rescheduleAll(_db);
    return true;
  }
}
