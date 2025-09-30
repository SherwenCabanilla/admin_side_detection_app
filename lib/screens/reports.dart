import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/report_pdf_service.dart';
// import '../services/settings_service.dart';
import '../shared/total_users_card.dart';
import '../shared/pending_approvals_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/scan_requests_service.dart';
// CSV export removed
// duplicate import removed
import 'admin_dashboard.dart' show ScanRequestsSnapshot;
import 'package:provider/provider.dart';
import 'dart:async';
// syncfusion date picker is imported in shared/date_range_picker.dart
import '../shared/date_range_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// picker moved to lib/shared/date_range_picker.dart

class Reports extends StatefulWidget {
  final VoidCallback? onGoToUsers;
  const Reports({Key? key, this.onGoToUsers}) : super(key: key);

  @override
  State<Reports> createState() => _ReportsState();
}

class _ReportsState extends State<Reports> {
  String _selectedTimeRange = 'Last 7 Days';
  bool _isLoading = true;

  // Real data from Firestore
  Map<String, dynamic> _stats = {
    'totalUsers': 0,
    'totalExperts': 0,
    'activeUsers': 0,
    'pendingApprovals': 0,
    'averageResponseTime': '0 hours',
  };

  List<Map<String, dynamic>> _reportsTrend = [];
  List<Map<String, dynamic>> _diseaseStats = [];
  List<Map<String, dynamic>> _avgResponseTrend = [];

  // SLA summary cached for display in KPI card (string like "85%")
  String? _slaWithin24h;
  String? _slaWithin48h;
  String? _completionRate;
  int? _overduePendingCount;

  String _monthName(int m) {
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

  String _displayRangeLabel(String range) {
    if (range.startsWith('Monthly (')) {
      final regex = RegExp(
        r'Monthly \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        try {
          final s = DateTime.parse(match.group(1)!);
          return '${_fullMonthName(s.month)} ${s.year}';
        } catch (_) {}
      }
      return range;
    }
    if (range.startsWith('Custom (')) {
      final regex = RegExp(
        r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        try {
          final s = DateTime.parse(match.group(1)!);
          final e = DateTime.parse(match.group(2)!);
          String fmt(DateTime d) =>
              '${_monthName(d.month)} ${d.day}, ${d.year}';
          return '${fmt(s)} to ${fmt(e)}';
        } catch (_) {}
      }
      return range.substring(8, range.length - 1);
    }
    return range;
  }

  String _fullMonthName(int m) {
    const names = [
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
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }

  String _formatTimeRangeForActivity(String range) {
    // Handle Monthly ranges
    if (range.startsWith('Monthly (')) {
      final regex = RegExp(
        r'Monthly \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        try {
          final s = DateTime.parse(match.group(1)!);
          return '"${_fullMonthName(s.month)} ${s.year}"';
        } catch (_) {}
      }
    }
    // Handle Custom ranges
    if (range.startsWith('Custom (')) {
      final regex = RegExp(
        r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        try {
          final s = DateTime.parse(match.group(1)!);
          final e = DateTime.parse(match.group(2)!);
          String fmt(DateTime d) =>
              '${_monthName(d.month)} ${d.day}, ${d.year}';
          return '"${fmt(s)} to ${fmt(e)}"';
        } catch (_) {}
      }
    }
    // Handle "Last 7 Days"
    if (range == 'Last 7 Days') {
      return '"Last 7 Days"';
    }
    return '"$range"';
  }

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadSavedTimeRange();
    print('[DEBUG] Saved time range loaded: $_selectedTimeRange');

    // Mark as initialized before loading data
    setState(() {
      _hasInitialized = true;
    });

    // Wait for all data to load
    await _loadData();

