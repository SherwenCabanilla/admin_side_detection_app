import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';
import 'scan_requests_service.dart';
// import 'settings_service.dart';
import 'weather_service.dart';

class ReportPdfService {
  static Future<void> generateAndShareReport({
    required BuildContext context,
    required String timeRange,
    String pageSize = 'A4',
    String? backgroundAsset,
    required String preparedBy,
  }) async {
    // Fetch data needed for the report
    // Get all requests
    final List<Map<String, dynamic>> allRequests =
        await ScanRequestsService.getScanRequests();

    // Determine reporting period for filtering by createdAt (when disease occurred)
    DateTime startDate;
    DateTime endDate;
    final nowForRange = DateTime.now();
    if (timeRange.startsWith('Custom (')) {
      final regex = RegExp(
        r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(timeRange);
      if (match != null) {
        startDate = DateTime.parse(match.group(1)!);
        endDate = DateTime.parse(match.group(2)!);
      } else {
        endDate = nowForRange;
        startDate = endDate.subtract(const Duration(days: 7));
      }
    } else {
      switch (timeRange) {
        case '1 Day':
          endDate = nowForRange;
          startDate = endDate.subtract(const Duration(days: 1));
          break;
        case 'Last 7 Days':
          endDate = nowForRange;
          startDate = endDate.subtract(const Duration(days: 7));
          break;
        case 'Last 30 Days':
          endDate = nowForRange;
          startDate = endDate.subtract(const Duration(days: 30));
          break;
        case 'Last 60 Days':
          endDate = nowForRange;
          startDate = endDate.subtract(const Duration(days: 60));
          break;
        case 'Last 90 Days':
          endDate = nowForRange;
          startDate = endDate.subtract(const Duration(days: 90));
          break;
        case 'Last Year':
          endDate = nowForRange;
          startDate = DateTime(
            nowForRange.year - 1,
            nowForRange.month,
            nowForRange.day,
          );
          break;
        default:
          // Handle Monthly ranges that weren't caught by the Custom regex above
          if (timeRange.startsWith('Monthly (')) {
            final regex = RegExp(
              r'Monthly \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
            );
            final match = regex.firstMatch(timeRange);
            if (match != null) {
              startDate = DateTime.parse(match.group(1)!);
              endDate = DateTime.parse(match.group(2)!);
            } else {
              endDate = nowForRange;
              startDate = endDate.subtract(const Duration(days: 7));
            }
          } else {
            endDate = nowForRange;
            startDate = endDate.subtract(const Duration(days: 7));
          }
      }
    }

    // CreatedAt-anchored, completed-only list for disease analysis
    // This shows diseases that occurred in the time period (validated by experts)
    final DateTime startInclusive = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final DateTime endExclusive = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    ).add(const Duration(days: 1));

    final List<Map<String, dynamic>> filteredCreatedCompleted = [];
    for (final r in allRequests) {
      // Only include completed (expert-validated) scans
      if ((r['status'] ?? '') != 'completed') continue;
      final createdRaw = r['createdAt'];
      if (createdRaw == null) continue;
      DateTime created;
      if (createdRaw is String) {
        created = DateTime.tryParse(createdRaw) ?? startInclusive;
      } else if (createdRaw.runtimeType.toString() == 'Timestamp') {
        created = createdRaw.toDate();
      } else {
        continue;
      }
      final bool inWindow =
          !created.isBefore(startInclusive) && created.isBefore(endExclusive);
      if (inWindow) filteredCreatedCompleted.add(r);
    }

    // Build disease stats from validated data
    final Map<String, int> diseaseCounts = {};
    int totalDetections = 0;
    for (final r in filteredCreatedCompleted) {
      List<dynamic> diseaseSummary = [];
      if (r['diseaseSummary'] != null) {
        diseaseSummary = r['diseaseSummary'] as List<dynamic>? ?? [];
      } else if (r['diseases'] != null) {
        diseaseSummary = r['diseases'] as List<dynamic>? ?? [];
      } else if (r['detections'] != null) {
        diseaseSummary = r['detections'] as List<dynamic>? ?? [];
      } else if (r['results'] != null) {
        diseaseSummary = r['results'] as List<dynamic>? ?? [];
      }
      for (final d in diseaseSummary) {
        String name = 'Unknown';
        int count = 1;
        if (d is Map<String, dynamic>) {
          name = d['name'] ?? d['label'] ?? d['disease'] ?? 'Unknown';
          count = d['count'] ?? d['confidence'] ?? 1;
        } else if (d is String) {
          name = d;
        }
        final lower = name.toLowerCase();
        if (lower.contains('tip burn') || lower.contains('unknown')) continue;
        diseaseCounts[name] = (diseaseCounts[name] ?? 0) + count;
        totalDetections += count;
      }
    }
    final List<Map<String, dynamic>> diseaseStats = [];
    // Application frequency column removed per request; focus on trend only

    // We'll fill these soon; declare placeholders for closure
    List<String> trendLabelKeys = const [];
    Map<String, int> diseaseByDay = const {};
    Map<String, int> healthyByDay = const {};
    Map<String, Map<String, int>> diseaseDayCounts = const {};

    String classifyTrend(String diseaseName) {
      // Build series for this disease from daily counts
      final lower = diseaseName.toLowerCase();
      final entries =
          trendLabelKeys.map((k) {
            final val =
                lower == 'healthy'
                    ? (healthyByDay[k] ?? 0)
                    : ((diseaseDayCounts[lower] ?? const <String, int>{})[k] ??
                        0);
            return val.toDouble();
          }).toList();
      if (entries.isEmpty) return 'N/A';
      if (entries.length < 2) return 'N/A';

      // Split the time range into two halves and compare their averages
      // This is intuitive: "first half vs second half of the period"
      final n = entries.length;
      final midPoint = n ~/ 2; // integer division

      // Calculate average of first half
      double firstHalfSum = 0.0;
      for (int i = 0; i < midPoint; i++) {
        firstHalfSum += entries[i];
      }
      final firstHalfAvg = midPoint > 0 ? firstHalfSum / midPoint : 0.0;

      // Calculate average of second half
      double secondHalfSum = 0.0;
      final secondHalfCount = n - midPoint;
      for (int i = midPoint; i < n; i++) {
        secondHalfSum += entries[i];
      }
      final secondHalfAvg =
          secondHalfCount > 0 ? secondHalfSum / secondHalfCount : 0.0;

      // Compare the two halves
      final delta = secondHalfAvg - firstHalfAvg;

      // Threshold: if difference is more than 1 detection on average
      const double eps = 1.0;
      if (delta > eps) return 'Increasing';
      if (delta < -eps) return 'Decreasing';
      return 'Stable';
    }

    diseaseCounts.forEach((name, count) {
      final pct = totalDetections > 0 ? count / totalDetections : 0.0;
      diseaseStats.add({
        'name': name,
        'count': count,
        'percentage': pct,
        'type': name.toLowerCase() == 'healthy' ? 'healthy' : 'disease',
        'trend': 'N/A',
      });
    });
    diseaseStats.sort(
      (a, b) => (b['count'] as int).compareTo(a['count'] as int),
    );

    // Fetch weather summary (avg/min/max temp) for range
    final weather = await WeatherService.getAverageTemperature(
      start: DateTime(startDate.year, startDate.month, startDate.day),
      end: DateTime(endDate.year, endDate.month, endDate.day),
    );
    // If weather summary is entirely empty (e.g., API no data for a single day),
    // use a safe label to avoid NaN formatting downstream
    final String weatherLabel = weather.toLabel();
    // Daily series for chart: separate disease vs healthy counts
    // Group by createdAt (when disease occurred)
    diseaseByDay = {};
    healthyByDay = {};
    diseaseDayCounts = {};
    for (final r in filteredCreatedCompleted) {
      final createdAt = r['createdAt'];
      DateTime dt;
      if (createdAt is String) {
        dt = DateTime.tryParse(createdAt) ?? DateTime.now();
      } else {
        dt = createdAt.toDate();
      }
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

      // Split detections into healthy vs disease for this day
      List<dynamic> diseaseSummary = [];
      if (r['diseaseSummary'] != null) {
        diseaseSummary = r['diseaseSummary'] as List<dynamic>? ?? [];
      } else if (r['diseases'] != null) {
        diseaseSummary = r['diseases'] as List<dynamic>? ?? [];
      } else if (r['detections'] != null) {
        diseaseSummary = r['detections'] as List<dynamic>? ?? [];
      } else if (r['results'] != null) {
        diseaseSummary = r['results'] as List<dynamic>? ?? [];
      }

      if (diseaseSummary.isNotEmpty) {
        for (final d in diseaseSummary) {
          String name = 'Unknown';
          int count = 1;
          if (d is Map<String, dynamic>) {
            name = d['name'] ?? d['label'] ?? d['disease'] ?? 'Unknown';
            count = d['count'] ?? d['confidence'] ?? 1;
          } else if (d is String) {
            name = d;
          }
          final lower = name.toLowerCase();
          if (lower.contains('tip burn') || lower.contains('unknown')) {
            continue;
          }
          if (lower == 'healthy') {
            healthyByDay[key] = (healthyByDay[key] ?? 0) + count;
          } else {
            diseaseByDay[key] = (diseaseByDay[key] ?? 0) + count;
            final perDay = diseaseDayCounts[lower] ?? <String, int>{};
            perDay[key] = (perDay[key] ?? 0) + count;
            diseaseDayCounts[lower] = perDay;
          }
        }
      }
    }
    // Build aligned label set (dates) and ordered series arrays
    final allKeys =
        <String>{}
          ..addAll(diseaseByDay.keys)
          ..addAll(healthyByDay.keys);
    trendLabelKeys = allKeys.toList()..sort();
    // Build full series first from complete label keys - convert to percentages
    final healthySeriesFull =
        trendLabelKeys.map((k) {
          final healthyCount = healthyByDay[k] ?? 0;
          final diseaseCount = diseaseByDay[k] ?? 0;
          final totalCount = healthyCount + diseaseCount;
          return totalCount > 0 ? (healthyCount / totalCount) : 0.0;
        }).toList();

    // Downsample labels for display; remap series to those label positions
    final List<String> displayLabels =
        _downsampleLabels(trendLabelKeys).map((e) => e.substring(5)).toList();
    final List<String> displayKeys = _downsampleLabels(trendLabelKeys);
    final Map<String, int> keyIndex = {
      for (int i = 0; i < trendLabelKeys.length; i++) trendLabelKeys[i]: i,
    };
    final healthySeries = [
      for (final k in displayKeys) healthySeriesFull[keyIndex[k] ?? 0],
    ];

    // Now that labels and daily series are ready, fill trend per disease
    for (final item in diseaseStats) {
      final name = (item['name'] ?? '').toString();
      item['trend'] = classifyTrend(name);
    }
    // Split stats into healthy vs disease for separate tables
    final List<Map<String, dynamic>> healthyOnlyStats =
        diseaseStats.where((e) => (e['type'] ?? '') == 'healthy').toList();
    final List<Map<String, dynamic>> diseaseOnlyStats =
        diseaseStats.where((e) => (e['type'] ?? '') != 'healthy').toList();
    // Overview counts: use the already-filtered list (diseases that occurred in period)
    final int completed = filteredCreatedCompleted.length;
    // SLA and average response time are no longer shown in the report

    // Fonts: Noto Sans (print-friendly, wide coverage)
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document();

    // Prepared by comes from caller (admin profile name)
    final String utilityName = preparedBy.trim();

    final now = DateTime.now();
    // Title without date range (moved to Reporting Period line)
    final String title = 'Mango Disease Summary';

    // Layout + unified typography
    final bool isSmall = pageSize.toLowerCase() == 'a5';
    final double margin = isSmall ? 10 : 16;
    final double scale = isSmall ? 0.9 : 1.0; // compact on smaller pages
    // Type scale (consistent across the document)
    const double baseH1 = 16.0;
    const double baseH2 = 13.0;
    const double baseBody = 10.5;
    const double baseCaption = 9.5;
    const double baseTable = 10.0;
    final pw.TextStyle tsH1 = pw.TextStyle(
      font: boldFont,
      fontSize: baseH1 * scale,
    );
    final pw.TextStyle tsH2 = pw.TextStyle(
      font: boldFont,
      fontSize: baseH2 * scale,
    );
    final pw.TextStyle tsBody = pw.TextStyle(
      font: baseFont,
      fontSize: baseBody * scale,
    );
    final pw.TextStyle tsCaption = pw.TextStyle(
      font: baseFont,
      fontSize: baseCaption * scale,
    );
    // Table styles are applied via _buildDiseaseTable parameters
    // Make charts compact but readable to fit executive summary and all content in 2 pages
    final double chartHeight = isSmall ? 70 : 85;
    final int tableRows = isSmall ? 3 : 5;

    // If using a background template with embedded logos, we won't draw logos here
    final bool useBackground = backgroundAsset != null;
    final pw.ImageProvider? bgImage =
        useBackground ? await _tryLoadLogo(backgroundAsset) : null;

    final pw.PageTheme pageTheme = pw.PageTheme(
      pageFormat: _resolvePageFormat(pageSize),
      margin:
          bgImage == null
              ? pw.EdgeInsets.all(margin)
              : pw.EdgeInsets.fromLTRB(
                isSmall ? 14 : 28,
                isSmall ? 110 : 140,
                isSmall ? 14 : 28,
                isSmall ? 80 : 100,
              ),
      buildBackground: (context) {
        if (bgImage == null) return pw.SizedBox();
        return pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(bgImage, fit: pw.BoxFit.cover),
        );
      },
    );

