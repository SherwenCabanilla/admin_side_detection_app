Future<void> triggerJsonDownload({
  required String filename,
  required String content,
}) async {
  throw UnsupportedError(
    'JSON download is only supported in the web build of this admin app.',
  );
}
