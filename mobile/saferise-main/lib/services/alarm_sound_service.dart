import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

/// Pengaturan suara alarm kustom.
///
/// Suara alarm loop DANGER bisa diganti user dari:
/// 1. Daftar suara bawaan HP (system Ringtone Picker), atau
/// 2. File audio apa pun dari storage (via SAF -- tanpa permission runtime).
///
/// Pilihan disimpan di native SharedPreferences ("saferise_settings")
/// sehingga tetap terbaca oleh AlarmLooper native saat app background/killed
/// (jalur FCM). App tidak menyediakan file audio sama sekali.
class AlarmSoundService {
  AlarmSoundService._();

  static final AlarmSoundService instance = AlarmSoundService._();

  static const MethodChannel _channel = MethodChannel('saferise.alarm');

  /// Info suara alarm aktif: {title, uri}.
  /// Title default "Suara Alarm Sistem" jika user belum memilih.
  Future<Map<String, String>> getAlarmSound() async {
    try {
      final result = await _channel.invokeMethod('getAlarmSound');
      return Map<String, String>.from(result as Map);
    } on PlatformException catch (e) {
      print('[AlarmSound] ❌ getAlarmSound: ${e.message}');
      return {'title': 'Suara Alarm Sistem', 'uri': ''};
    }
  }

  /// Buka system Ringtone Picker (daftar suara alarm milik HP).
  /// Return judul suara yang dipilih, atau null jika dibatalkan.
  Future<String?> pickSystemSound() async {
    try {
      final result = await _channel.invokeMethod('pickSystemSound');
      if (result == null) return null;
      return (result as Map)['title'] as String?;
    } on PlatformException catch (e) {
      print('[AlarmSound] ❌ pickSystemSound: ${e.message}');
      return null;
    }
  }

  /// Pilih file audio dari storage (SAF via file_picker -- tanpa permission),
  /// salin ke documents dir app agar tahan dari pembersihan cache,
  /// lalu daftarkan sebagai suara alarm.
  /// Return judul (nama file) atau null jika dibatalkan/gagal.
  Future<String?> pickFileSound() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
      final sourcePath = picked?.files.single.path;
      if (sourcePath == null) return null;

      final docs = await getApplicationDocumentsDirectory();
      final originalName = picked!.files.single.name;
      // Sanitasi nama file agar aman dipakai di filesystem & URI.
      final safeStem =
          originalName.replaceAll(RegExp(r'[^\w\-. ]'), '_');
      final dest = File('${docs.path}${Platform.pathSeparator}alarm_$safeStem');
      await File(sourcePath).copy(dest.path);

      await _channel.invokeMethod('setFileSound', {
        'path': dest.path,
        'title': picked.files.single.extension != null &&
                safeStem.toLowerCase().endsWith(
                    '.${picked.files.single.extension!.toLowerCase()}')
            ? safeStem.substring(
                0, safeStem.length - picked.files.single.extension!.length - 1)
            : safeStem,
      });
      return await getAlarmSound().then((s) => s['title']);
    } on PlatformException catch (e) {
      print('[AlarmSound] ❌ setFileSound: ${e.message}');
      return null;
    } catch (e) {
      print('[AlarmSound] ❌ pickFileSound error: $e');
      return null;
    }
  }

  /// Kembalikan ke suara alarm default sistem.
  Future<void> resetAlarmSound() async {
    try {
      await _channel.invokeMethod('resetAlarmSound');
    } on PlatformException catch (e) {
      print('[AlarmSound] ❌ resetAlarmSound: ${e.message}');
    }
  }

  /// Putar preview suara (uri kosong/null -> suara aktif saat ini).
  Future<void> preview([String? uri]) async {
    try {
      await _channel.invokeMethod('previewAlarm', uri ?? '');
    } on PlatformException catch (e) {
      print('[AlarmSound] ❌ previewAlarm: ${e.message}');
    }
  }

  /// Hentikan preview yang sedang berbunyi.
  Future<void> stopPreview() async {
    try {
      await _channel.invokeMethod('stopPreviewAlarm');
    } on PlatformException catch (e) {
      print('[AlarmSound] ❌ stopPreviewAlarm: ${e.message}');
    }
  }
}
