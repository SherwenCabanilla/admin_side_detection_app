import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> triggerJsonDownload({
  required String filename,
  required String content,
}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'application/json;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor =
      html.AnchorElement(href: url)
        ..download = filename
        ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<void> triggerBinaryDownload({
  required String filename,
  required List<int> bytes,
}) async {
  final u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final blob = html.Blob([u8], 'application/zip');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor =
      html.AnchorElement(href: url)
        ..download = filename
        ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
