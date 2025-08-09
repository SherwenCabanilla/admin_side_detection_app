import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CsvExportService {
  static String _escape(String value) {
    final needsQuotes =
        value.contains(',') || value.contains('"') || value.contains('\n');
    String v = value.replaceAll('"', '""');
    return needsQuotes ? '"$v"' : v;
  }

  static String generateCsv(List<List<String>> rows) {
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.writeln(row.map(_escape).join(','));
    }
    return buffer.toString();
  }

  static Future<void> copyToClipboard(
    BuildContext context,
    String filename,
    List<List<String>> rows,
  ) async {
    final csv = generateCsv(rows);
    await Clipboard.setData(ClipboardData(text: csv));
    // Best-effort UX message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'CSV copied to clipboard ($filename). Paste into a file or spreadsheet.',
        ),
      ),
    );
  }

  // Users CSV export removed per product decision
}
