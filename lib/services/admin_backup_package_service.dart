import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'firestore_backup_download.dart';
import 'firestore_backup_service.dart';

/// Full admin backup as ZIP: `firestore.json` + `manifest.json` + `storage/...` files.
class AdminBackupPackageService {
  AdminBackupPackageService._();

  static const int packageFormatVersion = 2;
  static const int maxCrawledStorageFiles = 3000;
  static const Duration perFileDownloadTimeout = Duration(seconds: 20);

  /// Max size per Storage object when downloading into the archive (bytes).
  static const int maxFileBytes = 100 * 1024 * 1024;

  static bool _looksLikeZip(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
        (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
  }

  static String _normalizeArchiveName(String name) =>
      name.replaceAll('\\', '/');

  static Uint8List? _readZipFile(Archive archive, String path) {
    final want = _normalizeArchiveName(path);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final n = _normalizeArchiveName(f.name);
      if (n == want) return f.content;
    }
    return null;
  }

  static String? _tryResolveStorageFullPath(String raw) {
    final s = raw.trim().replaceAll('\n', '').replaceAll('\r', '');
    if (s.isEmpty) return null;

    if (s.startsWith('gs://')) {
      try {
        return FirebaseStorage.instance.refFromURL(s).fullPath;
      } catch (_) {
        return null;
      }
    }

    if (s.startsWith('http://') || s.startsWith('https://')) {
      final lower = s.toLowerCase();
      if (!lower.contains('firebasestorage.googleapis.com') &&
          !lower.contains('firebasestorage.app')) {
        return null;
      }
      try {
        return FirebaseStorage.instance.refFromURL(s).fullPath;
      } catch (_) {
        return null;
      }
    }

    if (s.contains('://') || s.startsWith('/') || s.contains('..')) {
      return null;
    }
    if (!RegExp(r'^[a-zA-Z0-9_\-./]+$').hasMatch(s) || !s.contains('/')) {
      return null;
    }
    try {
      return FirebaseStorage.instance.ref(s).fullPath;
    } catch (_) {
      return null;
    }
  }

  static void _collectStorageStrings(
    dynamic v,
    Map<String, Set<String>> pathToUrls,
  ) {
    if (v == null) return;
    if (v is String) {
      final path = _tryResolveStorageFullPath(v);
      if (path != null) {
        pathToUrls.putIfAbsent(path, () => <String>{}).add(v);
      }
      return;
    }
    if (v is Map) {
      for (final val in v.values) {
        _collectStorageStrings(val, pathToUrls);
      }
      return;
    }
    if (v is List) {
      for (final val in v) {
        _collectStorageStrings(val, pathToUrls);
      }
    }
  }

  static Future<Map<String, Set<String>>> _mapStoragePathsFromFirestore(
    FirebaseFirestore firestore,
  ) async {
    final out = <String, Set<String>>{};
    for (final col in FirestoreBackupService.backupCollections) {
      final snap = await firestore.collection(col).get();
      for (final doc in snap.docs) {
        _collectStorageStrings(doc.data(), out);
      }
    }
    return out;
  }

