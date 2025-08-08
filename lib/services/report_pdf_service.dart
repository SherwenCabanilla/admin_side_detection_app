import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';
import 'scan_requests_service.dart';
import 'settings_service.dart';

class ReportPdfService {
  static Future<void> generateAndShareReport({
    required BuildContext context,
    required String timeRange,
    String pageSize = 'A4',
  }) async {
    // Fetch data needed for the report
    final List<Map<String, dynamic>> diseaseStats =
        await ScanRequestsService.getDiseaseStats(timeRange: timeRange);
    // Build a simple trend series: reports per day in range
    final List<Map<String, dynamic>> allRequests =
        await ScanRequestsService.getScanRequests();
    final List<Map<String, dynamic>> filtered =
        ScanRequestsService.filterByTimeRange(allRequests, timeRange);
    final Map<String, int> perDay = {};
    // For response-time trend (avg hours per day)
    final Map<String, List<double>> responseHoursByDay = {};
    for (final r in filtered) {
      final createdAt = r['createdAt'];
      DateTime dt;
      if (createdAt is String) {
        dt = DateTime.tryParse(createdAt) ?? DateTime.now();
      } else {
        dt = createdAt.toDate();
      }
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      perDay[key] = (perDay[key] ?? 0) + 1;

      // Compute expert response time in hours when reviewedAt present
      final reviewedAt = r['reviewedAt'];
      DateTime? reviewed;
      if (reviewedAt != null) {
        if (reviewedAt is String) {
          reviewed = DateTime.tryParse(reviewedAt);
        } else {
          reviewed = reviewedAt.toDate();
        }
      }
      if (reviewed != null) {
        final hours = reviewed.difference(dt).inMinutes / 60.0;
        (responseHoursByDay[key] ??= <double>[]).add(hours);
      }
    }
    final List<MapEntry<String, int>> trend =
        perDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final List<MapEntry<String, double>> responseTrend =
        responseHoursByDay
            .map(
              (k, v) => MapEntry(
                k,
                v.isEmpty ? 0.0 : (v.reduce((a, b) => a + b) / v.length),
              ),
            )
            .entries
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final int completed = await ScanRequestsService.getCompletedReportsCount();
    final int pending = await ScanRequestsService.getPendingReportsCount();
    final String avgResponse = await ScanRequestsService.getAverageResponseTime(
      timeRange: timeRange,
    );

    final doc = pw.Document();

    // Load utility name
    final String utilityName = await SettingsService.getUtilityName();

    final now = DateTime.now();
    final String title = 'Reports Summary ($timeRange)';

    // Adaptive sizing for compact single-page layout
    final isSmall = pageSize.toLowerCase() == 'a5';
    final double margin = isSmall ? 10 : 16;
    final double headerFont = isSmall ? 12 : 16;
    final double chipLabelFont = isSmall ? 7.5 : 9;
    final double chipValueFont = isSmall ? 10 : 12;
    final double chartHeight = isSmall ? 90 : 110;
    final int tableRows = isSmall ? 4 : 6;
    final double tableFont = isSmall ? 8 : 9.5;

    doc.addPage(
      pw.Page(
        pageFormat: _resolvePageFormat(pageSize),
        margin: pw.EdgeInsets.all(margin),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        utilityName,
                        style: pw.TextStyle(
                          fontSize: headerFont,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        title,
                        style: pw.TextStyle(
                          fontSize: chipLabelFont + 1,
                          color: pdf.PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Text(
                    '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                    style: pw.TextStyle(fontSize: chipLabelFont + 1),
                  ),
                ],
              ),
              pw.SizedBox(height: isSmall ? 4 : 6),
              // Overview chips
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _statChip(
                    'Reviewed',
                    completed.toString(),
                    chipLabelFont,
                    chipValueFont,
                  ),
                  _statChip(
                    'Pending',
                    pending.toString(),
                    chipLabelFont,
                    chipValueFont,
                  ),
                  _statChip(
                    'Avg Resp.',
                    avgResponse,
                    chipLabelFont,
                    chipValueFont,
                  ),
                ],
              ),
              pw.SizedBox(height: isSmall ? 6 : 8),
              // Charts grid (2 columns)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Reports / Day',
                          style: pw.TextStyle(
                            fontSize: chipValueFont,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        _buildTrendChart(trend, height: chartHeight),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Avg Expert Response (hrs)',
                          style: pw.TextStyle(
                            fontSize: chipValueFont,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        _buildResponseTrendChart(
                          responseTrend,
                          height: chartHeight,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: isSmall ? 6 : 8),
              pw.Text(
                'Disease Distribution',
                style: pw.TextStyle(
                  fontSize: chipValueFont,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              _buildDiseaseTable(
                diseaseStats,
                maxRows: tableRows,
                fontSize: tableFont,
              ),
              pw.SizedBox(height: isSmall ? 4 : 6),
              pw.Text(
                'Tip burn/Unknown are excluded from disease counts.',
                style: pw.TextStyle(fontSize: chipLabelFont),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'report_${now.millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _buildDiseaseTable(
    List<Map<String, dynamic>> stats, {
    int maxRows = 6,
    double fontSize = 10,
  }) {
    final sorted = [...stats]
      ..sort((a, b) => (b['count'] ?? 0).compareTo(a['count'] ?? 0));
    final top = sorted.take(maxRows).toList();
    if (sorted.length > maxRows) {
      final others = sorted.skip(maxRows);
      final othersCount = others.fold<int>(
        0,
        (sum, d) => sum + ((d['count'] as num? ?? 0).toInt()),
      );
      final othersPct = others.fold<double>(
        0.0,
        (sum, d) => sum + ((d['percentage'] ?? 0.0) as double),
      );
      top.add({
        'name': 'Others',
        'count': othersCount,
        'percentage': othersPct,
      });
    }

    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: fontSize,
    );
    final cellStyle = pw.TextStyle(fontSize: fontSize);

    final rows = <pw.TableRow>[
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Disease', style: headerStyle),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Count', style: headerStyle),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Percentage', style: headerStyle),
          ),
        ],
      ),
    ];

    for (final d in top) {
      final name = (d['name'] ?? 'Unknown').toString();
      final count = (d['count'] ?? 0).toString();
      final pct = ((d['percentage'] ?? 0.0) * 100).toStringAsFixed(1) + '%';
      rows.add(
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(name, style: cellStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(count, style: cellStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(pct, style: cellStyle),
            ),
          ],
        ),
      );
    }