    // Now update stats with the correct saved time range
    print(
      '[DEBUG] Calling _updateStatsFromSnapshot after loadData with range: $_selectedTimeRange',
    );
    _updateStatsFromSnapshot();
  }

  Future<void> _loadSavedTimeRange() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRange = prefs.getString('selected_time_range');
      if (savedRange != null && savedRange.isNotEmpty) {
        setState(() {
          _selectedTimeRange = savedRange;
        });
      }
    } catch (e) {
      print('Error loading saved time range: $e');
    }
  }

  Future<void> _saveTimeRange(String timeRange) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_time_range', timeRange);
    } catch (e) {
      print('Error saving time range: $e');
    }
  }

  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only update on first call, after that updates are triggered by data loading
    if (!_hasInitialized) {
      return; // Skip initial call, let _initializeData handle it
    }
    _updateStatsFromSnapshot();
  }

  void _updateStatsFromSnapshot() async {
    final scanRequestsProvider = Provider.of<ScanRequestsSnapshot?>(
      context,
      listen: false,
    );
    final snapshot = scanRequestsProvider?.snapshot;
    if (snapshot == null) {
      // Fallback: update card KPIs using service when realtime snapshot is unavailable
      try {
        final counts = await ScanRequestsService.getCountsForTimeRange(
          timeRange: _selectedTimeRange,
        );
        final int completedByCreated = counts['completed'] ?? 0;
        final int pendingByCreated = counts['pending'] ?? 0;
        final int totalForCompletion = completedByCreated + pendingByCreated;
        final String completionRateStr =
            totalForCompletion == 0
                ? '—'
                : '${((completedByCreated / totalForCompletion) * 100).toStringAsFixed(0)}%';

        final int overduePendingCreated = counts['overduePending'] ?? 0;

        setState(() {
          _completionRate = completionRateStr;
          _overduePendingCount = overduePendingCreated;
        });
      } catch (_) {}
      return;
    }
    final scanRequests =
        snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'userId': data['userId'] ?? '',
            'userName': data['userName'] ?? '',
            'status': data['status'] ?? 'pending',
            'createdAt': data['submittedAt'] ?? data['createdAt'],
            'reviewedAt': data['reviewedAt'],
            'images': data['images'] ?? [],
            'diseaseSummary': data['diseaseSummary'] ?? [],
            'expertReview': data['expertReview'],
          };
        }).toList();

    // Build a reviewedAt-anchored time window to match card/SLA logic
    final DateTime now = DateTime.now();
    DateTime? startInclusive;
    DateTime? endExclusive;
    if (_selectedTimeRange.startsWith('Custom (') ||
        _selectedTimeRange.startsWith('Monthly (')) {
      final regex = RegExp(
        r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(_selectedTimeRange);
      if (match != null) {
        final s = DateTime.parse(match.group(1)!);
        final e = DateTime.parse(match.group(2)!);
        startInclusive = DateTime(s.year, s.month, s.day);
        endExclusive = DateTime(
          e.year,
          e.month,
          e.day,
        ).add(const Duration(days: 1));
      }
    }
    if (startInclusive == null || endExclusive == null) {
      switch (_selectedTimeRange) {
        case '1 Day':
          startInclusive = now.subtract(const Duration(days: 1));
          endExclusive = now;
          break;
        case 'Last 7 Days':
          startInclusive = now.subtract(const Duration(days: 7));
          endExclusive = now;
          break;
        case 'Last 30 Days':
          startInclusive = now.subtract(const Duration(days: 30));
          endExclusive = now;
          break;
        case 'Last 60 Days':
          startInclusive = now.subtract(const Duration(days: 60));
          endExclusive = now;
          break;
        case 'Last 90 Days':
          startInclusive = now.subtract(const Duration(days: 90));
          endExclusive = now;
          break;
        case 'Last Year':
          startInclusive = DateTime(now.year - 1, now.month, now.day);
          endExclusive = now;
          break;
        default:
          startInclusive = now.subtract(const Duration(days: 7));
          endExclusive = now;
      }
    }

    // Real-time aggregates using reviewedAt window
    int completedInWindow = 0;
    double totalHoursInWindow = 0.0;
    int pendingInWindow = 0;
    int within24 = 0;
    int within48 = 0;
    // removed overduePending aggregation; we compute overdue pending from createdAt-filtered set below
    final Map<String, List<double>> hoursByDay = {};

    for (final r in scanRequests) {
      final status = (r['status'] ?? '').toString();
      final createdAtRaw = r['createdAt'];
      DateTime? createdAt;
      if (createdAtRaw is Timestamp) createdAt = createdAtRaw.toDate();
      if (createdAtRaw is String) createdAt = DateTime.tryParse(createdAtRaw);

      if (status == 'completed') {
        final reviewedAtRaw = r['reviewedAt'];
        DateTime? reviewedAt;
        if (reviewedAtRaw is Timestamp) reviewedAt = reviewedAtRaw.toDate();
        if (reviewedAtRaw is String)
          reviewedAt = DateTime.tryParse(reviewedAtRaw);
        if (createdAt != null && reviewedAt != null) {
          final inWindow =
              _selectedTimeRange == '1 Day'
                  ? reviewedAt.isAfter(startInclusive)
                  : (!reviewedAt.isBefore(startInclusive) &&
                      reviewedAt.isBefore(endExclusive));
          if (inWindow) {
            final hours = reviewedAt.difference(createdAt).inSeconds / 3600.0;
            totalHoursInWindow += hours;
            completedInWindow++;
            if (hours <= 24.0) within24++;
            if (hours <= 48.0) within48++;
            final key =
                '${reviewedAt.year}-${reviewedAt.month.toString().padLeft(2, '0')}-${reviewedAt.day.toString().padLeft(2, '0')}';
            (hoursByDay[key] ??= <double>[]).add(hours);
          }
        }
      } else if (status == 'pending') {
        // Count pending within the selected window using createdAt
        if (createdAt != null) {
          final inPendingWindow =
              _selectedTimeRange == '1 Day'
                  ? createdAt.isAfter(startInclusive)
                  : (!createdAt.isBefore(startInclusive) &&
                      createdAt.isBefore(endExclusive));
          if (inPendingWindow) pendingInWindow++;
          // Do not compute overdue here; computed after filtering by createdAt below
        }
      }
    }

    // Average response time for the card is computed via service; avoid recomputing here

    final List<Map<String, dynamic>> series =
        hoursByDay.entries.map((e) {
            final avg =
                e.value.isEmpty
                    ? 0.0
                    : e.value.reduce((a, b) => a + b) / e.value.length;
            return {'date': e.key, 'avgHours': avg};
          }).toList()
          ..sort(
            (a, b) => (a['date'] as String).compareTo(b['date'] as String),
          );

    // Realtime KPI calculations (reviewedAt-anchored for SLA/avg time)
    final averageResponseTimeStr =
        completedInWindow == 0
            ? '0 hours'
            : '${(totalHoursInWindow / completedInWindow).toStringAsFixed(2)} hours';
    final String sla24Str =
        completedInWindow == 0
            ? '—'
            : '${((within24 / completedInWindow) * 100).toStringAsFixed(0)}%';
    final String sla48Str =
        completedInWindow == 0
            ? '—'
            : '${((within48 / completedInWindow) * 100).toStringAsFixed(0)}%';

    // Align completion rate and overdue pending with modal logic and dataset
    // Use shared helper to match counts exactly
    print(
      '[DEBUG _updateStatsFromSnapshot] About to call getCountsForTimeRange with: $_selectedTimeRange',
    );
    final counts = await ScanRequestsService.getCountsForTimeRange(
      timeRange: _selectedTimeRange,
    );
    print('[DEBUG _updateStatsFromSnapshot] Received counts: $counts');
    final int completedByCreated = counts['completed'] ?? 0;
    final int pendingByCreated = counts['pending'] ?? 0;
    final int totalForCompletion = completedByCreated + pendingByCreated;
    final String completionRateStr =
        totalForCompletion == 0
            ? '—'
            : '${((completedByCreated / totalForCompletion) * 100).toStringAsFixed(0)}%';

    final int overduePendingCreated = counts['overduePending'] ?? 0;

    print(
      '[CARD] range=$_selectedTimeRange completed=$completedByCreated pending=$pendingByCreated overdue=$overduePendingCreated completionRate=$completionRateStr',
    );
    setState(() {
      _stats['totalReportsReviewed'] = completedInWindow;
      _stats['pendingRequests'] = pendingInWindow;
      _avgResponseTrend = series;
      _stats['averageResponseTime'] = averageResponseTimeStr;
      _slaWithin24h = sla24Str;
      _slaWithin48h = sla48Str;
      _completionRate = completionRateStr;
      _overduePendingCount = overduePendingCreated;
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load data in parallel
      await Future.wait([
        _loadStats(),
        _loadReportsTrend(),
        _loadDiseaseStats(),
        _loadAvgResponseTrend(),
        _loadSla(),
      ]);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      // Compute counts based on the selected time range for accuracy
      final all = await ScanRequestsService.getScanRequests();
      final filtered = ScanRequestsService.filterByTimeRange(
        all,
        _selectedTimeRange,
      );
      final completedReports =
          filtered.where((r) => (r['status'] ?? '') == 'completed').length;
      final pendingReports =
          filtered.where((r) => (r['status'] ?? '') == 'pending').length;
      final averageResponseTime =
          await ScanRequestsService.getAverageResponseTime(
            timeRange: _selectedTimeRange,
          );

      setState(() {
        _stats['totalReportsReviewed'] = completedReports;
        _stats['pendingRequests'] = pendingReports;
        _stats['averageResponseTime'] = averageResponseTime;
      });
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  Future<void> _loadReportsTrend() async {
    try {
      final trendData = await ScanRequestsService.getReportsTrend(
        timeRange: _selectedTimeRange,
      );
      print('Loaded reports trend: $trendData');

      // If no data, show a message
      if (trendData.isEmpty) {
        setState(() {
          _reportsTrend = [
            {'date': DateTime.now().toString().split(' ')[0], 'count': 0},
          ];
        });
      } else {
        setState(() {
          _reportsTrend = trendData;
        });
      }
    } catch (e) {
      print('Error loading reports trend: $e');
      // Fallback data
      setState(() {
        _reportsTrend = [
          {'date': DateTime.now().toString().split(' ')[0], 'count': 0},
        ];
      });
    }
  }

  Future<void> _loadDiseaseStats() async {
    try {
      final diseaseData = await ScanRequestsService.getDiseaseStats(
        timeRange: _selectedTimeRange,
      );
      print('Loaded disease stats: $diseaseData');

      // If no data, show a message
      if (diseaseData.isEmpty) {
        setState(() {
          _diseaseStats = [
            {
              'name': 'No Data Available',
              'count': 0,
              'percentage': 0.0,
              'type': 'disease',
            },
          ];
        });
      } else {
        setState(() {
          _diseaseStats = diseaseData;
        });
      }
    } catch (e) {
      print('Error loading disease stats: $e');
      // Fallback data
      setState(() {
        _diseaseStats = [
          {
            'name': 'Error Loading Data',
            'count': 0,
            'percentage': 0.0,
            'type': 'disease',
          },
        ];
      });
    }
  }

  Future<void> _loadAvgResponseTrend() async {
    try {
      final all = await ScanRequestsService.getScanRequests();
      // Determine date window based on selected range (end-exclusive)
      final DateTime now = DateTime.now();
      DateTime? startInclusive;
      DateTime? endExclusive;
      if (_selectedTimeRange.startsWith('Custom (') ||
          _selectedTimeRange.startsWith('Monthly (')) {
        final regex = RegExp(
          r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
        );
        final match = regex.firstMatch(_selectedTimeRange);
        if (match != null) {
          final s = DateTime.parse(match.group(1)!);
          final e = DateTime.parse(match.group(2)!);
          startInclusive = DateTime(s.year, s.month, s.day);
          endExclusive = DateTime(
            e.year,
            e.month,
            e.day,
          ).add(const Duration(days: 1));
        }
      }
      if (startInclusive == null || endExclusive == null) {
        switch (_selectedTimeRange) {
          case '1 Day':
            startInclusive = now.subtract(const Duration(days: 1));
            endExclusive = now;
            break;
          case 'Last 7 Days':
            startInclusive = now.subtract(const Duration(days: 7));
            endExclusive = now;
            break;
          case 'Last 30 Days':
            startInclusive = now.subtract(const Duration(days: 30));
            endExclusive = now;
            break;
          case 'Last 60 Days':
            startInclusive = now.subtract(const Duration(days: 60));
            endExclusive = now;
            break;
          case 'Last 90 Days':
            startInclusive = now.subtract(const Duration(days: 90));
            endExclusive = now;
            break;
          case 'Last Year':
            startInclusive = DateTime(now.year - 1, now.month, now.day);
            endExclusive = now;
            break;
          default:
            startInclusive = now.subtract(const Duration(days: 7));
            endExclusive = now;
        }
      }
      if (_selectedTimeRange == '1 Day') {
        // Build hourly buckets for the last 24 hours (inclusive of current hour)
        final DateTime endHour = DateTime(
          endExclusive.year,
          endExclusive.month,
          endExclusive.day,
          endExclusive.hour,
        );
        final DateTime startHour = endHour.subtract(const Duration(hours: 23));

        // Initialize map for each hour bucket to ensure continuity even with no data
        final Map<DateTime, List<double>> hoursMap = {
          for (int i = 0; i < 24; i++)
            startHour.add(Duration(hours: i)): <double>[],
        };

        // Fill buckets with response durations
        for (final r in all) {
          if ((r['status'] ?? '') != 'completed') continue;
          final createdAt = r['createdAt'];
          final reviewedAt = r['reviewedAt'];
          if (createdAt == null || reviewedAt == null) continue;
          DateTime? created;
          DateTime? reviewed;
          if (createdAt is Timestamp) created = createdAt.toDate();
          if (createdAt is String) created = DateTime.tryParse(createdAt);
          if (reviewedAt is Timestamp) reviewed = reviewedAt.toDate();
          if (reviewedAt is String) reviewed = DateTime.tryParse(reviewedAt);
          if (created == null || reviewed == null) continue;

          // Filter by REVIEW time within the window (end-exclusive)
          if (reviewed.isBefore(startInclusive) ||
              !reviewed.isBefore(endExclusive))
            continue;

          // Determine the hour bucket of review time
          final DateTime hourKey = DateTime(
            reviewed.year,
            reviewed.month,
            reviewed.day,
            reviewed.hour,
          );
          if (!hoursMap.containsKey(hourKey))
            continue; // outside 24-hour window

          final double hours = reviewed.difference(created).inMinutes / 60.0;
          hoursMap[hourKey]!.add(hours);
        }

        // Convert to ordered series with HH:00 labels
        final List<Map<String, dynamic>> seriesAll = [
          for (final entry
              in hoursMap.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)))
            {
              'date': '${entry.key.hour.toString().padLeft(2, '0')}:00',
              'avgHours':
                  entry.value.isEmpty
                      ? 0.0
                      : entry.value.reduce((a, b) => a + b) /
                          entry.value.length,
            },
        ];

        // Trim leading and trailing empty hours so the domain starts at the
        // first completed review and ends at the most recent completed review.
        int firstIdx = seriesAll.indexWhere(
          (e) => ((e['avgHours'] as double?) ?? 0) > 0,
        );
        int lastIdx = seriesAll.lastIndexWhere(
          (e) => ((e['avgHours'] as double?) ?? 0) > 0,
        );

        final List<Map<String, dynamic>> series =
            (firstIdx != -1 && lastIdx >= firstIdx)
                ? seriesAll.sublist(firstIdx, lastIdx + 1)
                : <Map<String, dynamic>>[];

        setState(() {
          _avgResponseTrend = series;
        });
      } else {
        // Default behavior: daily buckets for multi-day ranges
        final Map<String, List<double>> hoursByDay = {};
        for (final r in all) {
          if ((r['status'] ?? '') != 'completed') continue;
          final createdAt = r['createdAt'];
          final reviewedAt = r['reviewedAt'];
          if (createdAt == null || reviewedAt == null) continue;
          DateTime? c;
          DateTime? v;
          if (createdAt is Timestamp) c = createdAt.toDate();
          if (createdAt is String) c = DateTime.tryParse(createdAt);
          if (reviewedAt is Timestamp) v = reviewedAt.toDate();
          if (reviewedAt is String) v = DateTime.tryParse(reviewedAt);
          if (c == null || v == null) continue;
          // Filter by REVIEW date within the selected window (end-exclusive)
          if (v.isBefore(startInclusive) || !v.isBefore(endExclusive)) continue;
          final key =
              '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
          final hours = v.difference(c).inMinutes / 60.0;
          (hoursByDay[key] ??= <double>[]).add(hours);
        }
        final List<Map<String, dynamic>> series =
            hoursByDay.entries.map((e) {
                final avg =
                    e.value.isEmpty
                        ? 0.0
                        : e.value.reduce((a, b) => a + b) / e.value.length;
                return {'date': e.key, 'avgHours': avg};
              }).toList()
              ..sort(
                (a, b) => (a['date'] as String).compareTo(b['date'] as String),
              );
        setState(() {
          _avgResponseTrend = series;
        });
      }
    } catch (e) {
      print('Error loading avg response trend: $e');
      setState(() {
        _avgResponseTrend = [];
      });
    }
  }

  Future<void> _loadSla() async {
    try {
      final all = await ScanRequestsService.getScanRequests();
      // Build reviewedAt-anchored window
      final DateTime now = DateTime.now();
      DateTime? startInclusive;
      DateTime? endExclusive;
      if (_selectedTimeRange.startsWith('Custom (') ||
          _selectedTimeRange.startsWith('Monthly (')) {
        final regex = RegExp(
          r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
        );
        final match = regex.firstMatch(_selectedTimeRange);
        if (match != null) {
          final s = DateTime.parse(match.group(1)!);
          final e = DateTime.parse(match.group(2)!);
          startInclusive = DateTime(s.year, s.month, s.day);
          endExclusive = DateTime(
            e.year,
            e.month,
            e.day,
          ).add(const Duration(days: 1));
        }
      }
      if (startInclusive == null || endExclusive == null) {
        switch (_selectedTimeRange) {
          case '1 Day':
            startInclusive = now.subtract(const Duration(days: 1));
            endExclusive = now;
            break;
          case 'Last 7 Days':
            startInclusive = now.subtract(const Duration(days: 7));
            endExclusive = now;
            break;
          case 'Last 30 Days':
            startInclusive = now.subtract(const Duration(days: 30));
            endExclusive = now;
            break;
          case 'Last 60 Days':
            startInclusive = now.subtract(const Duration(days: 60));
            endExclusive = now;
            break;
          case 'Last 90 Days':
            startInclusive = now.subtract(const Duration(days: 90));
            endExclusive = now;
            break;
          case 'Last Year':
            startInclusive = DateTime(now.year - 1, now.month, now.day);
            endExclusive = now;
            break;
          default:
            startInclusive = now.subtract(const Duration(days: 7));
            endExclusive = now;
        }
      }
      int completed = 0;
      int within24 = 0;
      int within48 = 0;
      for (final r in all) {
        final status = (r['status'] ?? '').toString();
        final createdAt = r['createdAt'];
        DateTime? created;
        if (createdAt is Timestamp) {
          created = createdAt.toDate();
        } else if (createdAt is String) {
          created = DateTime.tryParse(createdAt);
        }
        if (status == 'completed') {
          final reviewedAt = r['reviewedAt'];
          if (created == null || reviewedAt == null) continue;
          DateTime reviewed;
          if (reviewedAt is Timestamp) {
            reviewed = reviewedAt.toDate();
          } else if (reviewedAt is String) {
            reviewed = DateTime.tryParse(reviewedAt) ?? created;
          } else {
            continue;
          }
          // Filter by reviewedAt window
          final bool inWindow;
          if (_selectedTimeRange == '1 Day') {
            inWindow = reviewed.isAfter(startInclusive);
          } else if (_selectedTimeRange.startsWith('Custom (') ||
              _selectedTimeRange.startsWith('Monthly (')) {
            inWindow =
                !reviewed.isBefore(startInclusive) &&
                reviewed.isBefore(endExclusive);
          } else {
            // Use end-exclusive to align with rest of UI calculations
            inWindow =
                !reviewed.isBefore(startInclusive) &&
                reviewed.isBefore(endExclusive);
          }
          if (!inWindow) continue;
          completed++;
          final hours = reviewed.difference(created).inMinutes / 60.0;
          if (hours <= 24.0) within24++;
          if (hours <= 48.0) within48++;
        }
      }
      final slaStr =
          completed == 0
              ? '—'
              : '${((within24 / completed) * 100).toStringAsFixed(0)}%';
      final sla48Str =
          completed == 0
              ? '—'
              : '${((within48 / completed) * 100).toStringAsFixed(0)}%';
      setState(() {
        _slaWithin24h = slaStr;
        _slaWithin48h = sla48Str;
      });
    } catch (e) {
      print('Error loading SLA: $e');
      setState(() {
        _slaWithin24h = '—';
        _slaWithin48h = '—';
        _completionRate = '—';
        _overduePendingCount = 0;
      });
    }
  }

  Future<void> _onTimeRangeChanged(String newTimeRange) async {
    if (newTimeRange == _selectedTimeRange) {
      return;
    }

    // Save the selected time range
    await _saveTimeRange(newTimeRange);

    // Log report time range change
    try {
      final formattedRange = _formatTimeRangeForActivity(newTimeRange);
      await FirebaseFirestore.instance.collection('activities').add({
        'action': 'Report time range changed to $formattedRange',
        'user':
            'Admin', // You can get this from the current admin context if available
        'type': 'report_change',
        'color': Colors.indigo.value,
        'icon': Icons.date_range.codePoint,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Failed to log time range change: $e');
    }

    setState(() {
      _selectedTimeRange = newTimeRange;
    });
    // Immediately update card KPIs to reflect the new range
    try {
      final counts = await ScanRequestsService.getCountsForTimeRange(
        timeRange: newTimeRange,
      );
      final int completedByCreated = counts['completed'] ?? 0;
      final int pendingByCreated = counts['pending'] ?? 0;
      final int totalForCompletion = completedByCreated + pendingByCreated;
      final String completionRateStr =
          totalForCompletion == 0
              ? '—'
              : '${((completedByCreated / totalForCompletion) * 100).toStringAsFixed(0)}%';
      final int overduePendingCreated = counts['overduePending'] ?? 0;
      setState(() {
        _completionRate = completionRateStr;
        _overduePendingCount = overduePendingCreated;
      });
    } catch (_) {}
    // Refresh all dependent data; snapshot updater will compute realtime KPIs
    await Future.wait([
      _loadStats(),
      _loadReportsTrend(),
      _loadDiseaseStats(),
      _loadAvgResponseTrend(),
      _loadSla(),
    ]);
    _updateStatsFromSnapshot();
  }

  // CSV export removed

  // Users CSV export removed per product decision

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Reports',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    // Global time filter
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: DropdownButton<String>(
                        value: _selectedTimeRange,
                        underline: const SizedBox.shrink(),
                        items:
                            (<String>['Last 7 Days', 'Monthly…', 'Custom…']
                                  ..addAll(
                                    _selectedTimeRange.startsWith('Custom (') ||
                                            _selectedTimeRange.startsWith(
                                              'Monthly (',
                                            )
                                        ? <String>[_selectedTimeRange]
                                        : const <String>[],
                                  ))
                                .map(
                                  (range) => DropdownMenuItem(
                                    value: range,
                                    child: Text(
                                      _displayRangeLabel(range),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) async {
                          if (value == null) return;
                          if (value == 'Monthly…') {
                            final now = DateTime.now();
                            final picked = await _showMonthYearPicker(
                              context: context,
                              initialDate: now,
                              firstDate: DateTime(2020),
                              lastDate: now,
                            );
                            if (picked != null) {
                              final firstDay = DateTime(
                                picked.year,
                                picked.month,
                                1,
                              );
                              final lastDay = DateTime(
                                picked.year,
                                picked.month + 1,
                                0,
                              );
                              final start =
                                  '${firstDay.year}-${firstDay.month.toString().padLeft(2, '0')}-${firstDay.day.toString().padLeft(2, '0')}';
                              final end =
                                  '${lastDay.year}-${lastDay.month.toString().padLeft(2, '0')}-${lastDay.day.toString().padLeft(2, '0')}';
                              final label = 'Monthly ($start to $end)';
                              await _onTimeRangeChanged(label);
                            }
                          } else if (value == 'Custom…') {
                            final picked = await pickDateRangeWithSf(
                              context,
                              initial: DateTimeRange(
                                start: DateTime.now().subtract(
                                  const Duration(days: 7),
                                ),
                                end: DateTime.now(),
                              ),
                            );
                            if (picked != null) {
                              final start =
                                  '${picked.start.year}-${picked.start.month.toString().padLeft(2, '0')}-${picked.start.day.toString().padLeft(2, '0')}';
                              final end =
                                  '${picked.end.year}-${picked.end.month.toString().padLeft(2, '0')}-${picked.end.day.toString().padLeft(2, '0')}';
                              final label = 'Custom ($start to $end)';
                              await _onTimeRangeChanged(label);
                            }
                          } else {
                            _onTimeRangeChanged(value);
                          }
                        },
                      ),
                    ),
                    // Removed Utility name editor; prepared-by now uses admin profile name
                    ElevatedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Export PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D7204),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onPressed: () async {
                        final result = await showDialog<Map<String, String>>(
                          context: context,
                          builder: (context) => const GenerateReportDialog(),
                        );
                        if (result != null) {
                          final selectedRange =
                              result['range'] ?? _selectedTimeRange;
                          final pageSize = result['pageSize'] ?? 'A4';
                          try {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder:
                                  (_) => const AlertDialog(
                                    content: SizedBox(
                                      height: 56,
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              'Generating PDF report...',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                            );
                            // Fetch admin profile name for Prepared By
                            String preparedBy = 'Admin';
                            try {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user != null) {
                                final snap =
                                    await FirebaseFirestore.instance
                                        .collection('admins')
                                        .doc(user.uid)
                                        .get();
                                final data = snap.data();
                                if (data != null) {
                                  final dynamic v = data['adminName'];
                                  final String n =
                                      (v == null ? '' : v.toString()).trim();
                                  if (n.isNotEmpty) preparedBy = n;
                                }
                              }
                            } catch (_) {}
                            await ReportPdfService.generateAndShareReport(
                              context: context,
                              timeRange: selectedRange,
                              pageSize: pageSize,
                              backgroundAsset: 'assets/report_template_bg.jpg',
                              preparedBy: preparedBy,
                            );
                            Navigator.of(context, rootNavigator: true).pop();
                            // Log activity: PDF generated
                            try {
                              await FirebaseFirestore.instance
                                  .collection('activities')
                                  .add({
                                    'action': 'Generated PDF report',
                                    'user':
                                        preparedBy.isEmpty
                                            ? 'Admin'
                                            : preparedBy,
                                    'type': 'export',
                                    'color': Colors.purple.value,
                                    'icon': Icons.picture_as_pdf.codePoint,
                                    'timestamp': FieldValue.serverTimestamp(),
                                  });
                            } catch (_) {
                              // ignore logging failures
                            }
                          } catch (e) {
                            Navigator.of(
                              context,
                              rootNavigator: true,
                            ).maybePop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to generate PDF: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stats Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2,
              children: [
                TotalUsersCard(onTap: widget.onGoToUsers),
                TotalReportsReviewedCard(
                  totalReports: _stats['totalReportsReviewed'] ?? 0,
                  reportsTrend: _reportsTrend,
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        final ValueNotifier<bool> fullscreen =
                            ValueNotifier<bool>(false);
                        return ValueListenableBuilder<bool>(
                          valueListenable: fullscreen,
                          builder:
                              (context, isFull, _) => Dialog(
                                insetPadding:
                                    isFull
                                        ? EdgeInsets.zero
                                        : const EdgeInsets.symmetric(
                                          horizontal: 40,
                                          vertical: 40,
                                        ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      isFull
                                          ? BorderRadius.zero
                                          : BorderRadius.circular(16),
                                ),
                                child: Container(
                                  width:
                                      isFull
                                          ? MediaQuery.of(context).size.width
                                          : MediaQuery.of(context).size.width *
                                              0.9,
                                  height:
                                      isFull
                                          ? MediaQuery.of(context).size.height
                                          : MediaQuery.of(context).size.height *
                                              0.8,
                                  padding: const EdgeInsets.all(20),
                                  child: ReportsModalContent(
                                    fullscreenNotifier: fullscreen,
                                  ),
                                ),
                              ),
                        );
                      },
                    );
                  },
                ),
                PendingApprovalsCard(),
                _buildStatCard(
                  'Avg. Response Time',
                  _stats['averageResponseTime'] ?? '0 hours',
                  Icons.timer,
                  Colors.teal,
                  onTap: () => _showAvgResponseTimeModal(context),
                ),
                _buildStatCard(
                  'SLA ≤ 24h',
                  _slaWithin24h ?? '—',
                  Icons.speed,
                  Colors.indigo,
                  onTap: () => _showSlaModal(context),
                ),
                _buildStatCard(
                  'SLA ≤ 48h',
                  _slaWithin48h ?? '—',
                  Icons.speed_outlined,
                  Colors.deepPurple,
                  onTap: () => _showSla48Modal(context),
                ),
                _buildStatCard(
                  'Completion Rate',
                  _completionRate ?? '—',
                  Icons.task_alt,
                  Colors.blueGrey,
                  onTap: () => _showCompletionRateModal(context),
                ),
                _buildStatCard(
                  'Overdue Pending >24h',
                  (_overduePendingCount ?? 0).toString(),
                  Icons.warning_amber,
                  Colors.orange,
                  onTap: () => _showOverduePendingModal(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Charts Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Disease Distribution Chart
                Expanded(
                  child: DiseaseDistributionChart(
                    diseaseStats: _diseaseStats,
                    selectedTimeRange: _selectedTimeRange,
                    onTimeRangeChanged: (String newTimeRange) async {
                      await _onTimeRangeChanged(newTimeRange);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AvgResponseTrendChart(
              trend: _avgResponseTrend,
              selectedTimeRange: _selectedTimeRange,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSlaModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 40,
          ),
          child: Container(
            width: 700,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SLA Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Selected range: ${_displayRangeLabel(_selectedTimeRange)}',
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: ScanRequestsService.getScanRequests(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final all = snapshot.data ?? [];

                    // Build reviewedAt-anchored window for SLA (matches cards)
                    final DateTime now = DateTime.now();
                    DateTime? startInclusive;
                    DateTime? endExclusive;
                    if (_selectedTimeRange.startsWith('Custom (') ||
                        _selectedTimeRange.startsWith('Monthly (')) {
                      final regex = RegExp(
                        r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
                      );
                      final match = regex.firstMatch(_selectedTimeRange);
                      if (match != null) {
                        final s = DateTime.parse(match.group(1)!);
                        final e = DateTime.parse(match.group(2)!);
                        startInclusive = DateTime(s.year, s.month, s.day);
                        endExclusive = DateTime(
                          e.year,
                          e.month,
                          e.day,
                        ).add(const Duration(days: 1));
                      }
                    }
                    if (startInclusive == null || endExclusive == null) {
                      switch (_selectedTimeRange) {
                        case '1 Day':
                          startInclusive = now.subtract(
                            const Duration(days: 1),
                          );
                          endExclusive = now;
                          break;
                        case 'Last 7 Days':
                          startInclusive = now.subtract(
                            const Duration(days: 7),
                          );
                          endExclusive = now;
                          break;
                        case 'Last 30 Days':
                          startInclusive = now.subtract(
                            const Duration(days: 30),
                          );
                          endExclusive = now;
                          break;
                        case 'Last 60 Days':
                          startInclusive = now.subtract(
                            const Duration(days: 60),
                          );
                          endExclusive = now;
                          break;
                        case 'Last 90 Days':
                          startInclusive = now.subtract(
                            const Duration(days: 90),
                          );
                          endExclusive = now;
                          break;
                        case 'Last Year':
                          startInclusive = DateTime(
                            now.year - 1,
                            now.month,
                            now.day,
                          );
                          endExclusive = now;
                          break;
                        default:
                          startInclusive = now.subtract(
                            const Duration(days: 7),
                          );
                          endExclusive = now;
                      }
                    }
                    int completed = 0;
                    int within24 = 0;
                    final buckets = <String, int>{
                      '0-6h': 0,
                      '6-12h': 0,
                      '12-24h': 0,
                      '24-48h': 0,
                      '>48h': 0,
                    };
                    for (final r in all) {
                      if ((r['status'] ?? '') != 'completed') continue;
                      final createdAt = r['createdAt'];
                      final reviewedAt = r['reviewedAt'];
                      if (createdAt == null || reviewedAt == null) continue;
                      DateTime? created;
                      DateTime? reviewed;
                      if (createdAt is Timestamp) created = createdAt.toDate();
                      if (createdAt is String)
                        created = DateTime.tryParse(createdAt);
                      if (reviewedAt is Timestamp)
                        reviewed = reviewedAt.toDate();
                      if (reviewedAt is String)
                        reviewed = DateTime.tryParse(reviewedAt);
                      if (created == null || reviewed == null) continue;
                      final inWindow =
                          !reviewed.isBefore(startInclusive) &&
                          reviewed.isBefore(endExclusive);
                      if (!inWindow) continue;
                      completed++;
                      final hours =
                          reviewed.difference(created).inMinutes / 60.0;
                      if (hours <= 24) within24++;
                      if (hours <= 6)
                        buckets['0-6h'] = buckets['0-6h']! + 1;
                      else if (hours <= 12)
                        buckets['6-12h'] = buckets['6-12h']! + 1;
                      else if (hours <= 24)
                        buckets['12-24h'] = buckets['12-24h']! + 1;
                      else if (hours <= 48)
                        buckets['24-48h'] = buckets['24-48h']! + 1;
                      else
                        buckets['>48h'] = buckets['>48h']! + 1;
                    }
                    final slaText =
                        completed == 0
                            ? '—'
                            : '${((within24 / completed) * 100).toStringAsFixed(0)}% within 24h';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Completed: $completed, $slaText',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children:
                              buckets.entries.map((e) {
                                return Chip(
                                  label: Text('${e.key}: ${e.value}'),
                                );
                              }).toList(),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSla48Modal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 40,
          ),
          child: Container(
            width: 700,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SLA ≤ 48h',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: ScanRequestsService.getScanRequests(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final all = snapshot.data ?? [];

                    // Build reviewedAt-anchored window for SLA 48h (matches cards)
                    final DateTime now = DateTime.now();
                    DateTime? startInclusive;
                    DateTime? endExclusive;
                    if (_selectedTimeRange.startsWith('Custom (') ||
                        _selectedTimeRange.startsWith('Monthly (')) {
                      final regex = RegExp(
                        r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
                      );
                      final match = regex.firstMatch(_selectedTimeRange);
                      if (match != null) {
                        final s = DateTime.parse(match.group(1)!);
                        final e = DateTime.parse(match.group(2)!);
                        startInclusive = DateTime(s.year, s.month, s.day);
                        endExclusive = DateTime(
                          e.year,
                          e.month,
                          e.day,
                        ).add(const Duration(days: 1));
                      }
                    }
                    if (startInclusive == null || endExclusive == null) {
                      switch (_selectedTimeRange) {
                        case '1 Day':
                          startInclusive = now.subtract(
                            const Duration(days: 1),
                          );
                          endExclusive = now;
                          break;
                        case 'Last 7 Days':
                          startInclusive = now.subtract(
                            const Duration(days: 7),
                          );
                          endExclusive = now;
                          break;
                        case 'Last 30 Days':
                          startInclusive = now.subtract(
                            const Duration(days: 30),
                          );
                          endExclusive = now;
                          break;
                        case 'Last 60 Days':
                          startInclusive = now.subtract(
                            const Duration(days: 60),
                          );
                          endExclusive = now;
                          break;
                        case 'Last 90 Days':
                          startInclusive = now.subtract(
                            const Duration(days: 90),
                          );
                          endExclusive = now;
                          break;
                        case 'Last Year':
                          startInclusive = DateTime(
                            now.year - 1,
                            now.month,
                            now.day,
                          );
                          endExclusive = now;
                          break;
                        default:
                          startInclusive = now.subtract(
                            const Duration(days: 7),
                          );
                          endExclusive = now;
                      }
                    }
                    int completed = 0;
                    int within48 = 0;
                    for (final r in all) {
                      if ((r['status'] ?? '') != 'completed') continue;
                      final createdAt = r['createdAt'];
                      final reviewedAt = r['reviewedAt'];
                      if (createdAt == null || reviewedAt == null) continue;
                      DateTime? created;
                      DateTime? reviewed;
                      if (createdAt is Timestamp) created = createdAt.toDate();
                      if (createdAt is String)
                        created = DateTime.tryParse(createdAt);
                      if (reviewedAt is Timestamp)
                        reviewed = reviewedAt.toDate();
                      if (reviewedAt is String)
                        reviewed = DateTime.tryParse(reviewedAt);
                      if (created == null || reviewed == null) continue;
                      final inWindow =
                          !reviewed.isBefore(startInclusive) &&
                          reviewed.isBefore(endExclusive);
                      if (!inWindow) continue;
                      completed++;
                      final hours =
                          reviewed.difference(created).inMinutes / 60.0;
                      if (hours <= 48) within48++;
                    }
                    final text =
                        completed == 0
                            ? '—'
                            : '${((within48 / completed) * 100).toStringAsFixed(0)}% within 48h';
                    return Text(
                      text,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCompletionRateModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 40,
          ),
          child: Container(
            width: 700,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Completion Rate',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: ScanRequestsService.getScanRequests(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final all = snapshot.data ?? [];
                    final filtered = ScanRequestsService.filterByTimeRange(
                      all,
                      _selectedTimeRange,
                    );
                    int completed = 0;
                    int pending = 0;
                    for (final r in filtered) {
                      final status = (r['status'] ?? '').toString();
                      if (status == 'completed') completed++;
                      if (status == 'pending') pending++;
                    }
                    final total = completed + pending;
                    final text =
                        total == 0
                            ? '—'
                            : '${((completed / total) * 100).toStringAsFixed(0)}% completed';
                    return Text(
                      text,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOverduePendingModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 40,
          ),
          child: Container(
            width: 700,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Overdue Pending (>24h)',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: ScanRequestsService.getScanRequests(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final all = snapshot.data ?? [];
                    final filtered = ScanRequestsService.filterByTimeRange(
                      all,
                      _selectedTimeRange,
                    );
                    int overdue = 0;
                    for (final r in filtered) {
                      if ((r['status'] ?? '') == 'pending') {
                        final createdAt = r['createdAt'];
                        DateTime? created;
                        if (createdAt is Timestamp) {
                          created = createdAt.toDate();
                        } else if (createdAt is String) {
                          created = DateTime.tryParse(createdAt);
                        }
                        if (created != null) {
                          final hrs =
                              DateTime.now().difference(created).inMinutes /
                              60.0;
                          if (hrs > 24.0) overdue++;
                        }
                      }
                    }
                    return Text(
                      'Overdue pending: $overdue',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAvgResponseTimeModal(BuildContext context) {
    final scanRequestsProvider = Provider.of<ScanRequestsSnapshot?>(
      context,
      listen: false,
    );
    final snapshot = scanRequestsProvider?.snapshot;
    final scanRequests =
        snapshot != null
            ? snapshot.docs
                .map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'id': doc.id,
                    'status': data['status'] ?? 'pending',
                    'createdAt': data['submittedAt'] ?? data['createdAt'],
                    'reviewedAt': data['reviewedAt'],
                    'expertReview': data['expertReview'],
                    'expertUid': data['expertUid'],
                    'expertId': data['expertId'],
                    'expertName': data['expertName'],
                  };
                })
                .toList()
                .cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
    showDialog(
      context: context,
      builder:
          (context) => AvgResponseTimeModal(
            scanRequests: scanRequests,
            onTimeRangeChanged: (String newTimeRange) {
              _updateAvgResponseTimeForRange(newTimeRange);
            },
          ),
    );
  }

  void _updateAvgResponseTimeForRange(String timeRange) async {
    try {
      final averageResponseTime =
          await ScanRequestsService.getAverageResponseTime(
            timeRange: timeRange,
          );
      setState(() {
        _stats['averageResponseTime'] = averageResponseTime;
      });
    } catch (_) {}
  }

  Future<DateTime?> _showMonthYearPicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    DateTime selectedDate = initialDate;

    return await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Select Month and Year'),
              content: SizedBox(
                width: 300,
                height: 400,
                child: Column(
                  children: [
                    // Year selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios),
                          onPressed:
                              selectedDate.year > firstDate.year
                                  ? () {
                                    setState(() {
                                      selectedDate = DateTime(
                                        selectedDate.year - 1,
                                        selectedDate.month,
                                      );
                                    });
                                  }
                                  : null,
                        ),
                        Text(
                          '${selectedDate.year}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios),
                          onPressed:
                              selectedDate.year < lastDate.year
                                  ? () {
                                    setState(() {
                                      selectedDate = DateTime(
                                        selectedDate.year + 1,
                                        selectedDate.month,
                                      );
                                    });
                                  }
                                  : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Month grid
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 2,
                            ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          final month = index + 1;
                          final isSelected = selectedDate.month == month;
                          final monthDate = DateTime(selectedDate.year, month);
                          final isDisabled =
                              monthDate.isBefore(
                                DateTime(firstDate.year, firstDate.month),
                              ) ||
                              monthDate.isAfter(
                                DateTime(lastDate.year, lastDate.month),
                              );

                          const monthNames = [
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

                          return InkWell(
                            onTap:
                                isDisabled
                                    ? null
                                    : () {
                                      setState(() {
                                        selectedDate = DateTime(
                                          selectedDate.year,
                                          month,
                                        );
                                      });
                                    },
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? const Color(0xFF2D7204)
                                        : isDisabled
                                        ? Colors.grey.shade200
                                        : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      isSelected
                                          ? const Color(0xFF2D7204)
                                          : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                monthNames[index],
                                style: TextStyle(
                                  color:
                                      isDisabled
                                          ? Colors.grey.shade400
                                          : isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selectedDate),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D7204),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class AvgResponseTrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  final String selectedTimeRange;

  const AvgResponseTrendChart({
    Key? key,
    required this.trend,
    required this.selectedTimeRange,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String _monthName(int m) {
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

    String _displayRangeLabel(String range) {
      if (range.startsWith('Monthly (')) {
        final regex = RegExp(
          r'Monthly \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
        );
        final match = regex.firstMatch(range);
        if (match != null) {
          try {
            final s = DateTime.parse(match.group(1)!);
            const months = [
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
            return '${months[s.month - 1]} ${s.year}';
          } catch (_) {}
        }
        return range;
      }
      if (range.startsWith('Custom (')) {
        final regex = RegExp(
          r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
        );
        final match = regex.firstMatch(range);
        if (match != null) {
          try {
            final s = DateTime.parse(match.group(1)!);
            final e = DateTime.parse(match.group(2)!);
            String fmt(DateTime d) =>
                '${_monthName(d.month)} ${d.day}, ${d.year}';
            return '${fmt(s)} to ${fmt(e)}';
          } catch (_) {}
        }
        return range.substring(8, range.length - 1);
      }
      return range;
    }

    final isEmpty = trend.isEmpty;
    final int numPoints = trend.length;
    final double minX = numPoints == 1 ? -0.5 : 0.0;
    final double maxX =
        numPoints == 1
            ? 0.5
            : (numPoints > 0 ? (numPoints - 1).toDouble() : 0.0);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Avg Expert Response (hrs)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _displayRangeLabel(selectedTimeRange),
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isEmpty)
              const SizedBox(
                height: 120,
                child: Center(child: Text('No data for this range.')),
              )
            else
              SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    minX: minX,
                    maxX: maxX,
                    gridData: FlGridData(show: true, drawVerticalLine: false),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        tooltipBgColor: Colors.blueGrey,
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((barSpot) {
                            final index = barSpot.x.toInt();
                            final raw = (trend[index]['date'] as String);
                            String dateLabel;
                            if (selectedTimeRange == '1 Day') {
                              dateLabel = raw; // HH:00
                            } else {
                              final dt = DateTime.tryParse(raw);
                              if (dt != null) {
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
                                dateLabel = '${months[dt.month - 1]} ${dt.day}';
                              } else {
                                dateLabel = raw;
                              }
                            }
                            final valueStr =
                                '${barSpot.y.toStringAsFixed(1)} hrs';
                            return LineTooltipItem(
                              '$valueStr\n$dateLabel',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: _computeYInterval(trend),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          interval:
                              selectedTimeRange == '1 Day'
                                  ? 1
                                  : _computeXInterval(trend),
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= trend.length)
                              return const SizedBox.shrink();
                            final raw = (trend[i]['date'] as String);
                            final label =
                                selectedTimeRange == '1 Day'
                                    ? raw // already in HH:00
                                    : raw.split('-').sublist(1).join('-');
                            return Text(
                              label,
                              style: const TextStyle(fontSize: 10),
                            );
                          },
                        ),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    minY: 0,
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        color: Colors.teal,
                        barWidth: 3,
                        // Show a dot when there is only a single data point so the chart isn't blank
                        dotData: FlDotData(show: numPoints <= 1),
                        spots: [
                          for (int i = 0; i < trend.length; i++)
                            FlSpot(
                              i.toDouble(),
                              (trend[i]['avgHours'] as double).toDouble(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _computeYInterval(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return 1;
    final maxVal = data
        .map((e) => (e['avgHours'] as double))
        .reduce((a, b) => a > b ? a : b);
    if (maxVal <= 4) return 1;
    if (maxVal <= 8) return 2;
    return (maxVal / 4).ceilToDouble();
  }

  double _computeXInterval(List<Map<String, dynamic>> data) {
    final n = data.length;
    if (n <= 1) return 1;
    if (n <= 8) return 1;
    return (n / 8).ceilToDouble();
  }
}

// EditUtilityDialog removed

class TotalReportsCard extends StatelessWidget {
  final int completedCount;
  final int pendingCount;
  final VoidCallback? onRefresh;

  const TotalReportsCard({
    Key? key,
    required this.completedCount,
    required this.pendingCount,
    this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Freeze a snapshot of the current data for this build to avoid
    // inconsistent reads across multiple getters during hover/rebuilds.
    // Note: _currentData is not in scope here; this card does not need it.
    // Remove unused snapshot logic to fix errors.

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header with refresh button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 24), // Spacer to center the content
                const Spacer(),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  tooltip: 'Refresh',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            // Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.assignment_turned_in,
                size: 24,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            // Number
            Text(
              completedCount.toString(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            // Title
            const Text(
              'Total Reports Reviewed',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            // Breakdown row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$completedCount Completed',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$pendingCount Pending Review',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ReportsListTable extends StatefulWidget {
  ReportsListTable({Key? key}) : super(key: key);

  @override
  State<ReportsListTable> createState() => _ReportsListTableState();
}

class _ReportsListTableState extends State<ReportsListTable> {
  String _searchQuery = '';
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ScanRequestsService.getScanRequests();
      setState(() {
        _reports = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredReports {
    if (_searchQuery.isEmpty) return _reports;
    final query = _searchQuery.toLowerCase();
    return _reports.where((report) {
      final user =
          (report['userName'] ?? report['userId'] ?? '')
              .toString()
              .toLowerCase();
      final status = (report['status'] ?? '').toString().toLowerCase();
      String disease = '';
      final ds = report['diseaseSummary'];
      if (ds is List && ds.isNotEmpty) {
        final first = ds.first;
        if (first is Map<String, dynamic>) {
          disease =
              (first['name'] ?? first['label'] ?? first['disease'] ?? '')
                  .toString()
                  .toLowerCase();
        } else {
          disease = first.toString().toLowerCase();
        }
      }
      return user.contains(query) ||
          status.contains(query) ||
          disease.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by user, disease, or status',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        ),
        SizedBox(
          height: 300,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child:
                _loading
                    ? const SizedBox(
                      width: 400,
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    )
                    : _error != null
                    ? SizedBox(
                      width: 400,
                      height: 200,
                      child: Center(child: Text('Failed to load: $_error')),
                    )
                    : DataTable(
                      columns: const [
                        DataColumn(label: Text('Report ID')),
                        DataColumn(label: Text('User')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Disease')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows:
                          _filteredReports.map((report) {
                            return DataRow(
                              cells: [
                                DataCell(Text((report['id'] ?? '').toString())),
                                DataCell(
                                  Text(
                                    (report['userName'] ??
                                            report['userId'] ??
                                            '')
                                        .toString(),
                                  ),
                                ),
                                DataCell(
                                  Text(_formatDate(report['createdAt'])),
                                ),
                                DataCell(Text(_extractDisease(report))),
                                DataCell(
                                  Text((report['status'] ?? '').toString()),
                                ),
                                DataCell(
                                  ElevatedButton(
                                    child: const Text('View'),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder:
                                            (context) => AlertDialog(
                                              title: Text(
                                                'Report Details: ${(report['id'] ?? '').toString()}',
                                              ),
                                              content: SingleChildScrollView(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Report ID: ${(report['id'] ?? '').toString()}',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'User: ${(report['userName'] ?? report['userId'] ?? '').toString()}',
                                                    ),
                                                    Text(
                                                      'Date: ${_formatDate(report['createdAt'])}',
                                                    ),
                                                    Text(
                                                      'Disease: ${_extractDisease(report)}',
                                                    ),
                                                    Text(
                                                      'Status: ${(report['status'] ?? '').toString()}',
                                                    ),
                                                    const SizedBox(height: 16),
                                                    if (report['image'] != null)
                                                      Container(
                                                        height: 180,
                                                        width: 180,
                                                        color: Colors.grey[200],
                                                        child: Image.network(
                                                          report['image']
                                                              .toString(),
                                                          fit: BoxFit.cover,
                                                        ),
                                                      )
                                                    else
                                                      Container(
                                                        height: 180,
                                                        width: 180,
                                                        color: Colors.grey[200],
                                                        child: const Center(
                                                          child: Text(
                                                            'No Image',
                                                          ),
                                                        ),
                                                      ),
                                                    const SizedBox(height: 16),
                                                    Text(
                                                      'Details: ${(report['details'] ?? '-').toString()}',
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'Expert: ${(report['expert'] ?? "-").toString()}',
                                                    ),
                                                    Text(
                                                      'Feedback: ${(report['feedback'] ?? "-").toString()}',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        context,
                                                      ),
                                                  child: const Text('Close'),
                                                ),
                                              ],
                                            ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                    ),
          ),
        ),
      ],
    );
  }

  String _formatDate(dynamic createdAt) {
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (createdAt is String) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      }
      return createdAt;
    }
    return '';
  }

  String _extractDisease(Map<String, dynamic> report) {
    final ds = report['diseaseSummary'];
    if (ds is List && ds.isNotEmpty) {
      final first = ds.first;
      if (first is Map<String, dynamic>) {
        return (first['name'] ?? first['label'] ?? first['disease'] ?? '')
            .toString();
      }
      return first.toString();
    }
    return '-';
  }
}

class DiseaseDistributionChart extends StatefulWidget {
  final List<Map<String, dynamic>> diseaseStats;
  final double? height;
  final Function(String)? onTimeRangeChanged;
  final String selectedTimeRange;
  const DiseaseDistributionChart({
    Key? key,
    required this.diseaseStats,
    this.height,
    this.onTimeRangeChanged,
    required this.selectedTimeRange,
  }) : super(key: key);

  @override
  State<DiseaseDistributionChart> createState() =>
      _DiseaseDistributionChartState();
}

class _DiseaseDistributionChartState extends State<DiseaseDistributionChart> {
  StreamSubscription<QuerySnapshot>? _streamSub;
  QuerySnapshot? _lastSnapshot;
  List<Map<String, dynamic>> _liveAggregated = const [];
  // Removed: we aggregate in build() with a safe fallback to pre-fetched data

  String _monthName(int m) {
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

  String _displayRangeLabel(String range) {
    if (range.startsWith('Monthly (')) {
      final regex = RegExp(
        r'Monthly \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        try {
          final s = DateTime.parse(match.group(1)!);
          const months = [
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
          return '${months[s.month - 1]} ${s.year}';
        } catch (_) {}
      }
      return range;
    }
    if (range.startsWith('Custom (')) {
      final regex = RegExp(
        r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        try {
          final s = DateTime.parse(match.group(1)!);
          final e = DateTime.parse(match.group(2)!);
          String fmt(DateTime d) =>
              '${_monthName(d.month)} ${d.day}, ${d.year}';
          return '${fmt(s)} to ${fmt(e)}';
        } catch (_) {}
      }
      return range.substring(8, range.length - 1);
    }
    return range;
  }

  DateTimeRange _resolveDateRange(String range) {
    final now = DateTime.now();
    if (range.startsWith('Custom (') || range.startsWith('Monthly (')) {
      try {
        final prefixLength =
            range.startsWith('Custom (')
                ? 'Custom ('.length
                : 'Monthly ('.length;
        final inner = range.substring(prefixLength, range.length - 1);
        final parts = inner.split(' to ');
        if (parts.length == 2) {
          final start = DateTime.parse(parts[0]);
          final end = DateTime.parse(parts[1]);
          // Include the whole end day
          return DateTimeRange(
            start: start,
            end: end.add(const Duration(days: 1)),
          );
        }
      } catch (_) {}
    }
    switch (range) {
      case '1 Day':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 1)),
          end: now,
        );
      case 'Last 7 Days':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      case 'Last 30 Days':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
      case 'Last 60 Days':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 60)),
          end: now,
        );
      case 'Last 90 Days':
        return DateTimeRange(
          start: now.subtract(const Duration(days: 90)),
          end: now,
        );
      case 'Last Year':
        return DateTimeRange(
          start: DateTime(now.year - 1, now.month, now.day),
          end: now,
        );
      default:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _streamSub = FirebaseFirestore.instance
        .collection('scan_requests')
        .snapshots()
        .listen((snap) {
          _lastSnapshot = snap;
          final agg = _aggregateFromSnapshot(snap, widget.selectedTimeRange);
          if (mounted) {
            setState(() {
              _liveAggregated = agg;
            });
          }
        });
  }

  @override
  void didUpdateWidget(covariant DiseaseDistributionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTimeRange != widget.selectedTimeRange &&
        _lastSnapshot != null) {
      final agg = _aggregateFromSnapshot(
        _lastSnapshot,
        widget.selectedTimeRange,
      );
      setState(() {
        _liveAggregated = agg;
      });
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _aggregateFromSnapshot(
    QuerySnapshot? snapshot,
    String selectedRange,
  ) {
    if (snapshot == null) return const [];
    final range = _resolveDateRange(selectedRange);
    final DateTime start = range.start;
    final DateTime end = range.end;

    final Map<String, int> diseaseToCount = {};
    int healthyCount = 0;

    for (final doc in snapshot.docs) {
      final Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      // Only include expert-reviewed (completed) and anchor to reviewedAt
      final String status = (data['status'] ?? '').toString();
      if (status != 'completed') continue;
      final dynamic reviewedAtRaw = data['reviewedAt'];
      DateTime? reviewed;
      if (reviewedAtRaw is Timestamp) {
        reviewed = reviewedAtRaw.toDate();
      } else if (reviewedAtRaw is String) {
        reviewed = DateTime.tryParse(reviewedAtRaw);
      }
      if (reviewed == null) continue;
      if (reviewed.isBefore(start) || !reviewed.isBefore(end)) continue;

      final List<dynamic> diseaseSummary =
          (data['diseaseSummary'] as List<dynamic>?) ?? const [];
      if (diseaseSummary.isEmpty) {
        healthyCount += 1;
        continue;
      }

      for (final d in diseaseSummary) {
        if (d is Map<String, dynamic>) {
          final String rawName =
              (d['name'] ?? d['label'] ?? d['disease'] ?? 'Unknown').toString();
          final String normalized =
              rawName.replaceAll(RegExp(r'[_\-]+'), ' ').trim().toLowerCase();
          final dynamic countRaw = d['count'] ?? d['confidence'] ?? 1;
          int countVal;
          if (countRaw is num) {
            countVal = countRaw.round();
          } else {
            final parsed = int.tryParse(countRaw.toString());
            countVal = parsed == null ? 1 : parsed;
          }
          // Route Healthy to dedicated panel, do not include in disease bars
          if (normalized == 'healthy') {
            healthyCount += countVal;
            continue;
          }
          // Do not display Unknown/Tip Burn in disease bars
          if (normalized == 'unknown' ||
              normalized == 'tip burn' ||
              normalized == 'tipburn') {
            continue;
          }
          diseaseToCount[rawName] = (diseaseToCount[rawName] ?? 0) + countVal;
        }
      }
    }

    final int total = diseaseToCount.values.fold(healthyCount, (a, b) => a + b);
    final List<Map<String, dynamic>> result = [];

    diseaseToCount.forEach((name, count) {
      result.add({
        'name': name,
        'count': count,
        'percentage': total == 0 ? 0.0 : count / total,
        'type': 'disease',
      });
    });
    if (healthyCount > 0) {
      result.add({
        'name': 'Healthy',
        'count': healthyCount,
        'percentage': total == 0 ? 0.0 : healthyCount / total,
        'type': 'healthy',
      });
    }
    return result;
  }

  // Removed old getters; we snapshot build-scoped lists instead to avoid hover flicker

  Color _getDiseaseColor(String disease) {
    // Normalize common separators and whitespace
    final normalized =
        disease
            .toLowerCase()
            .replaceAll(RegExp(r'[_\-]+'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    switch (normalized) {
      case 'anthracnose':
        return Colors.orange;
      case 'bacterial blackspot':
      case 'bacterial black spot':
        return Colors.purple;
      case 'powdery mildew':
        return const Color.fromARGB(255, 9, 46, 2);
      case 'dieback':
        return Colors.red;
      case 'tip burn':
      case 'tip_burn':
      case 'unknown':
        return Colors.amber;
      case 'healthy':
        return const Color.fromARGB(255, 2, 119, 252);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build-scoped immutable lists using live data when available
    final List<Map<String, dynamic>> dataSnapshot =
        _liveAggregated.isNotEmpty ? _liveAggregated : widget.diseaseStats;
    final List<Map<String, dynamic>> diseaseData =
        dataSnapshot.where((item) => item['type'] == 'disease').toList();
    final List<Map<String, dynamic>> healthyData =
        dataSnapshot.where((item) => item['type'] == 'healthy').toList();
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Distribution',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _displayRangeLabel(widget.selectedTimeRange),
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Disease Distribution Chart
            Container(
              height: widget.height ?? 400,
              width: double.infinity,
              child: Row(
                children: [
                  // Diseases Chart
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.warning_rounded,
                                      size: 16,
                                      color: Colors.red[700],
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Diseases',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Total: ${diseaseData.isEmpty ? 0 : diseaseData.fold<int>(0, (sum, item) => sum + (item['count'] as int))} cases',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Expanded(
                            child:
                                diseaseData.isEmpty
                                    ? const Center(
                                      child: Text(
                                        'No disease data available',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                    : BarChart(
                                      BarChartData(
                                        alignment:
                                            BarChartAlignment.spaceAround,
                                        maxY:
                                            diseaseData.isEmpty
                                                ? 100.0
                                                : diseaseData
                                                        .map(
                                                          (d) =>
                                                              d['count']
                                                                  .toDouble(),
                                                        )
                                                        .reduce(
                                                          (a, b) =>
                                                              a > b ? a : b,
                                                        ) *
                                                    1.2,
                                        barTouchData: BarTouchData(
                                          enabled: true,
                                          touchTooltipData: BarTouchTooltipData(
                                            tooltipBgColor: Colors.blueGrey,
                                            getTooltipItem: (
                                              group,
                                              groupIndex,
                                              rod,
                                              rodIndex,
                                            ) {
                                              if (groupIndex < 0 ||
                                                  groupIndex >=
                                                      diseaseData.length ||
                                                  diseaseData.isEmpty) {
                                                return null;
                                              }
                                              final disease =
                                                  diseaseData[groupIndex];
                                              return BarTooltipItem(
                                                '${disease['name']}\n${disease['count']} cases\n${(disease['percentage'] * 100).toStringAsFixed(1)}%',
                                                const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        titlesData: FlTitlesData(
                                          show: true,
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (value, meta) {
                                                if (value < 0 ||
                                                    value >=
                                                        diseaseData.length ||
                                                    diseaseData.isEmpty) {
                                                  return const SizedBox.shrink();
                                                }
                                                final disease =
                                                    diseaseData[value.toInt()];
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8.0,
                                                      ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        disease['name'],
                                                        style: TextStyle(
                                                          color:
                                                              _getDiseaseColor(
                                                                disease['name'],
                                                              ),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              _getDiseaseColor(
                                                                disease['name'],
                                                              ).withOpacity(
                                                                0.1,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          '${(disease['percentage'] * 100).toStringAsFixed(1)}%',
                                                          style: TextStyle(
                                                            color:
                                                                _getDiseaseColor(
                                                                  disease['name'],
                                                                ),
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                              reservedSize: 72,
                                            ),
                                          ),
                                          leftTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 40,
                                              interval:
                                                  (() {
                                                    // Use the same maxY calculation as the chart
                                                    final double chartMaxY =
                                                        diseaseData.isEmpty
                                                            ? 100.0
                                                            : diseaseData
                                                                    .map(
                                                                      (d) =>
                                                                          (d['count']
                                                                                  as num)
                                                                              .toDouble(),
                                                                    )
                                                                    .reduce(
                                                                      (a, b) =>
                                                                          a > b
                                                                              ? a
                                                                              : b,
                                                                    ) *
                                                                1.2;

                                                    // Calculate interval based on chart's actual maxY
                                                    if (chartMaxY <= 12)
                                                      return 2.0;
                                                    if (chartMaxY <= 24)
                                                      return 5.0;
                                                    if (chartMaxY <= 60)
                                                      return 10.0;
                                                    if (chartMaxY <= 120)
                                                      return 25.0;
                                                    if (chartMaxY <= 240)
                                                      return 50.0;
                                                    if (chartMaxY <= 600)
                                                      return 100.0;
                                                    if (chartMaxY <= 1200)
                                                      return 200.0;
                                                    if (chartMaxY <= 2400)
                                                      return 500.0;
                                                    if (chartMaxY <= 6000)
                                                      return 1000.0;
                                                    if (chartMaxY <= 12000)
                                                      return 2000.0;
                                                    if (chartMaxY <= 24000)
                                                      return 5000.0;
                                                    if (chartMaxY <= 60000)
                                                      return 10000.0;
                                                    // For extremely large numbers, use dynamic calculation
                                                    return (chartMaxY / 5)
                                                        .ceilToDouble();
                                                  })(),
                                              getTitlesWidget: (value, meta) {
                                                return Text(
                                                  value.toInt().toString(),
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 12,
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          topTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                          rightTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                        ),
                                        borderData: FlBorderData(show: false),
                                        gridData: FlGridData(
                                          show: true,
                                          drawVerticalLine: false,
                                          horizontalInterval:
                                              (() {
                                                final double maxVal =
                                                    diseaseData.isEmpty
                                                        ? 100
                                                        : diseaseData
                                                            .map(
                                                              (d) =>
                                                                  (d['count']
                                                                          as num)
                                                                      .toDouble(),
                                                            )
                                                            .reduce(
                                                              (a, b) =>
                                                                  a > b ? a : b,
                                                            );
                                                if (maxVal <= 10) return 2.0;
                                                if (maxVal <= 20) return 5.0;
                                                if (maxVal <= 50) return 10.0;
                                                return 20.0;
                                              })(),
                                          getDrawingHorizontalLine: (value) {
                                            return FlLine(
                                              color: Colors.grey[200],
                                              strokeWidth: 1,
                                            );
                                          },
                                        ),
                                        barGroups:
                                            diseaseData.isEmpty
                                                ? []
                                                : diseaseData.asMap().entries.map((
                                                  entry,
                                                ) {
                                                  final index = entry.key;
                                                  final disease = entry.value;
                                                  return BarChartGroupData(
                                                    x: index,
                                                    barRods: [
                                                      BarChartRodData(
                                                        toY:
                                                            disease['count']
                                                                .toDouble(),
                                                        color: _getDiseaseColor(
                                                          disease['name'],
                                                        ),
                                                        width: 36,
                                                        borderRadius:
                                                            const BorderRadius.vertical(
                                                              top:
                                                                  Radius.circular(
                                                                    8,
                                                                  ),
                                                            ),
                                                      ),
                                                    ],
                                                  );
                                                }).toList(),
                                      ),
                                      swapAnimationDuration: Duration(
                                        milliseconds: 0,
                                      ),
                                      swapAnimationCurve: Curves.linear,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Healthy Plants Chart
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 16,
                                      color: Colors.green[700],
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Healthy',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Total: ${healthyData.isEmpty ? 0 : healthyData.fold<int>(0, (sum, item) => sum + (item['count'] as int))} cases',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Expanded(
                            child:
                                healthyData.isEmpty
                                    ? const Center(
                                      child: Text(
                                        'No healthy data available',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                    : BarChart(
                                      BarChartData(
                                        alignment:
                                            BarChartAlignment.spaceAround,
                                        maxY:
                                            healthyData.isEmpty
                                                ? 100.0
                                                : healthyData
                                                        .map(
                                                          (d) =>
                                                              d['count']
                                                                  .toDouble(),
                                                        )
                                                        .reduce(
                                                          (a, b) =>
                                                              a > b ? a : b,
                                                        ) *
                                                    1.2,
                                        barTouchData: BarTouchData(
                                          enabled: true,
                                          touchTooltipData: BarTouchTooltipData(
                                            tooltipBgColor: Colors.blueGrey,
                                            getTooltipItem: (
                                              group,
                                              groupIndex,
                                              rod,
                                              rodIndex,
                                            ) {
                                              if (groupIndex < 0 ||
                                                  groupIndex >=
                                                      healthyData.length ||
                                                  healthyData.isEmpty) {
                                                return null;
                                              }
                                              final disease =
                                                  healthyData[groupIndex];
                                              return BarTooltipItem(
                                                '${disease['name']}\n${disease['count']} cases\n${(disease['percentage'] * 100).toStringAsFixed(1)}%',
                                                const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        titlesData: FlTitlesData(
                                          show: true,
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              getTitlesWidget: (value, meta) {
                                                if (value < 0 ||
                                                    value >=
                                                        healthyData.length ||
                                                    healthyData.isEmpty) {
                                                  return const SizedBox.shrink();
                                                }
                                                final disease =
                                                    healthyData[value.toInt()];
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8.0,
                                                      ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        disease['name'],
                                                        style: TextStyle(
                                                          color:
                                                              _getDiseaseColor(
                                                                disease['name'],
                                                              ),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              _getDiseaseColor(
                                                                disease['name'],
                                                              ).withOpacity(
                                                                0.1,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          '${(disease['percentage'] * 100).toStringAsFixed(1)}%',
                                                          style: TextStyle(
                                                            color:
                                                                _getDiseaseColor(
                                                                  disease['name'],
                                                                ),
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                              reservedSize: 72,
                                            ),
                                          ),
                                          leftTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 40,
                                              interval:
                                                  (() {
                                                    // Use the same maxY calculation as the chart
                                                    final double chartMaxY =
                                                        healthyData.isEmpty
                                                            ? 100.0
                                                            : healthyData
                                                                    .map(
                                                                      (d) =>
                                                                          (d['count']
                                                                                  as num)
                                                                              .toDouble(),
                                                                    )
                                                                    .reduce(
                                                                      (a, b) =>
                                                                          a > b
                                                                              ? a
                                                                              : b,
                                                                    ) *
                                                                1.2;

                                                    // Calculate interval based on chart's actual maxY
                                                    if (chartMaxY <= 12)
                                                      return 2.0;
                                                    if (chartMaxY <= 24)
                                                      return 5.0;
                                                    if (chartMaxY <= 60)
                                                      return 10.0;
                                                    if (chartMaxY <= 120)
                                                      return 25.0;
                                                    if (chartMaxY <= 240)
                                                      return 50.0;
                                                    if (chartMaxY <= 600)
                                                      return 100.0;
                                                    if (chartMaxY <= 1200)
                                                      return 200.0;
                                                    if (chartMaxY <= 2400)
                                                      return 500.0;
                                                    if (chartMaxY <= 6000)
                                                      return 1000.0;
                                                    if (chartMaxY <= 12000)
                                                      return 2000.0;
                                                    if (chartMaxY <= 24000)
                                                      return 5000.0;
                                                    if (chartMaxY <= 60000)
                                                      return 10000.0;
                                                    // For extremely large numbers, use dynamic calculation
                                                    return (chartMaxY / 5)
                                                        .ceilToDouble();
                                                  })(),
                                              getTitlesWidget: (value, meta) {
                                                return Text(
                                                  value.toInt().toString(),
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 12,
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          topTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                          rightTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                        ),
                                        borderData: FlBorderData(show: false),
                                        gridData: FlGridData(
                                          show: true,
                                          drawVerticalLine: false,
                                          horizontalInterval:
                                              (() {
                                                final double maxVal =
                                                    healthyData.isEmpty
                                                        ? 100
                                                        : healthyData
                                                            .map(
                                                              (d) =>
                                                                  (d['count']
                                                                          as num)
                                                                      .toDouble(),
                                                            )
                                                            .reduce(
                                                              (a, b) =>
                                                                  a > b ? a : b,
                                                            );
                                                if (maxVal <= 10) return 2.0;
                                                if (maxVal <= 20) return 5.0;
                                                if (maxVal <= 50) return 10.0;
                                                return 20.0;
                                              })(),
                                          getDrawingHorizontalLine: (value) {
                                            return FlLine(
                                              color: Colors.grey[200],
                                              strokeWidth: 1,
                                            );
                                          },
                                        ),
                                        barGroups:
                                            healthyData.isEmpty
                                                ? []
                                                : healthyData.asMap().entries.map((
                                                  entry,
                                                ) {
                                                  final index = entry.key;
                                                  final disease = entry.value;
                                                  return BarChartGroupData(
                                                    x: index,
                                                    barRods: [
                                                      BarChartRodData(
                                                        toY:
                                                            disease['count']
                                                                .toDouble(),
                                                        color: _getDiseaseColor(
                                                          disease['name'],
                                                        ),
                                                        width: 36,
                                                        borderRadius:
                                                            const BorderRadius.vertical(
                                                              top:
                                                                  Radius.circular(
                                                                    8,
                                                                  ),
                                                            ),
                                                      ),
                                                    ],
                                                  );
                                                }).toList(),
                                      ),
                                      swapAnimationDuration: Duration(
                                        milliseconds: 0,
                                      ),
                                      swapAnimationCurve: Curves.linear,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Trend feedback removed per request
}

class ReportsTrendDialog extends StatefulWidget {
  @override
  State<ReportsTrendDialog> createState() => _ReportsTrendDialogState();
}

class _ReportsTrendDialogState extends State<ReportsTrendDialog> {
  String _selectedTimeRange = 'Last 7 Days';
  List<Map<String, dynamic>> _trendData = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrend();
  }

  Future<void> _loadTrend() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ScanRequestsService.getReportsTrend(
        timeRange: _selectedTimeRange,
      );
      setState(() {
        _trendData = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _aggregatedData {
    // For large ranges, aggregate by week
    if (_selectedTimeRange == 'Last 30 Days' ||
        _selectedTimeRange == 'Last 60 Days' ||
        _selectedTimeRange == 'Last 90 Days') {
      final data = _trendData;
      final int daysPerBar = 7;
      List<Map<String, dynamic>> result = [];
      for (int i = 0; i < data.length; i += daysPerBar) {
        int sum = 0;
        for (int j = i; j < i + daysPerBar && j < data.length; j++) {
          sum += data[j]['count'] as int;
        }
        result.add({'date': data[i]['date'], 'count': sum});
      }
      return result;
    }
    return _trendData;
  }

  @override
  Widget build(BuildContext context) {
    final isManyBars = _aggregatedData.length > 10;
    final chartWidth =
        isManyBars ? (_aggregatedData.length * 60.0) : double.infinity;
    final int totalReports = _aggregatedData.fold<int>(
      0,
      (sum, item) => sum + (item['count'] as int),
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Container(
        width: 800,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Reports',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.list),
                      label: const Text('User activity'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder:
                              (context) => Dialog(
                                insetPadding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                  vertical: 40,
                                ),
                                child: Container(
                                  width: 900,
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'User activity',
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close),
                                            onPressed:
                                                () => Navigator.pop(context),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        height: 400,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: ReportsListTable(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _selectedTimeRange,
                      items:
                          ['Last 7 Days', 'Custom…']
                              .map(
                                (range) => DropdownMenuItem(
                                  value: range,
                                  child: Text(range),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedTimeRange = value;
                            _loadTrend();
                          });
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Total Reports: $totalReports',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(child: Text('Failed to load: $_error'))
            else if (_aggregatedData.isEmpty)
              const Center(child: Text('No data available for this range.'))
            else
              SizedBox(
                height: 400,
                child:
                    isManyBars
                        ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: chartWidth,
                            child: _buildBarChart(
                              key: ValueKey(_selectedTimeRange),
                            ),
                          ),
                        )
                        : _buildBarChart(key: ValueKey(_selectedTimeRange)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart({Key? key}) {
    // Debug print to trace data
    print(
      'DEBUG: _selectedTimeRange=$_selectedTimeRange, _aggregatedData.length=${_aggregatedData.length}',
    );
    for (var i = 0; i < _aggregatedData.length; i++) {
      print('DEBUG: _aggregatedData[$i]=${_aggregatedData[i]}');
    }
    // Data validation
    if (_selectedTimeRange == 'Last Year' && _aggregatedData.length != 12) {
      return const Center(
        child: Text('Data error: Expected 12 months of data.'),
      );
    }
    if (_aggregatedData.isEmpty ||
        _aggregatedData.any((d) => d['date'] == null || d['count'] == null)) {
      return const Center(child: Text('Data error: Invalid or missing data.'));
    }
    return BarChart(
      key: key,
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY:
            _aggregatedData
                .map((d) => d['count'] as int)
                .reduce((a, b) => a > b ? a : b) *
            1.2,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.blueGrey,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= _aggregatedData.length) {
                return null;
              }
              final report = _aggregatedData[groupIndex];
              String label = _barLabel(groupIndex, report['date']);
              return BarTooltipItem(
                '$label\n${report['count']} reports',
                const TextStyle(color: Colors.white),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                if (value < 0 || value >= _aggregatedData.length) {
                  return const SizedBox.shrink();
                }
                final date = _aggregatedData[value.toInt()]['date'];
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _barLabel(value.toInt(), date),
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value % 20 == 0) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups:
            _aggregatedData.asMap().entries.map((entry) {
              final index = entry.key;
              final report = entry.value;
              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: (report['count'] as int).toDouble(),
                    color: Colors.purple,
                    width: 28,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    rodStackItems: [],
                  ),
                ],
              );
            }).toList(),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        extraLinesData: ExtraLinesData(),
        groupsSpace: 12,
      ),
    );
  }

  String _barLabel(int index, String date) {
    if (_selectedTimeRange == 'Last Year') {
      final parts = date.split('-');
      int monthNum = 1;
      if (parts.length > 1) {
        monthNum = int.tryParse(parts[1]) ?? 1;
      }
      const months = [
        '',
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
      if (monthNum < 1 || monthNum > 12) {
        return '?';
      }
      return months[monthNum];
    } else if (_selectedTimeRange == 'Last 30 Days' ||
        _selectedTimeRange == 'Last 60 Days' ||
        _selectedTimeRange == 'Last 90 Days') {
      return 'Wk ${index + 1}';
    } else {
      final parts = date.split('-');
      return parts.length > 2 ? '${parts[1]}/${parts[2]}' : date;
    }
  }
}

class AvgResponseTimeModal extends StatefulWidget {
  final List<Map<String, dynamic>> scanRequests;
  final Function(String)? onTimeRangeChanged;
  const AvgResponseTimeModal({
    Key? key,
    required this.scanRequests,
    this.onTimeRangeChanged,
  }) : super(key: key);

  @override
  State<AvgResponseTimeModal> createState() => _AvgResponseTimeModalState();
}

class _AvgResponseTimeModalState extends State<AvgResponseTimeModal> {
  String _selectedRange = 'Last 7 Days';
  bool _loading = true;
  List<_ExpertResponseStats> _expertStats = [];
  int _totalCompletedReports = 0;
  double _weightedAverageHours = 0.0;

  String _monthName(int m) {
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

  String _displayRangeLabel(String range) {
    if (range.startsWith('Monthly (')) {
      final regex = RegExp(
        r'Monthly \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        try {
          final s = DateTime.parse(match.group(1)!);
          const months = [
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
          return '${months[s.month - 1]} ${s.year}';
        } catch (_) {}
      }
      return range;
    }
    if (range.startsWith('Custom (')) {
      final regex = RegExp(
        r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        try {
          final s = DateTime.parse(match.group(1)!);
          final e = DateTime.parse(match.group(2)!);
          String fmt(DateTime d) =>
              '${_monthName(d.month)} ${d.day}, ${d.year}';
          return '${fmt(s)} to ${fmt(e)}';
        } catch (_) {}
      }
      // Fallback: strip the wrapper if parsing fails
      return range.substring(8, range.length - 1);
    }
    return range;
  }

  @override
  void initState() {
    super.initState();
    print('[DEBUG] AvgResponseTimeModal initState called');
    _loadExpertStats();
  }

  Future<void> _loadExpertStats() async {
    setState(() {
      _loading = true;
    });
    final scanRequests = widget.scanRequests;
    // Build reviewedAt-anchored window
    final DateTime now = DateTime.now();
    DateTime? startInclusive;
    DateTime? endExclusive;
    if (_selectedRange.startsWith('Custom (') ||
        _selectedRange.startsWith('Monthly (')) {
      final regex = RegExp(
        r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(_selectedRange);
      if (match != null) {
        final s = DateTime.parse(match.group(1)!);
        final e = DateTime.parse(match.group(2)!);
        startInclusive = DateTime(s.year, s.month, s.day);
        endExclusive = DateTime(
          e.year,
          e.month,
          e.day,
        ).add(const Duration(days: 1));
      }
    }
    if (startInclusive == null || endExclusive == null) {
      switch (_selectedRange) {
        case '1 Day':
          startInclusive = now.subtract(const Duration(days: 1));
          endExclusive = now;
          break;
        case 'Last 7 Days':
          startInclusive = now.subtract(const Duration(days: 7));
          endExclusive = now;
          break;
        case 'Last 30 Days':
          startInclusive = now.subtract(const Duration(days: 30));
          endExclusive = now;
          break;
        case 'Last 60 Days':
          startInclusive = now.subtract(const Duration(days: 60));
          endExclusive = now;
          break;
        case 'Last 90 Days':
          startInclusive = now.subtract(const Duration(days: 90));
          endExclusive = now;
          break;
        case 'Last Year':
          startInclusive = DateTime(now.year - 1, now.month, now.day);
          endExclusive = now;
          break;
        default:
          startInclusive = now.subtract(const Duration(days: 7));
          endExclusive = now;
      }
    }
    final Map<String, List<Map<String, dynamic>>> expertGroups = {};
    for (final req in scanRequests) {
      if ((req['status'] ?? '') != 'completed') continue;
      final expertId =
          req['expertReview']?['expertId'] ??
          req['expertUid'] ??
          req['expertId'];
      if (expertId == null) continue;
      final createdRaw = req['createdAt'];
      final reviewedRaw = req['reviewedAt'];
      if (createdRaw == null || reviewedRaw == null) continue;
      DateTime created;
      DateTime reviewed;
      if (createdRaw is Timestamp) {
        created = createdRaw.toDate();
      } else if (createdRaw is String) {
        created = DateTime.tryParse(createdRaw) ?? DateTime.now();
      } else {
        continue;
      }
      if (reviewedRaw is Timestamp) {
        reviewed = reviewedRaw.toDate();
      } else if (reviewedRaw is String) {
        reviewed = DateTime.tryParse(reviewedRaw) ?? created;
      } else {
        continue;
      }
      // Filter by reviewedAt window
      bool inWindow;
      if (_selectedRange == '1 Day') {
        inWindow = reviewed.isAfter(startInclusive);
      } else if (_selectedRange.startsWith('Custom (') ||
          _selectedRange.startsWith('Monthly (')) {
        inWindow =
            !reviewed.isBefore(startInclusive) &&
            reviewed.isBefore(endExclusive);
      } else {
        inWindow =
            !reviewed.isBefore(startInclusive) &&
            !reviewed.isAfter(endExclusive);
      }
      if (!inWindow) continue;
      expertGroups.putIfAbsent(expertId, () => []).add(req);
    }
    print('[DEBUG] expertGroups keys: \'${expertGroups.keys.toList()}\'');
    final Map<String, Map<String, dynamic>> experts = {};
    final List<_ExpertResponseStats> stats = [];
    int grandTotalSeconds = 0;
    int grandCompletedCount = 0;
    for (final entry in expertGroups.entries) {
      final expertId = entry.key;
      final requests = entry.value;
      final times = <double>[];
      int totalSeconds = 0;
      for (final req in requests) {
        DateTime createdAt, reviewedAt;
        if (req['createdAt'] is Timestamp) {
          createdAt = req['createdAt'].toDate();
        } else if (req['createdAt'] is String) {
          createdAt = DateTime.tryParse(req['createdAt']) ?? DateTime.now();
        } else {
          createdAt = DateTime.now();
        }
        if (req['reviewedAt'] is Timestamp) {
          reviewedAt = req['reviewedAt'].toDate();
        } else {
          reviewedAt = DateTime.tryParse(req['reviewedAt']) ?? DateTime.now();
        }
        final diff = reviewedAt.difference(createdAt);
        final seconds = diff.inSeconds;
        totalSeconds += seconds;
        times.add(seconds.toDouble());
      }
      final avgSeconds = requests.isEmpty ? 0 : totalSeconds ~/ requests.length;
      grandTotalSeconds += totalSeconds;
      grandCompletedCount += requests.length;
      final expert = experts[expertId];
      final firstReq = requests.isNotEmpty ? requests.first : null;
      stats.add(
        _ExpertResponseStats(
          expertId: expertId,
          name:
              expert?['fullName'] ??
              (firstReq?['expertReview']?['expertName'] ??
                  firstReq?['expertName'] ??
                  'Unknown'),
          avatar: expert?['imageProfile'] ?? '',
          avgSeconds: avgSeconds,
          trend: times,
          count: requests.length,
        ),
      );
    }
    print('[DEBUG] _expertStats to display:');
    for (final s in stats) {
      print(
        '  expertId: \'${s.expertId}\', name: \'${s.name}\', avgSeconds: ${s.avgSeconds}, trend: ${s.trend}',
      );
    }
    stats.sort((a, b) => a.avgSeconds.compareTo(b.avgSeconds));
    setState(() {
      _expertStats = stats;
      _loading = false;
      _totalCompletedReports = grandCompletedCount;
      _weightedAverageHours =
          grandCompletedCount == 0
              ? 0.0
              : (grandTotalSeconds / grandCompletedCount) / 3600.0;
    });
  }

  String _formatDuration(int seconds) {
    final hr = seconds ~/ 3600;
    final min = (seconds % 3600) ~/ 60;
    final sec = seconds % 60;
    if (hr > 0) {
      return '${hr} hr ${min.toString().padLeft(2, '0')} min ${sec.toString().padLeft(2, '0')} sec';
    } else if (min > 0) {
      return '${min} min ${sec.toString().padLeft(2, '0')} sec';
    } else {
      return '${sec} sec';
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
      '[DEBUG] AvgResponseTimeModal build called with _selectedRange: $_selectedRange',
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 750,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Average Response Time (per Expert)',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 260,
                      child: DropdownButton<String>(
                        value: _selectedRange,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: () {
                          final base = <String>['Last 7 Days', 'Custom…'];
                          // Ensure the concrete Custom (YYYY-MM-DD to YYYY-MM-DD) is present as an item
                          if (_selectedRange.startsWith('Custom (') &&
                              !base.contains(_selectedRange)) {
                            base.add(_selectedRange);
                          }
                          return base.map((range) {
                            final label = _displayRangeLabel(range);
                            return DropdownMenuItem(
                              value: range,
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList();
                        }(),
                        selectedItemBuilder: (context) {
                          final base = <String>['Last 7 Days', 'Custom…'];
                          if (_selectedRange.startsWith('Custom (') &&
                              !base.contains(_selectedRange)) {
                            base.add(_selectedRange);
                          }
                          return base.map((range) {
                            final label = _displayRangeLabel(range);
                            return Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList();
                        },
                        onChanged: (value) async {
                          print('=== DROPDOWN ONCHANGED CALLED ===');
                          print('Dropdown onChanged called with value: $value');
                          if (value == null) return;
                          if (value == 'Custom…') {
                            final picked = await pickDateRangeWithSf(
                              context,
                              initial: DateTimeRange(
                                start: DateTime.now().subtract(
                                  const Duration(days: 7),
                                ),
                                end: DateTime.now(),
                              ),
                            );
                            if (picked != null) {
                              final start =
                                  '${picked.start.year}-${picked.start.month.toString().padLeft(2, '0')}-${picked.start.day.toString().padLeft(2, '0')}';
                              final end =
                                  '${picked.end.year}-${picked.end.month.toString().padLeft(2, '0')}-${picked.end.day.toString().padLeft(2, '0')}';
                              final label = 'Custom ($start to $end)';
                              setState(() => _selectedRange = label);
                              widget.onTimeRangeChanged?.call(label);
                              _loadExpertStats();
                            }
                          } else {
                            print('=== MODAL DROPDOWN DEBUG ===');
                            print('Modal dropdown changed to: $value');
                            setState(() {
                              _selectedRange = value;
                            });
                            print('Calling onTimeRangeChanged callback...');
                            widget.onTimeRangeChanged?.call(value);
                            print(
                              'Callback called, now loading expert stats...',
                            );
                            _loadExpertStats();
                            print('=== END MODAL DROPDOWN DEBUG ===');
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _expertStats.isEmpty
                ? const Text('No data available for this range.')
                : Row(
                  children: [
                    Expanded(
                      child: DataTable(
                        columnSpacing: 8, // minimal extra space
                        columns: const [
                          DataColumn(label: Text('Expert')),
                          DataColumn(label: Text('Avg. Response Time')),
                          DataColumn(label: Text('Reports')),
                          DataColumn(
                            label: Align(
                              alignment: Alignment.center,
                              child: Text('Trend'),
                            ),
                          ),
                        ],
                        rows:
                            _expertStats
                                .map(
                                  (e) => DataRow(
                                    cells: [
                                      DataCell(
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundImage:
                                                  (e.avatar.isNotEmpty)
                                                      ? NetworkImage(e.avatar)
                                                      : null,
                                              child:
                                                  (e.avatar.isEmpty)
                                                      ? const Icon(Icons.person)
                                                      : null,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(e.name),
                                          ],
                                        ),
                                      ),
                                      DataCell(
                                        Text(_formatDuration(e.avgSeconds)),
                                      ),
                                      DataCell(Text(e.count.toString())),
                                      DataCell(
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: SizedBox(
                                            width: double.infinity,
                                            height: 32,
                                            child:
                                                e.trend.length > 1
                                                    ? CustomPaint(
                                                      painter:
                                                          _MiniTrendLinePainter(
                                                            e.trend,
                                                          ),
                                                    )
                                                    : const Text('-'),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ],
                ),
            const SizedBox(height: 12),
            if (_totalCompletedReports > 0)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  () {
                    final label = _displayRangeLabel(_selectedRange);
                    return 'Overall (weighted) for $label: '
                        '${_weightedAverageHours.toStringAsFixed(2)} hours '
                        'across $_totalCompletedReports reports';
                  }(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpertResponseStats {
  final String expertId;
  final String name;
  final String avatar;
  final int avgSeconds;
  final List<double> trend;
  final int count;
  _ExpertResponseStats({
    required this.expertId,
    required this.name,
    required this.avatar,
    required this.avgSeconds,
    required this.trend,
    required this.count,
  });
}

class _MiniTrendLinePainter extends CustomPainter {
  final List<double> data;
  _MiniTrendLinePainter(this.data);
  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final paint =
        Paint()
          ..color = Colors.teal
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
    final min = data.reduce((a, b) => a < b ? a : b);
    final max = data.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 1e-2 ? 1.0 : (max - min);
    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = i * size.width / (data.length - 1);
      final y = size.height - ((data[i] - min) / range * size.height);
      points.add(Offset(x, y));
    }
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (final pt in points.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GenerateReportDialog extends StatefulWidget {
  const GenerateReportDialog({Key? key}) : super(key: key);

  @override
  State<GenerateReportDialog> createState() => _GenerateReportDialogState();
}

class _GenerateReportDialogState extends State<GenerateReportDialog> {
  String _selectedRange = 'Last 7 Days';
  DateTime? _customStart;
  DateTime? _customEnd;
  // Page size fixed to A4
  final List<Map<String, dynamic>> _ranges = [
    {
      'label': '1 Day',
      'icon': Icons.today,
      'desc': 'Reports from the last 24 hours.',
    },
    {
      'label': 'Last 7 Days',
      'icon': Icons.calendar_view_week,
      'desc': 'Reports from the last 7 days.',
    },
    {
      'label': 'Last 30 Days',
      'icon': Icons.calendar_today,
      'desc': 'Reports from the last 30 days.',
    },
    {
      'label': 'Last 60 Days',
      'icon': Icons.date_range,
      'desc': 'Reports from the last 60 days.',
    },
    {
      'label': 'Last 90 Days',
      'icon': Icons.event,
      'desc': 'Reports from the last 90 days.',
    },
    {
      'label': 'Last Year',
      'icon': Icons.calendar_month,
      'desc': 'Reports from the last 12 months.',
    },
    {
      'label': 'Monthly…',
      'icon': Icons.calendar_month_outlined,
      'desc': 'Pick a specific month for the report.',
    },
    {
      'label': 'Custom…',
      'icon': Icons.date_range_outlined,
      'desc': 'Pick a date range for the report.',
    },
  ];

  Map<String, dynamic> get _selectedRangeData =>
      _ranges.firstWhere((r) => r['label'] == _selectedRange);

  String _formatMonthYear(DateTime date) {
    const months = [
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
    return '${months[date.month - 1]} ${date.year}';
  }

  String _formatDateRange(DateTime start, DateTime end) {
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

    final startMonth = months[start.month - 1];
    final endMonth = months[end.month - 1];
    final startDay = start.day;
    final endDay = end.day;
    final startYear = start.year;
    final endYear = end.year;

    // Same month and year: "Aug 8 to 19, 2025"
    if (start.month == end.month && start.year == end.year) {
      return '$startMonth $startDay to $endDay, $startYear';
    }
    // Same year, different months: "Aug 8 to Sep 19, 2025"
    else if (start.year == end.year) {
      return '$startMonth $startDay to $endMonth $endDay, $startYear';
    }
    // Different years: "Dec 25, 2024 to Jan 5, 2025"
    else {
      return '$startMonth $startDay, $startYear to $endMonth $endDay, $endYear';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.picture_as_pdf, color: Color(0xFF2D7204)),
          const SizedBox(width: 10),
          const Text('Generate PDF Report'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a time range for your report.',
            style: TextStyle(fontSize: 15, color: Colors.black87),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: DropdownButton<String>(
              value: _selectedRange,
              isExpanded: true,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down),
              items:
                  _ranges
                      .where(
                        (r) =>
                            r['label'] == 'Last 7 Days' ||
                            r['label'] == 'Monthly…' ||
                            r['label'] == 'Custom…',
                      )
                      .map((range) {
                        return DropdownMenuItem<String>(
                          value: range['label'],
                          child: Row(
                            children: [
                              Icon(
                                range['icon'],
                                size: 20,
                                color: Color(0xFF2D7204),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                range['label'],
                                style: const TextStyle(fontSize: 15),
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedRange = value;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          if (_selectedRange == 'Monthly…') ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: Text(
                _customStart != null
                    ? _formatMonthYear(_customStart!)
                    : 'Pick month',
              ),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await _showMonthYearPicker(
                  context: context,
                  initialDate: _customStart ?? now,
                  firstDate: DateTime(2020),
                  lastDate: now,
                );
                if (picked != null) {
                  // Set to first and last day of the month
                  final firstDay = DateTime(picked.year, picked.month, 1);
                  final lastDay = DateTime(picked.year, picked.month + 1, 0);
                  setState(() {
                    _customStart = firstDay;
                    _customEnd = lastDay;
                  });
                }
              },
            ),
          ],
          if (_selectedRange == 'Custom…') ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(
                _customStart != null && _customEnd != null
                    ? _formatDateRange(_customStart!, _customEnd!)
                    : 'Pick date range',
              ),
              onPressed: () async {
                final initial = DateTimeRange(
                  start:
                      _customStart ??
                      DateTime.now().subtract(const Duration(days: 7)),
                  end: _customEnd ?? DateTime.now(),
                );
                final picked = await pickDateRangeWithSf(
                  context,
                  initial: initial,
                );
                if (picked != null) {
                  setState(() {
                    _customStart = picked.start;
                    _customEnd = picked.end;
                  });
                }
              },
            ),
          ],
          const SizedBox(height: 18),
          Divider(),
          const SizedBox(height: 10),
          Card(
            color: Colors.green[50],
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_selectedRangeData['icon'], color: Color(0xFF2D7204)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedRangeData['label'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF2D7204),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedRangeData['desc'],
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Includes: Disease Distribution, Healthy Trends, Weather Summary',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.teal,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Generate'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF2D7204),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            String range = _selectedRange;
            if (_selectedRange == 'Monthly…') {
              if (_customStart == null || _customEnd == null) return;
              final start = _customStart!;
              final end = _customEnd!;
              final startStr = start.toIso8601String().substring(0, 10);
              final endStr = end.toIso8601String().substring(0, 10);
              range = 'Custom ($startStr to $endStr)';
            } else if (_selectedRange == 'Custom…') {
              if (_customStart == null || _customEnd == null) return;
              final start = _customStart!;
              final end = _customEnd!;
              final startStr = start.toIso8601String().substring(0, 10);
              final endStr = end.toIso8601String().substring(0, 10);
              range = 'Custom ($startStr to $endStr)';
            }
            Navigator.pop(context, {'range': range, 'pageSize': 'A4'});
          },
        ),
      ],
    );
  }

  Future<DateTime?> _showMonthYearPicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    DateTime selectedDate = initialDate;

    return await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Select Month and Year'),
              content: SizedBox(
                width: 300,
                height: 400,
                child: Column(
                  children: [
                    // Year selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios),
                          onPressed:
                              selectedDate.year > firstDate.year
                                  ? () {
                                    setState(() {
                                      selectedDate = DateTime(
                                        selectedDate.year - 1,
                                        selectedDate.month,
                                      );
                                    });
                                  }
                                  : null,
                        ),
                        Text(
                          '${selectedDate.year}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios),
                          onPressed:
                              selectedDate.year < lastDate.year
                                  ? () {
                                    setState(() {
                                      selectedDate = DateTime(
                                        selectedDate.year + 1,
                                        selectedDate.month,
                                      );
                                    });
                                  }
                                  : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Month grid
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 2,
                            ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          final month = index + 1;
                          final isSelected = selectedDate.month == month;
                          final monthDate = DateTime(selectedDate.year, month);
                          final isDisabled =
                              monthDate.isBefore(
                                DateTime(firstDate.year, firstDate.month),
                              ) ||
                              monthDate.isAfter(
                                DateTime(lastDate.year, lastDate.month),
                              );

                          const monthNames = [
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

                          return InkWell(
                            onTap:
                                isDisabled
                                    ? null
                                    : () {
                                      setState(() {
                                        selectedDate = DateTime(
                                          selectedDate.year,
                                          month,
                                        );
                                      });
                                    },
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? const Color(0xFF2D7204)
                                        : isDisabled
                                        ? Colors.grey.shade200
                                        : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      isSelected
                                          ? const Color(0xFF2D7204)
                                          : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                monthNames[index],
                                style: TextStyle(
                                  color:
                                      isDisabled
                                          ? Colors.grey.shade400
                                          : isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selectedDate),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D7204),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
