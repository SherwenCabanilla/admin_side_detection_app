import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';

import 'firestore_backup_download.dart';

/// Exports and restores top-level Firestore collections used by this admin app.
class FirestoreBackupService {
  FirestoreBackupService._();

  static const int formatVersion = 1;

  static const List<String> backupCollections = [
    'users',
    'scan_requests',
    'activities',
    'admins',
  ];

  static dynamic _encodeValue(dynamic v) {
    if (v is Timestamp) {
      return {
        '_fsType': 'timestamp',
        'seconds': v.seconds,
        'nanoseconds': v.nanoseconds,
      };
    }
    if (v is GeoPoint) {
      return {'_fsType': 'geopoint', 'lat': v.latitude, 'lng': v.longitude};
    }
    if (v is DocumentReference) {
      return {'_fsType': 'ref', 'path': v.path};
    }
    if (v is Map) {
      return v.map((k, dynamic val) => MapEntry(k.toString(), _encodeValue(val)));
    }
    if (v is List) {
      return v.map(_encodeValue).toList();
    }
    return v;
  }

  static dynamic _decodeValue(dynamic v) {
    if (v is Map) {
      final m = Map<String, dynamic>.from(
        v.map((k, dynamic val) => MapEntry(k.toString(), val)),
      );
      final t = m['_fsType'];
      if (t == 'timestamp') {
        return Timestamp(
          (m['seconds'] as num).toInt(),
          (m['nanoseconds'] as num).toInt(),
        );
      }
      if (t == 'geopoint') {
        return GeoPoint(
          (m['lat'] as num).toDouble(),
          (m['lng'] as num).toDouble(),
        );
      }
      if (t == 'ref') {
        return FirebaseFirestore.instance.doc(m['path'] as String);
      }
      return m.map((k, dynamic val) => MapEntry(k, _decodeValue(val)));
    }
    if (v is List) {
      return v.map(_decodeValue).toList();
    }
    return v;
  }

  static Future<Map<String, dynamic>> exportPayload(
    FirebaseFirestore firestore,
  ) async {
    final collections = <String, dynamic>{};
    for (final name in backupCollections) {
      final snap = await firestore.collection(name).get();
      final docs = <String, dynamic>{};
      for (final d in snap.docs) {
        docs[d.id] = _encodeValue(d.data());
      }
      collections[name] = docs;
    }
    return {
      'backupFormatVersion': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'collections': collections,
    };
  }

  static String payloadToJsonString(Map<String, dynamic> payload) {
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static Future<void> downloadBackup(FirebaseFirestore firestore) async {
    final payload = await exportPayload(firestore);
    final json = payloadToJsonString(payload);
    final stamp =
        DateTime.now()
            .toUtc()
            .toIso8601String()
            .replaceAll(':', '-')
            .split('.')
            .first;
    await triggerJsonDownload(
      filename: 'admin_firestore_backup_$stamp.json',
      content: json,
    );
  }

  /// Returns parsed backup root map, or null if user cancelled or file is invalid.
  static Future<Map<String, dynamic>?> pickAndParseBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.bytes == null) return null;
    final text = utf8.decode(file.bytes!);
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> restoreFromPayload(
    FirebaseFirestore firestore,
    Map<String, dynamic> root,
  ) async {
    final version = root['backupFormatVersion'];
    if (version != formatVersion) {
      throw FormatException(
        'Unsupported backup version: $version (expected $formatVersion).',
      );
    }
    final rawCols = root['collections'];
    if (rawCols is! Map) {
      throw const FormatException('Invalid backup: missing "collections" object.');
    }
    final collections = Map<String, dynamic>.from(rawCols);

    for (final name in backupCollections) {
      final docs = collections[name];
      if (docs == null) continue;
      if (docs is! Map) {
        throw FormatException('Invalid backup: collection "$name" must be an object.');
      }
      await _writeCollection(
        firestore,
        name,
        Map<String, dynamic>.from(docs),
      );
    }
  }

  static Future<void> _writeCollection(
    FirebaseFirestore fs,
    String collectionName,
    Map<String, dynamic> docsById,
  ) async {
    WriteBatch batch = fs.batch();
    var n = 0;
    for (final e in docsById.entries) {
      final decoded = _decodeValue(e.value);
      if (decoded is! Map<String, dynamic>) continue;
      batch.set(
        fs.collection(collectionName).doc(e.key),
        decoded,
        SetOptions(merge: false),
      );
      n++;
      if (n >= 500) {
        await batch.commit();
        batch = fs.batch();
        n = 0;
      }
    }
    if (n > 0) await batch.commit();
  }
}