    if (stats.isEmpty) {
      rows.add(
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('No Data', style: cellStyle),
            ),
            pw.SizedBox(),
            pw.SizedBox(),
          ],
        ),
      );
    }

    return pw.Table(border: pw.TableBorder.all(width: 0.5), children: rows);
  }

  static pw.Widget _statChip(
    String label,
    String value,
    double labelFont,
    double valueFont,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: pdf.PdfColors.grey300, width: 0.5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: labelFont,
              color: pdf.PdfColors.grey700,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: valueFont,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTrendChart(
    List<MapEntry<String, int>> trend, {
    double height = 180,
  }) {
    if (trend.isEmpty) {
      return pw.Text('No trend data');
    }

    final points = <pw.PointChartValue>[];
    int maxY = 1;
    for (int i = 0; i < trend.length; i++) {
      final y = trend[i].value;
      if (y > maxY) maxY = y;
      points.add(pw.PointChartValue(i.toDouble(), y.toDouble()));
    }

    // Simple Cartesian chart using pw.Chart
    return pw.Container(
      height: height,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(
            List<String>.from(trend.map((e) => e.key.substring(5))),
            marginStart: 10,
            marginEnd: 10,
          ),
          yAxis: pw.FixedAxis([
            for (int i = 0; i <= maxY; i++) i.toDouble(),
          ], format: (v) => v.toInt().toString()),
        ),
        datasets: [
          pw.LineDataSet(
            drawSurface: true,
            isCurved: true,
            color: pdf.PdfColors.blue,
            data: points,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildResponseTrendChart(
    List<MapEntry<String, double>> trend, {
    double height = 180,
  }) {
    if (trend.isEmpty) {
      return pw.Text('No response-time data');
    }

    final points = <pw.PointChartValue>[];
    double maxY = 1.0;
    for (int i = 0; i < trend.length; i++) {
      final y = trend[i].value;
      if (y > maxY) maxY = y;
      points.add(pw.PointChartValue(i.toDouble(), y));
    }

    return pw.Container(
      height: height,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(
            List<String>.from(trend.map((e) => e.key.substring(5))),
            marginStart: 10,
            marginEnd: 10,
          ),
          yAxis: pw.FixedAxis([
            for (double i = 0; i <= maxY; i += _safeStep(maxY)) i,
          ], format: (v) => v.toStringAsFixed(1)),
        ),
        datasets: [
          pw.LineDataSet(
            drawSurface: false,
            isCurved: true,
            color: pdf.PdfColors.deepOrange,
            data: points,
          ),
        ],
      ),
    );
  }

  static pdf.PdfPageFormat _resolvePageFormat(String name) {
    switch (name.toLowerCase()) {
      case 'letter':
        return pdf.PdfPageFormat.letter;
      case 'legal':
        return pdf.PdfPageFormat.legal;
      case 'a3':
        return pdf.PdfPageFormat.a3;
      case 'a5':
        return pdf.PdfPageFormat.a5;
      case 'a4':
      default:
        return pdf.PdfPageFormat.a4;
    }
  }

  static double _safeStep(double maxY) {
    final step = maxY / 4.0;
    if (step.isNaN || step.isInfinite || step <= 0.0) return 1.0;
    return step.clamp(0.5, 24.0);
  }
}