    // Build disease multi-series for top 4 diseases
    final Map<String, List<double>> diseaseSeriesByName = {};
    // Determine top 4 diseases by total counts
    final List<MapEntry<String, int>> totals =
        diseaseDayCounts.entries
            .map(
              (e) => MapEntry(
                e.key,
                e.value.values.fold<int>(0, (sum, v) => sum + v),
              ),
            )
            .toList()
          ..removeWhere(
            (e) =>
                e.key == 'healthy' ||
                e.key.contains('tip burn') ||
                e.key.contains('unknown'),
          )
          ..sort((a, b) => b.value.compareTo(a.value));
    final topDiseases = totals.take(4).map((e) => e.key).toList();
    for (final name in topDiseases) {
      final perDay = diseaseDayCounts[name] ?? const <String, int>{};
      final series =
          displayKeys.map((k) {
            final diseaseCount = perDay[k] ?? 0;
            final healthyCount = healthyByDay[k] ?? 0;
            final totalCount = diseaseCount + healthyCount;
            return totalCount > 0 ? (diseaseCount / totalCount) : 0.0;
          }).toList();
      diseaseSeriesByName[name] = series;
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        build:
            (context) => [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(title, style: tsH1),
                  pw.Text(_fmtHumanDate(now), style: tsCaption),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Reporting Period: ' + _fmtHumanRange(startDate, endDate),
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: (baseBody * scale) * 1.15,
                      color: pdf.PdfColors.black,
                    ),
                  ),
                  pw.SizedBox(),
                ],
              ),
              pw.Divider(thickness: 0.7),
              _labeledRow(
                'Location:',
                'Barangay Cebulano, Carmen, Davao del Norte',
                baseBody * scale,
                font: baseFont,
                boldFont: boldFont,
              ),
              _labeledRow(
                'Weather Summary:',
                weatherLabel,
                baseBody * scale,
                font: baseFont,
                boldFont: boldFont,
              ),
              pw.Divider(thickness: 0.7),
              pw.SizedBox(height: isSmall ? 3 : 4),

              // === EXECUTIVE SUMMARY ===
              pw.Text('Executive Summary', style: tsH2),
              pw.SizedBox(height: 2),
              _buildExecutiveSummary(
                diseaseStats,
                healthyOnlyStats,
                diseaseOnlyStats,
                completed,
                baseBody * scale,
                baseFont,
                boldFont,
              ),
              pw.SizedBox(height: isSmall ? 3 : 4),

              // === HEALTHY SECTION ===
              // Healthy Trend chart
              pw.SizedBox(height: isSmall ? 4 : 6),
              pw.Text('Healthy Trend (Daily Percentages)', style: tsH2),
              pw.SizedBox(height: 3),
              _buildSingleLineChart(
                displayLabels,
                healthySeries,
                color: pdf.PdfColors.blue,
                height: chartHeight,
              ),
              pw.SizedBox(height: 6),
              pw.Text(_healthyConclusion(healthySeries), style: tsCaption),

              // Healthy Distribution (paired with chart above)
              pw.SizedBox(height: isSmall ? 4 : 6),
              pw.Text('Healthy Distribution (Total Counts)', style: tsH2),
              pw.SizedBox(height: 3),
              _buildStatsTable(
                healthyOnlyStats,
                firstColumnLabel: 'Category',
                maxRows: 4,
                fontSize: baseTable * scale,
                font: baseFont,
                boldFont: boldFont,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                _distributionConclusion(healthyOnlyStats, isHealthy: true),
                style: tsCaption,
              ),

              // === SECTION SEPARATOR - FORCE PAGE BREAK ===
              pw.NewPage(),

              // === DISEASE SECTION ===
              // Disease Trends chart (top 4 diseases)
              pw.SizedBox(height: isSmall ? 4 : 6),
              pw.Text('Disease Trends (Daily Percentages)', style: tsH2),
              pw.SizedBox(height: 3),
              _buildMultiLineDiseaseChart(
                displayLabels,
                diseaseSeriesByName,
                order: topDiseases,
                height: chartHeight,
              ),
              pw.SizedBox(height: 3),
              // Legend for diseases
              pw.Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  for (int i = 0; i < topDiseases.length; i++)
                    _legendSwatch(
                      _colorForDisease(topDiseases[i]),
                      _titleCase(topDiseases[i]),
                    ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                _diseaseConclusion(diseaseSeriesByName),
                style: tsCaption,
              ),

              // Disease Distribution (paired with chart above - excludes Tip burn/Unknown)
              pw.SizedBox(height: isSmall ? 4 : 6),
              pw.Text('Disease Distribution (Total Counts)', style: tsH2),
              pw.SizedBox(height: 3),
              _buildStatsTable(
                diseaseOnlyStats,
                firstColumnLabel: 'Disease',
                maxRows: tableRows,
                fontSize: baseTable * scale,
                font: baseFont,
                boldFont: boldFont,
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                _distributionConclusion(diseaseOnlyStats, isHealthy: false),
                style: tsCaption,
              ),

              // General notes
              pw.SizedBox(height: isSmall ? 4 : 6),
              pw.Text('Notes', style: tsH2),
              pw.SizedBox(height: 2),
              pw.Bullet(
                text:
                    'Charts are sampled to keep labels readable; underlying calculations use full data.',
                style: tsCaption,
              ),
              pw.Bullet(
                text:
                    'Trends compare the average of the first half versus the second half of the time range, providing a clear and intuitive measure of change over the period.',
                style: tsCaption,
              ),

              // Signature Section
              pw.SizedBox(height: isSmall ? 40 : 60),
              pw.Padding(
                padding: pw.EdgeInsets.symmetric(horizontal: isSmall ? 20 : 40),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Left side - Prepared By
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Prepared By: _________________',
                            style: tsBody,
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Agricultural Technologist',
                            style: tsCaption,
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 20),
                    // Right side - Certified Correct By
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Certified Correct By: ${utilityName.isEmpty ? 'Admin name' : utilityName}',
                            style: tsBody,
                            textAlign: pw.TextAlign.right,
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Municipal Agriculturist',
                            style: tsCaption,
                            textAlign: pw.TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
      ),
    );

    final String filename = _buildReportFilename(
      timeRange: timeRange,
      start: startDate,
      end: endDate,
    );
    await Printing.sharePdf(bytes: await doc.save(), filename: filename);
  }

  // Keep about 8 evenly spaced labels; always include first and last.
  static List<String> _downsampleLabels(List<String> sortedFullYmd) {
    if (sortedFullYmd.length <= 8) {
      return sortedFullYmd;
    }
    final int n = sortedFullYmd.length;
    final int step = (n / 8).ceil();
    final List<String> out = [];
    for (int i = 0; i < n; i += step) {
      out.add(sortedFullYmd[i]);
    }
    // Ensure last label present
    final String last = sortedFullYmd.last;
    if (out.last != last) out.add(last);
    return out;
  }

  static pw.Widget _buildDiseaseTable(
    List<Map<String, dynamic>> stats, {
    int maxRows = 6,
    double fontSize = 10,
    pw.Font? font,
    pw.Font? boldFont,
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
      font: boldFont,
    );
    final cellStyle = pw.TextStyle(fontSize: fontSize, font: font);

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
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Trend', style: headerStyle),
          ),
          // Frequency column removed
        ],
      ),
    ];

    for (final d in top) {
      final name = (d['name'] ?? 'Unknown').toString();
      final count = (d['count'] ?? 0).toString();
      final pct = ((d['percentage'] ?? 0.0) * 100).toStringAsFixed(1) + '%';
      final trend = (d['trend'] ?? 'N/A').toString();
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
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(trend, style: cellStyle),
            ),
            // Frequency cell removed
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

  // Removed statChip helper (not used in simplified layout)

  static pw.Widget _buildStatsTable(
    List<Map<String, dynamic>> stats, {
    String firstColumnLabel = 'Disease',
    int maxRows = 6,
    double fontSize = 10,
    pw.Font? font,
    pw.Font? boldFont,
  }) {
    final normalized =
        stats
            .map(
              (e) => {
                'name': (e['name'] ?? 'Unknown').toString(),
                'count': (e['count'] as num? ?? 0).toInt(),
                'percentage': (e['percentage'] as double? ?? 0.0),
                'trend': (e['trend'] ?? 'N/A').toString(),
              },
            )
            .toList();
    return _buildDiseaseTable(
      normalized,
      maxRows: maxRows,
      fontSize: fontSize,
      font: font,
      boldFont: boldFont,
    );
  }

  // Removed old combined trend and response-time helpers

  static pw.Widget _buildExecutiveSummary(
    List<Map<String, dynamic>> diseaseStats,
    List<Map<String, dynamic>> healthyStats,
    List<Map<String, dynamic>> diseaseOnlyStats,
    int completed,
    double fontSize,
    pw.Font? font,
    pw.Font? boldFont,
  ) {
    // Calculate overall health percentage
    final int totalHealthy = healthyStats.fold<int>(
      0,
      (sum, item) => sum + (item['count'] as int),
    );
    final int totalDiseased = diseaseOnlyStats.fold<int>(
      0,
      (sum, item) => sum + (item['count'] as int),
    );
    final int totalLeaves = totalHealthy + totalDiseased;
    final double healthyPercentage =
        totalLeaves > 0 ? (totalHealthy / totalLeaves) * 100 : 0.0;
    final double diseasedPercentage =
        totalLeaves > 0 ? (totalDiseased / totalLeaves) * 100 : 0.0;

    // Get top disease
    final topDisease =
        diseaseOnlyStats.isNotEmpty ? diseaseOnlyStats.first : null;
    final String topDiseaseName = topDisease?['name'] ?? 'None';
    final double topDiseasePercentage =
        ((topDisease?['percentage'] ?? 0.0) as double) * 100;

    // Calculate trend (simplified)
    final String trend =
        healthyPercentage > 70
            ? 'Good'
            : healthyPercentage > 50
            ? 'Moderate'
            : 'Poor';

    final boldStyle = pw.TextStyle(
      fontSize: fontSize * 1.05,
      font: boldFont,
      fontWeight: pw.FontWeight.bold,
    );
    final regularStyle = pw.TextStyle(fontSize: fontSize, font: font);

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: pdf.PdfColors.white,
        border: pw.Border.all(color: pdf.PdfColors.grey300, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // LEFT SIDE - Professional Health Chart
          pw.Container(
            width: 100,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Chart Title
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ),
                  decoration: pw.BoxDecoration(
                    color: pdf.PdfColors.grey800,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    'HEALTH STATUS',
                    style: pw.TextStyle(
                      fontSize: fontSize * 0.75,
                      font: boldFont,
                      fontWeight: pw.FontWeight.bold,
                      color: pdf.PdfColors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),

                // Bar Chart Container
                pw.Container(
                  height: 75,
                  decoration: pw.BoxDecoration(
                    color: pdf.PdfColors.white,
                    border: pw.Border.all(
                      color: pdf.PdfColors.grey300,
                      width: 1.5,
                    ),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Chart(
                    grid: pw.CartesianGrid(
                      xAxis: pw.FixedAxis.fromStrings(
                        ['Healthy', 'Diseased'],
                        marginStart: 12,
                        marginEnd: 12,
                        textStyle: pw.TextStyle(
                          fontSize: fontSize * 0.65,
                          font: font,
                        ),
                      ),
                      yAxis: pw.FixedAxis(
                        [0, 25, 50, 75, 100],
                        format: (v) => '${v.toInt()}%',
                        divisions: true,
                        textStyle: pw.TextStyle(
                          fontSize: fontSize * 0.6,
                          font: font,
                        ),
                      ),
                    ),
                    datasets: [
                      pw.BarDataSet(
                        color: pdf.PdfColors.green600,
                        borderColor: pdf.PdfColors.green800,
                        borderWidth: 1.5,
                        width: 20,
                        data: [pw.PointChartValue(0, healthyPercentage)],
                      ),
                      pw.BarDataSet(
                        color: pdf.PdfColors.red600,
                        borderColor: pdf.PdfColors.red800,
                        borderWidth: 1.5,
                        width: 20,
                        data: [pw.PointChartValue(1, diseasedPercentage)],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),

                // Percentage Badges
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: pdf.PdfColors.green600,
                        borderRadius: pw.BorderRadius.circular(12),
                        border: pw.Border.all(
                          color: pdf.PdfColors.green800,
                          width: 1,
                        ),
                      ),
                      child: pw.Text(
                        '${healthyPercentage.toStringAsFixed(1)}%',
                        style: pw.TextStyle(
                          fontSize: fontSize * 0.75,
                          color: pdf.PdfColors.white,
                          font: boldFont,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: pdf.PdfColors.red600,
                        borderRadius: pw.BorderRadius.circular(12),
                        border: pw.Border.all(
                          color: pdf.PdfColors.red800,
                          width: 1,
                        ),
                      ),
                      child: pw.Text(
                        '${diseasedPercentage.toStringAsFixed(1)}%',
                        style: pw.TextStyle(
                          fontSize: fontSize * 0.75,
                          color: pdf.PdfColors.white,
                          font: boldFont,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(width: 12),

          // RIGHT SIDE - Plain Text Summary
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(top: 25),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.start,
                    children: [
                      pw.Text('• Overall Health: ', style: boldStyle),
                      pw.Text(
                        '${healthyPercentage.toStringAsFixed(1)}% Healthy, ${diseasedPercentage.toStringAsFixed(1)}% Diseased',
                        style: regularStyle,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.start,
                    children: [
                      pw.Text('• Primary Concern: ', style: boldStyle),
                      pw.Text(
                        '$topDiseaseName (${topDiseasePercentage.toStringAsFixed(1)}%)',
                        style: regularStyle,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.start,
                    children: [
                      pw.Text('• Health Status: ', style: boldStyle),
                      pw.Text(trend, style: regularStyle),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.start,
                    children: [
                      pw.Text('• Recommendation: ', style: boldStyle),
                      pw.Text(
                        topDiseaseName != 'None'
                            ? 'Focus treatment on $topDiseaseName'
                            : 'Continue monitoring crop health',
                        style: regularStyle,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.start,
                    children: [
                      pw.Text('• Total Reports: ', style: boldStyle),
                      pw.Text(
                        '$completed validated reports',
                        style: regularStyle,
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

  // _safeStep no longer used in simplified layout

  static String _fmtHumanDate(DateTime d) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = (d.month >= 1 && d.month <= 12) ? names[d.month - 1] : '';
    return '$m ${d.day}, ${d.year}';
  }

  static String _fmtHumanRange(DateTime start, DateTime end) {
    String m(int m) => _monthName(m);
    final sameMonth = start.month == end.month && start.year == end.year;
    if (sameMonth) {
      // Use ASCII hyphen to avoid missing glyphs in embedded PDF font
      return '${m(start.month)} ${start.day}-${end.day}, ${end.year}';
    }
    return '${m(start.month)} ${start.day}, ${start.year} - ${m(end.month)} ${end.day}, ${end.year}';
  }

  static String _monthName(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }

  static String _buildReportFilename({
    required String timeRange,
    required DateTime start,
    required DateTime end,
  }) {
    String fmt(DateTime d) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final m = (d.month >= 1 && d.month <= 12) ? months[d.month - 1] : '';
      return '$m ${d.day}, ${d.year}';
    }

    String clean(String s) {
      // Replace characters that may be problematic in filenames
      final replaced = s.replaceAll(RegExp(r'[^A-Za-z0-9 _\-\(\),]'), '_');
      // Collapse multiple spaces/underscores
      return replaced
          .replaceAll(RegExp(r'[\s_]+'), ' ')
          .trim()
          .replaceAll(' ', '_');
    }

    // Detect if the period covers a full single month (useful when UI passes
    // Monthly ranges as Custom).
    bool isFullMonthRange(DateTime s, DateTime e) {
      final startIsFirst = s.day == 1;
      final sameMonth = s.year == e.year && s.month == e.month;
      final lastDay = DateTime(s.year, s.month + 1, 0).day; // last day of month
      final endIsLast = e.day == lastDay;
      return startIsFirst && sameMonth && endIsLast;
    }

    String base;
    if (timeRange.startsWith('Monthly (') || isFullMonthRange(start, end)) {
      const monthsLong = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final label = '${monthsLong[start.month - 1]}_${start.year.toString()}';
      base = 'Monthly_Report_' + label;
    } else if (timeRange.startsWith('Custom (')) {
      base = 'Custom_Report_${fmt(start)}_to_${fmt(end)}';
    } else {
      // Preset ranges (e.g., Last 7 Days). Include type and human dates.
      base = 'Report_${timeRange}_${fmt(start)}_to_${fmt(end)}';
    }
    return clean(base) + '.pdf';
  }

  static Future<pw.ImageProvider?> _tryLoadLogo(String assetPath) async {
    try {
      final bytes = await rootBundle.load(assetPath);
      return pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static pw.Widget _labeledRow(
    String label,
    String value,
    double fontSize, {
    pw.Font? font,
    pw.Font? boldFont,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2, bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label ',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: fontSize,
                font: boldFont,
              ),
            ),
            pw.TextSpan(
              text: value,
              style: pw.TextStyle(fontSize: fontSize, font: font),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _legendSwatch(pdf.PdfColor color, String label) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(width: 10, height: 10, color: color),
        pw.SizedBox(width: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  // Frequency extraction removed (not used)

  // Recommendations section removed as per request
  static pw.Widget _buildSingleLineChart(
    List<String> labels,
    List<double> values, {
    pdf.PdfColor color = pdf.PdfColors.green,
    double height = 180,
  }) {
    if (labels.isEmpty || labels.length < 2) {
      return pw.Text('No trend data');
    }
    // Convert to percentages (0-100)
    final percentageValues =
        values.map((v) => (v.isFinite ? v : 0.0) * 100).toList();
    double maxY = 100.0; // Max percentage is 100%
    final step = 25.0; // 25% intervals
    return pw.Container(
      height: height,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(
            labels,
            marginStart: 10,
            marginEnd: 10,
          ),
          yAxis: pw.FixedAxis([
            for (double i = 0; i <= maxY; i += step) i,
          ], format: (v) => '${v.toStringAsFixed(0)}%'),
        ),
        datasets: [
          pw.LineDataSet(
            drawSurface: false,
            isCurved: true,
            color: color,
            data: [
              for (int i = 0; i < percentageValues.length; i++)
                pw.PointChartValue(
                  i.toDouble(),
                  percentageValues[i].isFinite ? percentageValues[i] : 0.0,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMultiLineDiseaseChart(
    List<String> labels,
    Map<String, List<double>> seriesByName, {
    required List<String> order,
    double height = 180,
  }) {
    if (labels.isEmpty || labels.length < 2 || seriesByName.isEmpty) {
      return pw.Text('No disease trend data');
    }
    // Convert all series to percentages (0-100)
    final percentageSeriesByName = <String, List<double>>{};
    for (final entry in seriesByName.entries) {
      percentageSeriesByName[entry.key] =
          entry.value.map((v) => (v.isFinite ? v : 0.0) * 100).toList();
    }

    double maxY = 100.0; // Max percentage is 100%
    final step = 25.0; // 25% intervals
    final datasets = <pw.Dataset>[];
    for (int idx = 0; idx < order.length; idx++) {
      final String diseaseName = order[idx];
      final series = percentageSeriesByName[diseaseName] ?? const <double>[];
      datasets.add(
        pw.LineDataSet(
          drawSurface: false,
          isCurved: true,
          color: _colorForDisease(diseaseName),
          data: [
            for (int i = 0; i < series.length; i++)
              pw.PointChartValue(
                i.toDouble(),
                series[i].isFinite ? series[i] : 0.0,
              ),
          ],
        ),
      );
    }

    return pw.Container(
      height: height,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(
            labels,
            marginStart: 10,
            marginEnd: 10,
          ),
          yAxis: pw.FixedAxis([
            for (double i = 0; i <= maxY; i += step) i,
          ], format: (v) => '${v.toStringAsFixed(0)}%'),
        ),
        datasets: datasets,
      ),
    );
  }

  static pdf.PdfColor _colorForDisease(String name) {
    final n = name.toLowerCase();
    if (n.contains('powdery')) return pdf.PdfColors.green; // Powdery Mildew
    if (n.contains('anthracnose')) return pdf.PdfColors.orange; // Anthracnose
    if (n.contains('bacterial') && n.contains('black'))
      return pdf.PdfColors.purple; // Bacterial black spot
    if (n.contains('dieback')) return pdf.PdfColors.red; // Dieback
    return pdf.PdfColors.red; // default for any other disease
  }

  static String _healthyConclusion(List<double> series) {
    if (series.isEmpty) return 'No data shown.';

    // Split the time range into two halves and compare averages
    final n = series.length;
    if (n < 2) return 'Insufficient data for trend analysis.';

    final midPoint = n ~/ 2;

    // Calculate average of first half
    double firstHalfSum = 0.0;
    for (int i = 0; i < midPoint; i++) {
      final val = series[i].isFinite ? series[i] : 0.0;
      firstHalfSum += val;
    }
    final firstHalfAvg = midPoint > 0 ? firstHalfSum / midPoint : 0.0;

    // Calculate average of second half
    double secondHalfSum = 0.0;
    final secondHalfCount = n - midPoint;
    for (int i = midPoint; i < n; i++) {
      final val = series[i].isFinite ? series[i] : 0.0;
      secondHalfSum += val;
    }
    final secondHalfAvg =
        secondHalfCount > 0 ? secondHalfSum / secondHalfCount : 0.0;

    // Compare the two halves (values are already percentages 0-1)
    final delta =
        (secondHalfAvg - firstHalfAvg) * 100; // convert to percentage points
    const double eps = 5.0; // 5 percentage point threshold

    String direction;
    String detail;
    if (delta > eps) {
      direction = 'an increasing trend';
      detail =
          'The second half of the period shows ${delta.toStringAsFixed(1)}% higher healthy prevalence than the first half.';
    } else if (delta < -eps) {
      direction = 'a decreasing trend';
      detail =
          'The second half of the period shows ${(-delta).toStringAsFixed(1)}% lower healthy prevalence than the first half.';
    } else {
      direction = 'relatively stable conditions';
      detail =
          'The average healthy prevalence remained consistent between the first and second half of the period.';
    }

    final String summary =
        'Healthy prevalence shows ' + direction + '. ' + detail;
    final String context =
        ' This analysis compares the average of the first half versus the second half of the time range, providing a clear picture of the overall direction.';
    return summary + context;
  }

  static String _diseaseConclusion(Map<String, List<double>> seriesByName) {
    if (seriesByName.isEmpty) return 'No disease lines to summarize.';

    // Calculate first-half vs second-half change for each disease
    String? rising;
    double risingDelta = -1e9;
    String? falling;
    double fallingDelta = 1e9;

    seriesByName.forEach((name, s) {
      if (s.isEmpty || s.length < 2) return;

      final n = s.length;
      final midPoint = n ~/ 2;

      // Calculate average of first half
      double firstHalfSum = 0.0;
      for (int i = 0; i < midPoint; i++) {
        final val = s[i].isFinite ? s[i] : 0.0;
        firstHalfSum += val;
      }
      final firstHalfAvg = midPoint > 0 ? firstHalfSum / midPoint : 0.0;

      // Calculate average of second half
      double secondHalfSum = 0.0;
      final secondHalfCount = n - midPoint;
      for (int i = midPoint; i < n; i++) {
        final val = s[i].isFinite ? s[i] : 0.0;
        secondHalfSum += val;
      }
      final secondHalfAvg =
          secondHalfCount > 0 ? secondHalfSum / secondHalfCount : 0.0;

      // Calculate change (already in percentage form 0-1, convert to percentage points)
      final delta = (secondHalfAvg - firstHalfAvg) * 100;

      if (delta > risingDelta) {
        risingDelta = delta;
        rising = name;
      }
      if (delta < fallingDelta) {
        fallingDelta = delta;
        falling = name;
      }
    });

    const double eps = 3.0; // 3 percentage point threshold
    final bool hasUp = rising != null && risingDelta > eps;
    final bool hasDown = falling != null && fallingDelta < -eps;

    final String opening =
        hasUp
            ? _titleCase(rising!) +
                ' shows the strongest increase (${risingDelta.toStringAsFixed(1)}% higher in second half)'
            : 'No significant increasing disease trends are observed';
    final String middle =
        hasDown
            ? ', while ' +
                _titleCase(falling!) +
                ' shows the strongest decline (${(-fallingDelta).toStringAsFixed(1)}% lower in second half).'
            : '.';
    final String context =
        ' This analysis compares the average prevalence in the first half versus the second half of the time range.';
    final String guidance =
        ' Diseases showing increases warrant closer monitoring and potential intervention.';
    return opening + middle + context + ' ' + guidance;
  }

  static String _distributionConclusion(
    List<Map<String, dynamic>> rows, {
    required bool isHealthy,
  }) {
    if (rows.isEmpty) {
      return isHealthy
          ? 'No healthy detections recorded for the selected period.'
          : 'No disease detections recorded for the selected period.';
    }
    Map<String, dynamic> top = rows.first;
    for (final r in rows) {
      if ((r['count'] as num? ?? 0).toInt() >
          (top['count'] as num? ?? 0).toInt()) {
        top = r;
      }
    }
    final String topName = _titleCase((top['name'] ?? '').toString());
    final String topPct =
        (((top['percentage'] ?? 0.0) as double) * 100).toStringAsFixed(1) + '%';

    if (isHealthy) {
      return 'Healthy detections indicate instances without identified disease and serve as a baseline for field condition. '
              'In this period, Healthy accounts for ' +
          topPct +
          ' of observations, suggesting overall field health across the sampled days. '
              'Compare this share against disease categories to identify shifts toward or away from problematic conditions.';
    }

    return 'This table ranks the most frequent disease detections in the selected period. ' +
        topName +
        ' leads with ' +
        topPct +
        ' of total detections, providing a focal point for mitigation and monitoring. ' +
        'Use the trend column alongside counts to see which issues are expanding versus stabilizing.';
  }

  static String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }
}
