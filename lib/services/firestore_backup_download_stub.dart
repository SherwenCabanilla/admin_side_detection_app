Future<void> triggerJsonDownload({
  required String filename,
  required String content,
}) async {
  throw UnsupportedError(
    'JSON download is only supported in the web build of this admin app.',
  );
}

Future<void> triggerBinaryDownload({
  required String filename,
  required List<int> bytes,
}) async {
  throw UnsupportedError(
    'Binary download is only supported in the web build of this admin app.',
  );
}