  static Future<Set<String>> _crawlStoragePaths({
    void Function(String message)? onProgress,
  }) async {
    final out = <String>{};
    final queue = <Reference>[FirebaseStorage.instance.ref()];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (out.length >= maxCrawledStorageFiles) break;
      try {
        final listed = await current.listAll();
        for (final item in listed.items) {
          out.add(item.fullPath);
          if (out.length >= maxCrawledStorageFiles) break;
        }
        queue.addAll(listed.prefixes);
        onProgress?.call('Scanning storage folders… (${out.length} found)');
      } catch (_) {
        // Some prefixes may be disallowed by rules; continue best-effort.
      }
    }
    return out;
  }

  static String _zipPathForStorage(String fullPath) {
    final clean = fullPath.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
    if (clean.isEmpty || clean.contains('..')) {
      throw FormatException('Invalid storage path: $fullPath');
    }
    return 'storage/$clean';
  }

  static String? _contentTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'application/octet-stream';
  }

  static Future<void> downloadFullZipBackup(
    FirebaseFirestore firestore, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Exporting database…');
    final payload = await FirestoreBackupService.exportPayload(firestore);
    final firestoreJson = FirestoreBackupService.payloadToJsonString(payload);

    onProgress?.call('Finding storage files from database links…');
    final pathToUrls = await _mapStoragePathsFromFirestore(firestore);
    final referencedCount = pathToUrls.length;

    onProgress?.call('Scanning storage folders for additional files…');
    final crawled = await _crawlStoragePaths(onProgress: onProgress);
    for (final p in crawled) {
      pathToUrls.putIfAbsent(p, () => <String>{});
    }

    final packedFiles = <_PackedStorageFile>[];
    final skippedFiles = <Map<String, dynamic>>[];

    var i = 0;
    final total = pathToUrls.length;
    for (final e in pathToUrls.entries) {
      final fullPath = e.key;
      final urls = e.value.toList()..sort();
      final next = i + 1;
      onProgress?.call('Downloading files ($next / $total)…');
      try {
        final ref = FirebaseStorage.instance.ref(fullPath);
        final data = await ref
            .getData(maxFileBytes)
            .timeout(perFileDownloadTimeout);
        if (data == null || data.isEmpty) {
          skippedFiles.add({
            'storageFullPath': fullPath,
            'reason': 'empty_or_missing',
          });
          continue;
        }
        final zipPath = _zipPathForStorage(fullPath);
        packedFiles.add(
          _PackedStorageFile(
            zipPath: zipPath,
            storageFullPath: fullPath,
            originalUrls: urls,
            bytes: data,
          ),
        );
      } on TimeoutException {
        skippedFiles.add({
          'storageFullPath': fullPath,
          'reason': 'download_timeout_${perFileDownloadTimeout.inSeconds}s',
        });
      } catch (err) {
        skippedFiles.add({
          'storageFullPath': fullPath,
          'reason': err.toString(),
        });
      } finally {
        i++;
      }
    }

    final packedCount = packedFiles.length;
    final skippedCount = skippedFiles.length;
    onProgress?.call(
      'Downloads finished ($packedCount files, $skippedCount skipped). '
      'Compressing backup — please wait…',
    );
    await Future<void>.delayed(Duration.zero);

    final manifest = <String, dynamic>{
      'packageFormatVersion': packageFormatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'firestoreBackupFormatVersion': FirestoreBackupService.formatVersion,
      'scan': {
        'referencedFromFirestore': referencedCount,
        'foundByStorageCrawl': crawled.length,
        'maxCrawledStorageFiles': maxCrawledStorageFiles,
      },
      'files': packedFiles
          .map(
            (f) => {
              'zipPath': f.zipPath,
              'storageFullPath': f.storageFullPath,
              'originalUrls': f.originalUrls,
            },
          )
          .toList(),
      'skippedFiles': skippedFiles,
    };

    final archive = Archive();
    archive.addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
    archive.addFile(ArchiveFile.string('firestore.json', firestoreJson));

    final nPacked = packedFiles.length;
    for (var fi = 0; fi < nPacked; fi++) {
      final f = packedFiles[fi];
      // Store blobs uncompressed — JPEGs barely shrink; much faster to pack.
      archive.addFile(
        ArchiveFile.noCompress(f.zipPath, f.bytes.length, f.bytes),
      );
      if (fi > 0 && fi % 25 == 0) {
        onProgress?.call('Packing into ZIP ($fi / $nPacked files)…');
        await Future<void>.delayed(Duration.zero);
      }
    }

    onProgress?.call('Finalizing ZIP (almost done)…');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final zipBytes = ZipEncoder().encode(
      archive,
      level: DeflateLevel.bestSpeed,
    );

    onProgress?.call('Starting download…');
    await Future<void>.delayed(Duration.zero);
    final stamp =
        DateTime.now()
            .toUtc()
            .toIso8601String()
            .replaceAll(':', '-')
            .split('.')
            .first;
    await triggerBinaryDownload(
      filename: 'admin_full_backup_$stamp.zip',
      bytes: zipBytes,
    );
  }

  static dynamic _deepReplaceUrls(dynamic v, Map<String, String> oldToNew) {
    if (v is String) {
      return oldToNew[v] ?? v;
    }
    if (v is List) {
      return v.map((e) => _deepReplaceUrls(e, oldToNew)).toList();
    }
    if (v is Map) {
      return Map<String, dynamic>.from(
        v.map(
          (k, dynamic val) =>
              MapEntry(k.toString(), _deepReplaceUrls(val, oldToNew)),
        ),
      );
    }
    return v;
  }

  static Future<void> restoreFromZipBytes(
    Uint8List bytes, {
    void Function(String message)? onProgress,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    final manifestBytes = _readZipFile(archive, 'manifest.json');
    if (manifestBytes == null) {
      throw const FormatException(
        'This ZIP is missing manifest.json. Use a backup created from this admin app.',
      );
    }

    final manifest =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    final pkgVer = manifest['packageFormatVersion'];
    if (pkgVer != packageFormatVersion) {
      throw FormatException(
        'Unsupported backup package version: $pkgVer (expected $packageFormatVersion).',
      );
    }

    final firestoreBytes = _readZipFile(archive, 'firestore.json');
    if (firestoreBytes == null) {
      throw const FormatException('This ZIP is missing firestore.json.');
    }

    final files = manifest['files'];
    if (files is! List) {
      throw const FormatException('Invalid manifest: "files" must be a list.');
    }

    final oldToNew = <String, String>{};
    var idx = 0;
    for (final raw in files) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final zipPath = m['zipPath'] as String?;
      final storageFullPath = m['storageFullPath'] as String?;
      if (zipPath == null || storageFullPath == null) continue;

      idx++;
      onProgress?.call('Uploading files ($idx / ${files.length})…');

      final entryBytes = _readZipFile(archive, zipPath);
      if (entryBytes == null || entryBytes.isEmpty) {
        continue;
      }

      final ref = FirebaseStorage.instance.ref(storageFullPath);
      final ct = _contentTypeForPath(storageFullPath);
      await ref.putData(
        entryBytes,
        SettableMetadata(contentType: ct),
      );
      final newUrl = await ref.getDownloadURL();
      final originals = m['originalUrls'];
      if (originals is List) {
        for (final u in originals) {
          if (u is String && u.isNotEmpty) {
            oldToNew[u] = newUrl;
          }
        }
      }
    }

    onProgress?.call('Restoring database…');
    final root =
        jsonDecode(utf8.decode(firestoreBytes)) as Map<String, dynamic>;
    final patched = _deepReplaceUrls(root, oldToNew);
    if (patched is! Map) {
      throw const FormatException('Invalid firestore.json after URL rewrite.');
    }
    await FirestoreBackupService.restoreFromPayload(
      FirebaseFirestore.instance,
      Map<String, dynamic>.from(patched),
    );
  }

  /// Picks a .zip or legacy .json backup. Returns kind + data for the caller to route.
  static Future<BackupPickResult?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.bytes == null || file.bytes!.isEmpty) return null;
    final bytes = file.bytes!;
    if (_looksLikeZip(bytes)) {
      return BackupPickResult.zip(bytes);
    }
    return BackupPickResult.json(bytes);
  }
}

class BackupPickResult {
  BackupPickResult._(this.isZip, this.bytes);

  factory BackupPickResult.zip(Uint8List bytes) =>
      BackupPickResult._(true, bytes);

  factory BackupPickResult.json(Uint8List bytes) =>
      BackupPickResult._(false, bytes);

  final bool isZip;
  final Uint8List bytes;
}

class _PackedStorageFile {
  _PackedStorageFile({
    required this.zipPath,
    required this.storageFullPath,
    required this.originalUrls,
    required this.bytes,
  });

  final String zipPath;
  final String storageFullPath;
  final List<String> originalUrls;
  final Uint8List bytes;
}
