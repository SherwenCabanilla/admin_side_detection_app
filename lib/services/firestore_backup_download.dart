import 'firestore_backup_download_stub.dart'
    if (dart.library.html) 'firestore_backup_download_web.dart' as impl;

Future<void> triggerJsonDownload({
  required String filename,
  required String content,
}) =>
    impl.triggerJsonDownload(filename: filename, content: content);

Future<void> triggerBinaryDownload({
  required String filename,
  required List<int> bytes,
}) =>
    impl.triggerBinaryDownload(filename: filename, bytes: bytes);
