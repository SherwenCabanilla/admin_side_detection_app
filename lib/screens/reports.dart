import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/report_pdf_service.dart';
// import '../services/settings_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/scan_requests_service.dart';
import '../services/weather_service.dart';
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
  Future<List<Map<String, dynamic>>>?
  _scanRequestsFuture; // cached shared future
  Timer? _autoRefreshTimer;
  bool _refreshInFlight = false;
  final ScrollController _pageScrollController = ScrollController();

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
  String? _avgTemperature; // Average temperature for the time range
  bool _temperatureLoadInProgress =
      false; // Flag to prevent duplicate simultaneous calls

  // New metrics for time-filtered cards
  int _reviewsCompleted = 0; // Reviews done in period (reviewedAt-based)
  int _totalScansSubmitted = 0; // Scans submitted in period
  int _scansCompletedFromPeriod =
      0; // Scans submitted in period that got reviewed
  String _healthyRate = '—';
  int _healthyScansCount = 0;
  int _diseasedScansCount = 0;
  // Dismiss state for completion rate warning animation/icon
  bool _completionWarningDismissed = false;

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

    _scanRequestsFuture = ScanRequestsService.getScanRequests();
    _initializeData();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted || _refreshInFlight) return;
      _refreshInFlight = true;
      try {
        // force refresh data so cache TTL doesn't delay UI updates
        _scanRequestsFuture = ScanRequestsService.getScanRequests();
        await _loadData(silent: true); // avoid toggling global loading state
      } finally {
        _refreshInFlight = false;
      }
    });
  }

  Future<void> _initializeData() async {
    await _loadSavedTimeRange();
    await _loadCompletionWarningDismissed();
    // debug log removed

    // Mark as initialized before loading data
    setState(() {
      _hasInitialized = true;
    });

    // Wait for all data to load
    await _loadData();

    // Now update stats with the correct saved time range
    // debug log removed
    _updateStatsFromSnapshot();

    // Fetch temperature ONCE during initialization only
    _fetchTemperatureData();
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
      // log suppressed in production
    }
  }

  Future<void> _saveTimeRange(String timeRange) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_time_range', timeRange);
    } catch (e) {
      // log suppressed in production
    }
  }

  String _dismissalKeyForRange(String range) =>
      'completion_warning_dismissed_' + range;

  Future<void> _loadCompletionWarningDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _dismissalKeyForRange(_selectedTimeRange);
      final dismissed = prefs.getBool(key);
      if (dismissed != null) {
        setState(() {
          _completionWarningDismissed = dismissed;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _saveCompletionWarningDismissed(bool dismissed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _dismissalKeyForRange(_selectedTimeRange);
      await prefs.setBool(key, dismissed);
    } catch (e) {
      // ignore
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
      // Note: In fallback mode, we don't have real-time reviewsCompleted count
      // so completion rate will be approximate
      try {
        final counts = await ScanRequestsService.getCountsForTimeRange(
          timeRange: _selectedTimeRange,
        );
        final int overduePendingCreated = counts['overduePending'] ?? 0;

        setState(() {
          _completionRate = '—'; // Unable to calculate without reviewedAt data
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
    // debug log removed
    final counts = await ScanRequestsService.getCountsForTimeRange(
      timeRange: _selectedTimeRange,
    );
    // debug log removed
    final int completedByCreated = counts['completed'] ?? 0;
    final int pendingByCreated = counts['pending'] ?? 0;
    final int totalForCompletion = completedByCreated + pendingByCreated;

    final int overduePendingCreated = counts['overduePending'] ?? 0;

    // Calculate new metrics for time-filtered cards
    // 1. Reviews Completed (reviewedAt-based)
    final int reviewsCompletedCount = completedInWindow;

    // 2. Total Scans Submitted (createdAt-based)
    final int totalScansCount = totalForCompletion;

    // 3. TRUE Completion Rate - scans submitted AND completed within the period
    // Count scans that were submitted in period AND reviewed in period
    int scansSubmittedAndCompletedInPeriod = 0;
    for (final r in scanRequests) {
      final status = (r['status'] ?? '').toString();
      if (status != 'completed') continue;

      // Check if submitted in period
      final createdAtRaw = r['createdAt'];
      DateTime? createdAt;
      if (createdAtRaw is Timestamp) createdAt = createdAtRaw.toDate();
      if (createdAtRaw is String) createdAt = DateTime.tryParse(createdAtRaw);

      // Check if reviewed in period
      final reviewedAtRaw = r['reviewedAt'];
      DateTime? reviewedAt;
      if (reviewedAtRaw is Timestamp) reviewedAt = reviewedAtRaw.toDate();
      if (reviewedAtRaw is String)
        reviewedAt = DateTime.tryParse(reviewedAtRaw);

      if (createdAt != null && reviewedAt != null) {
        // Check if BOTH createdAt and reviewedAt are in the period
        final createdInPeriod =
            _selectedTimeRange == '1 Day'
                ? createdAt.isAfter(startInclusive)
                : (!createdAt.isBefore(startInclusive) &&
                    createdAt.isBefore(endExclusive));

        final reviewedInPeriod =
            _selectedTimeRange == '1 Day'
                ? reviewedAt.isAfter(startInclusive)
                : (!reviewedAt.isBefore(startInclusive) &&
                    reviewedAt.isBefore(endExclusive));

        if (createdInPeriod && reviewedInPeriod) {
          scansSubmittedAndCompletedInPeriod++;
        }
      }
    }

    // Card shows TRUE completion rate: scans submitted AND completed in period
    final String completionRateStr =
        totalScansCount == 0
            ? '—'
            : '${((scansSubmittedAndCompletedInPeriod / totalScansCount) * 100).toStringAsFixed(0)}%';

    // 3. Healthy Rate - calculate from disease stats in the time window
    // Use createdAt (when disease occurred) for accurate disease timing
    int healthyScans = 0;
    int diseaseScans = 0;
    for (final r in scanRequests) {
      final status = (r['status'] ?? '').toString();
      if (status != 'completed') continue;

      final createdAtRaw = r['createdAt'];
      DateTime? createdAt;
      if (createdAtRaw is Timestamp) createdAt = createdAtRaw.toDate();
      if (createdAtRaw is String) createdAt = DateTime.tryParse(createdAtRaw);

      if (createdAt != null) {
        final inWindow =
            _selectedTimeRange == '1 Day'
                ? createdAt.isAfter(startInclusive)
                : (!createdAt.isBefore(startInclusive) &&
                    createdAt.isBefore(endExclusive));

        if (inWindow) {
          final List<dynamic> diseaseSummary =
              (r['diseaseSummary'] as List<dynamic>?) ?? [];
          if (diseaseSummary.isEmpty) {
            healthyScans++;
          } else {
            // Check if it contains disease detections (excluding tip burn)
            bool hasDisease = false;
            for (final d in diseaseSummary) {
              String name = 'Unknown';
              if (d is Map<String, dynamic>) {
                name = d['name'] ?? d['label'] ?? d['disease'] ?? 'Unknown';
              } else if (d is String) {
                name = d;
              }
              final lower = name.toLowerCase();
              if (!lower.contains('tip burn') &&
                  !lower.contains('unknown') &&
                  lower != 'healthy') {
                hasDisease = true;
                break;
              }
              if (lower == 'healthy') {
                healthyScans++;
                break;
              }
            }
            if (hasDisease) diseaseScans++;
          }
        }
      }
    }

    final int totalHealthyCheck = healthyScans + diseaseScans;
    final String healthyRateStr =
        totalHealthyCheck == 0
            ? '—'
            : '${((healthyScans / totalHealthyCheck) * 100).toStringAsFixed(1)}%';

    // debug log removed
    setState(() {
      _stats['totalReportsReviewed'] = completedInWindow;
      _stats['pendingRequests'] = pendingInWindow;
      _avgResponseTrend = series;
      _stats['averageResponseTime'] = averageResponseTimeStr;
      _slaWithin24h = sla24Str;
      _slaWithin48h = sla48Str;
      _completionRate =
          completionRateStr; // TRUE rate: submitted AND completed in period
      _overduePendingCount = overduePendingCreated;

      // Update new metrics
      _reviewsCompleted = reviewsCompletedCount;
      _totalScansSubmitted = totalScansCount;
      _scansCompletedFromPeriod =
          completedByCreated; // Lifetime completion (for modal)
      _healthyRate = healthyRateStr;
      _healthyScansCount = healthyScans;
      _diseasedScansCount = diseaseScans;
    });

    // Temperature is loaded ONCE in _initializeData only
    // This function is called every 30s by auto-refresh but does NOT fetch temperature
  }

  // Helper method to parse time range into start and end dates
  Map<String, DateTime> _parseTimeRange(String timeRange) {
    final DateTime now = DateTime.now();
    DateTime startDate;
    DateTime endDate = now;

    // Check for custom or monthly range format
    if (timeRange.startsWith('Custom (') || timeRange.startsWith('Monthly (')) {
      final regex = RegExp(
        r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(timeRange);
      if (match != null) {
        final s = DateTime.parse(match.group(1)!);
        final e = DateTime.parse(match.group(2)!);
        startDate = DateTime(s.year, s.month, s.day);
        endDate = DateTime(e.year, e.month, e.day);
        return {'start': startDate, 'end': endDate};
      }
    }

    // Standard time range options
    switch (timeRange) {
      case '1 Day':
        startDate = now.subtract(const Duration(days: 1));
        break;
      case 'Last 7 Days':
        startDate = now.subtract(const Duration(days: 7));
        break;
      case 'Last 30 Days':
        startDate = now.subtract(const Duration(days: 30));
        break;
      case 'Last 60 Days':
        startDate = now.subtract(const Duration(days: 60));
        break;
      case 'Last 90 Days':
        startDate = now.subtract(const Duration(days: 90));
        break;
      case 'Last Year':
        startDate = DateTime(now.year - 1, now.month, now.day);
        break;
      default:
        startDate = now.subtract(const Duration(days: 7));
    }

    return {'start': startDate, 'end': endDate};
  }

  // Helper method to format time range description for temperature card
  String _formatTimeRangeDescription(String timeRange) {
    const monthNames = [
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

    // Handle custom range
    if (timeRange.startsWith('Custom (')) {
      final regex = RegExp(
        r'Custom \((\d{4})-(\d{2})-(\d{2}) to (\d{4})-(\d{2})-(\d{2})\)',
      );
      final match = regex.firstMatch(timeRange);
      if (match != null) {
        final startYear = match.group(1);
        final startMonth = int.parse(match.group(2)!);
        final startDay = int.parse(match.group(3)!);
        final endYear = match.group(4);
        final endMonth = int.parse(match.group(5)!);
        final endDay = int.parse(match.group(6)!);

        return 'from ${monthNames[startMonth - 1]} $startDay, $startYear to ${monthNames[endMonth - 1]} $endDay, $endYear';
      }
    }

    // Handle monthly range
    if (timeRange.startsWith('Monthly (')) {
      final regex = RegExp(
        r'Monthly \((\d{4})-(\d{2})-(\d{2}) to (\d{4})-(\d{2})-(\d{2})\)',
      );
      final match = regex.firstMatch(timeRange);
      if (match != null) {
        final year = match.group(1);
        final month = int.parse(match.group(2)!);

        return 'for ${monthNames[month - 1]} $year';
      }
    }

    // Handle standard ranges
    switch (timeRange) {
      case '1 Day':
        return 'for the past day';
      case 'Last 7 Days':
        return 'for the past 7 days';
      case 'Last 30 Days':
        return 'for the past 30 days';
      case 'Last 60 Days':
        return 'for the past 60 days';
      case 'Last 90 Days':
        return 'for the past 90 days';
      case 'Last Year':
        return 'for the past year';
      default:
        return 'for the selected period';
    }
  }

  Future<void> _fetchTemperatureData() async {
    print('🌡️ [TEMP-FETCH] === Starting temperature fetch ===');
    print(
      '🌡️ [TEMP-FETCH] mounted: $mounted, loadInProgress: $_temperatureLoadInProgress',
    );

    if (!mounted) {
      print('❌ [TEMP-FETCH] Aborted - widget not mounted');
      return;
    }

    if (_temperatureLoadInProgress) {
      print('⏭️ [TEMP-FETCH] Already loading - skipping duplicate call');
      return;
    }

    // Mark as in progress to prevent duplicate calls
    _temperatureLoadInProgress = true;
    print('✅ [TEMP-FETCH] Marked as in progress - fetching from API now');

    // Set loading state
    if (mounted) {
      setState(() {
        _avgTemperature = 'Loading...';
      });
      print('⏳ [TEMP-FETCH] UI updated to "Loading..."');
    }

    try {
      // Use the selected time range instead of hardcoding 7 days
      final dateRange = _parseTimeRange(_selectedTimeRange);
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;

      print(
        '📅 [TEMP-FETCH] Date range: $startDate to $endDate (from $_selectedTimeRange)',
      );
      print('🌐 [TEMP-FETCH] Calling WeatherService.getAverageTemperature...');

      final weatherSummary = await WeatherService.getAverageTemperature(
        start: startDate,
        end: endDate,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('⏱️ [TEMP-FETCH] TIMEOUT after 15 seconds');
          return WeatherSummary.empty();
        },
      );

      print('📦 [TEMP-FETCH] Response received:');
      print('   - averageC: ${weatherSummary.averageC}');
      print('   - minC: ${weatherSummary.minC}');
      print('   - maxC: ${weatherSummary.maxC}');

      if (!mounted) {
        print(
          '❌ [TEMP-FETCH] Widget unmounted after fetch - aborting setState',
        );
        return;
      }

      setState(() {
        if (weatherSummary.averageC != null &&
            weatherSummary.averageC! > -50 &&
            weatherSummary.averageC! < 60) {
          _avgTemperature = '${weatherSummary.averageC!.toStringAsFixed(1)}°C';
          print('✅ [TEMP-FETCH] SUCCESS - Display: $_avgTemperature');
        } else {
          // Show estimated typical temperature for Davao del Norte
          _avgTemperature = '~27°C';
          print(
            '⚠️ [TEMP-FETCH] API returned no data - Display: "~27°C" (estimated)',
          );
        }
      });
    } catch (e, stackTrace) {
      print('❌ [TEMP-FETCH] EXCEPTION caught: $e');
      print('📚 [TEMP-FETCH] Stack trace: $stackTrace');

      if (!mounted) return;

      setState(() {
        // Show estimated typical temperature on error
        _avgTemperature = '~27°C';
      });
      print('⚠️ [TEMP-FETCH] Error handled - Display: "~27°C" (estimated)');
    } finally {
      // Reset the flag so it can be retried if needed
      _temperatureLoadInProgress = false;
      print('🏁 [TEMP-FETCH] === Temperature fetch completed, flag reset ===');
    }
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // Load data in parallel
      await Future.wait([
        _loadStats(),
        _loadReportsTrend(),
        _loadDiseaseStats(),
        _loadAvgResponseTrend(),
        _loadSla(),
      ]);

      if (!silent && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // log suppressed in production
      if (!silent && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _pageScrollController.dispose();
    super.dispose();
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

      if (mounted) {
        setState(() {
          _stats['totalReportsReviewed'] = completedReports;
          _stats['pendingRequests'] = pendingReports;
          _stats['averageResponseTime'] = averageResponseTime;
        });
      }
    } catch (e) {
      // log suppressed in production
    }
  }

  Future<void> _loadReportsTrend() async {
    try {
      final trendData = await ScanRequestsService.getReportsTrend(
        timeRange: _selectedTimeRange,
      );
      // debug log removed

      // If no data, show a message
      if (mounted) {
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
      }
    } catch (e) {
      // log suppressed in production
      // Fallback data
      if (mounted) {
        setState(() {
          _reportsTrend = [
            {'date': DateTime.now().toString().split(' ')[0], 'count': 0},
          ];
        });
      }
    }
  }

  Future<void> _loadDiseaseStats() async {
    try {
      final diseaseData = await ScanRequestsService.getDiseaseStats(
        timeRange: _selectedTimeRange,
      );
      // debug log removed

      // If no data, show a message
      if (mounted) {
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
      }
    } catch (e) {
      // log suppressed in production
      // Fallback data
      if (mounted) {
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

        if (mounted) {
          setState(() {
            _avgResponseTrend = series;
          });
        }
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
        if (mounted) {
          setState(() {
            _avgResponseTrend = series;
          });
        }
      }
    } catch (e) {
      // log suppressed in production
      if (mounted) {
        setState(() {
          _avgResponseTrend = [];
        });
      }
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
      if (mounted) {
        setState(() {
          _slaWithin24h = slaStr;
          _slaWithin48h = sla48Str;
        });
      }
    } catch (e) {
      // log suppressed in production
      if (mounted) {
        setState(() {
          _slaWithin24h = '—';
          _slaWithin48h = '—';
          _completionRate = '—';
          _overduePendingCount = 0;
        });
      }
    }
  }

  Future<void> _onTimeRangeChanged(String newTimeRange) async {
    if (newTimeRange == _selectedTimeRange) {
      return;
    }

    // Save the selected time range
    await _saveTimeRange(newTimeRange);

    // No activity logging for time range change

    setState(() {
      _selectedTimeRange = newTimeRange;
      // Reset dismissal when the range changes so warnings reflect new data
      _completionWarningDismissed = false;
    });
    await _saveCompletionWarningDismissed(false);
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
      _fetchTemperatureData(), // Refresh temperature data when time range changes
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

    return Consumer<ScanRequestsSnapshot?>(
      builder: (context, scanRequestsSnapshot, child) {
        // Trigger update when snapshot changes (real-time)
        if (_hasInitialized && scanRequestsSnapshot?.snapshot != null) {
          // Use addPostFrameCallback to avoid calling setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _updateStatsFromSnapshot();
            }
          });
        }

        return child!;
      },
      child: SingleChildScrollView(
        key: const PageStorageKey('reports_scroll'),
        controller: _pageScrollController,
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
                              (<String>[
                                    'Last 7 Days',
                                    'Monthly…',
                                    'Custom…',
                                  ]..addAll(
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
                                backgroundAsset:
                                    'assets/report_template_bg.jpg',
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

              // Stats Grid - Time-filtered metrics only
              RepaintBoundary(
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.2,
                  children: [
                    // Row 1: Volume & Health metrics
                    _buildStatCard(
                      'Reviews Completed',
                      _reviewsCompleted.toString(),
                      Icons.check_circle,
                      Colors.green,
                      onTap: () => _showReviewsCompletedModal(context),
                    ),
                    _buildStatCard(
                      'Total Scans Submitted',
                      _totalScansSubmitted.toString(),
                      Icons.upload_file,
                      Colors.blue,
                      onTap: () => _showTotalScansSubmittedModal(context),
                    ),
                    _buildStatCard(
                      'Healthy Rate',
                      _healthyRate,
                      Icons.verified,
                      Colors.lightGreen,
                      onTap: () => _showHealthyRateModal(context),
                    ),
                    _buildStatCard(
                      'Completion Rate',
                      _completionRate ?? '—',
                      Icons.task_alt,
                      Colors.blueGrey,
                      onTap: () async {
                        setState(() {
                          _completionWarningDismissed = true;
                        });
                        await _saveCompletionWarningDismissed(true);
                        _showCompletionRateModal(context);
                      },
                      showWarning: _hasCompletionRateMismatch(),
                    ),
                    // Row 2: Performance & SLA metrics
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
                      'Avg Temperature',
                      _avgTemperature ?? 'Loading...',
                      Icons.thermostat,
                      Colors.deepPurple,
                      onTap: () {
                        print('🖱️ [TEMP-CARD] Temperature card clicked');
                        print(
                          '🖱️ [TEMP-CARD] Current value: $_avgTemperature',
                        );
                        print(
                          '🖱️ [TEMP-CARD] Load in progress: $_temperatureLoadInProgress',
                        );
                        _showAvgTemperatureModal(context);
                      },
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
              ),
              const SizedBox(height: 24),

              // Charts Row
              RepaintBoundary(
                child: Row(
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
              ),
              const SizedBox(height: 16),
              RepaintBoundary(
                child: AvgResponseTrendChart(
                  trend: _avgResponseTrend,
                  selectedTimeRange: _selectedTimeRange,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  bool _isCompletionRateOver100() {
    if (_completionRate == null || _completionRate == '—') return false;
    try {
      final rateStr = _completionRate!.replaceAll('%', '').trim();
      final rate = double.tryParse(rateStr);
      return rate != null && rate > 100;
    } catch (_) {
      return false;
    }
  }

  bool _hasCompletionRateMismatch() {
    // Show warning if reviews completed doesn't match what you'd expect
    // from the completion rate (indicates backlog or future reviews)
    if (_completionWarningDismissed) {
      return false;
    }
    if (_completionRate == null ||
        _completionRate == '—' ||
        _reviewsCompleted == 0 ||
        _totalScansSubmitted == 0) {
      return false;
    }

    // If over 100%, definitely show warning
    if (_isCompletionRateOver100()) return true;

    // If the simple math doesn't match (due to old submissions being reviewed),
    // show warning. Allow 2% tolerance for rounding.
    try {
      final rateStr = _completionRate!.replaceAll('%', '').trim();
      final displayedRate = double.tryParse(rateStr);
      final expectedRate = (_reviewsCompleted / _totalScansSubmitted) * 100;

      if (displayedRate != null && (displayedRate - expectedRate).abs() > 2) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  bool _shouldShowWarningContent() {
    // Show warning content in modal based on actual data conditions,
    // regardless of whether the warning has been dismissed
    if (_completionRate == null ||
        _completionRate == '—' ||
        _reviewsCompleted == 0 ||
        _totalScansSubmitted == 0) {
      return false;
    }

    // If over 100%, definitely show warning content
    if (_isCompletionRateOver100()) return true;

    // If the simple math doesn't match (due to old submissions being reviewed),
    // show warning content. Allow 2% tolerance for rounding.
    try {
      final rateStr = _completionRate!.replaceAll('%', '').trim();
      final displayedRate = double.tryParse(rateStr);
      final expectedRate = (_reviewsCompleted / _totalScansSubmitted) * 100;

      if (displayedRate != null && (displayedRate - expectedRate).abs() > 2) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
    bool showWarning = false,
  }) {
    return _StatCardWithWarning(
      title: title,
      value: value,
      icon: icon,
      color: color,
      onTap: onTap,
      showWarning: showWarning,
    );
  }

  // Modal methods (moved from below to inside _ReportsState class)
  void _showSlaModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 650,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Container(
              width:
                  MediaQuery.of(context).size.width > 700
                      ? 650
                      : MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fixed header with close button
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'SLA ≤ 24h Performance',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _scanRequestsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
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
                            if (createdAt == null || reviewedAt == null)
                              continue;
                            DateTime? created;
                            DateTime? reviewed;
                            if (createdAt is Timestamp)
                              created = createdAt.toDate();
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
                          final slaPercentage =
                              completed == 0
                                  ? 0.0
                                  : (within24 / completed) * 100;
                          final slaText =
                              completed == 0
                                  ? '—'
                                  : '${slaPercentage.toStringAsFixed(0)}%';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'What does this show?',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Percentage of reviews completed within 24 hours during ${_displayRangeLabel(_selectedTimeRange)}.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Icon(
                                    Icons.speed,
                                    color: Colors.indigo.shade700,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'SLA Performance (What\'s on the Card)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.indigo.shade200,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'SLA ≤ 24h Rate:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        Text(
                                          slaText,
                                          style: TextStyle(
                                            fontSize: 26,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                slaPercentage >= 85
                                                    ? Colors.green.shade700
                                                    : slaPercentage >= 70
                                                    ? Colors.orange.shade700
                                                    : Colors.red.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Divider(
                                      color: Colors.indigo.shade300,
                                      thickness: 1.5,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Breakdown:',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.indigo.shade300,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Total Reviews Completed: $completed',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo.shade900,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Completed within 24h: $within24',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green.shade700,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'SLA Rate = ($within24 ÷ $completed) × 100 = $slaText',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.indigo.shade700,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Response Time Distribution',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    _buildResponseTimeBucket(
                                      ' 0-6 hours (Excellent)',
                                      buckets['0-6h']!,
                                      completed,
                                      Colors.green,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildResponseTimeBucket(
                                      ' 6-12 hours (Good)',
                                      buckets['6-12h']!,
                                      completed,
                                      Colors.lightGreen,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildResponseTimeBucket(
                                      ' 12-24 hours (Acceptable)',
                                      buckets['12-24h']!,
                                      completed,
                                      Colors.orange,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildResponseTimeBucket(
                                      ' 24-48 hours (Needs Improvement)',
                                      buckets['24-48h']!,
                                      completed,
                                      Colors.deepOrange,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildResponseTimeBucket(
                                      ' >48 hours (Critical)',
                                      buckets['>48h']!,
                                      completed,
                                      Colors.red,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      slaPercentage >= 85
                                          ? Colors.green.shade50
                                          : slaPercentage >= 70
                                          ? Colors.orange.shade50
                                          : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        slaPercentage >= 85
                                            ? Colors.green.shade200
                                            : slaPercentage >= 70
                                            ? Colors.orange.shade200
                                            : Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      slaPercentage >= 85
                                          ? Icons.check_circle_outline
                                          : slaPercentage >= 70
                                          ? Icons.info_outline
                                          : Icons.warning_amber,
                                      color:
                                          slaPercentage >= 85
                                              ? Colors.green.shade700
                                              : slaPercentage >= 70
                                              ? Colors.orange.shade700
                                              : Colors.red.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                slaPercentage >= 85
                                                    ? Colors.green.shade900
                                                    : slaPercentage >= 70
                                                    ? Colors.orange.shade900
                                                    : Colors.red.shade900,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: 'Performance Insight: ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  slaPercentage >= 85
                                                      ? 'Excellent performance! Your team is meeting SLA targets consistently. $within24 out of $completed reviews were completed within 24 hours.'
                                                      : slaPercentage >= 70
                                                      ? 'Good performance, but there\'s room for improvement. Consider reviewing workload distribution to increase the percentage of reviews completed within 24 hours.'
                                                      : 'Critical: SLA target not being met. Only $within24 out of $completed reviews were completed within 24 hours. Immediate action required to improve response times.',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResponseTimeBucket(
    String label,
    int count,
    int total,
    Color color,
  ) {
    final percentage = total == 0 ? 0.0 : (count / total) * 100;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: percentage / 100,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              '$count (${percentage.toStringAsFixed(0)}%)',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSla48Modal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 650,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Container(
              width:
                  MediaQuery.of(context).size.width > 700
                      ? 650
                      : MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fixed header with close button
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'SLA ≤ 48h Performance',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _scanRequestsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
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
                            if (createdAt == null || reviewedAt == null)
                              continue;
                            DateTime? created;
                            DateTime? reviewed;
                            if (createdAt is Timestamp)
                              created = createdAt.toDate();
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAvgTemperatureModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Container(
              width:
                  MediaQuery.of(context).size.width > 700
                      ? 600
                      : MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fixed header with close button
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Average Temperature',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: FutureBuilder<WeatherSummary>(
                        future: _getTemperatureForRange(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final weather = snapshot.data;
                          if (weather == null || weather.averageC == null) {
                            return const Center(
                              child: Text(
                                'No temperature data available for this period.',
                              ),
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'What does this show?',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Average temperature ${_formatTimeRangeDescription(_selectedTimeRange)}. Temperature impacts plant health and disease development patterns.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Icon(
                                    Icons.thermostat,
                                    color: Colors.deepPurple.shade700,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Temperature Summary',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.orange.shade50,
                                      Colors.deepOrange.shade50,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.shade200,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${weather.averageC!.toStringAsFixed(1)}°C',
                                      style: TextStyle(
                                        fontSize: 48,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepOrange.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Average Temperature',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildTempStat(
                                          'High',
                                          weather.maxC != null
                                              ? '${weather.maxC!.toStringAsFixed(1)}°C'
                                              : '—',
                                          Icons.arrow_upward,
                                          Colors.red,
                                        ),
                                        _buildTempStat(
                                          'Low',
                                          weather.minC != null
                                              ? '${weather.minC!.toStringAsFixed(1)}°C'
                                              : '—',
                                          Icons.arrow_downward,
                                          Colors.blue,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.lightbulb_outline,
                                      color: Colors.blue.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.blue.shade900,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: 'Agricultural Insight: ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            TextSpan(
                                              text: _getTemperatureInsight(
                                                weather.averageC!,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.grey.shade700,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Temperature data is sourced from Open-Meteo API and represents average conditions for Carmen, Davao del Norte during the selected time range.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTempStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  String _getTemperatureInsight(double avgTemp) {
    if (avgTemp < 20) {
      return 'Cooler temperatures may slow plant growth but can reduce certain fungal disease pressure. Monitor for cold-sensitive plant stress.';
    } else if (avgTemp >= 20 && avgTemp < 28) {
      return 'Optimal temperature range for most tropical plants. These conditions support healthy growth while minimizing heat stress.';
    } else if (avgTemp >= 28 && avgTemp < 32) {
      return 'Warm temperatures may accelerate plant growth but also increase water needs. Watch for signs of heat stress and ensure adequate irrigation.';
    } else {
      return 'High temperatures can stress plants and create favorable conditions for certain diseases. Increased monitoring and proper hydration are essential.';
    }
  }

  Future<WeatherSummary> _getTemperatureForRange() async {
    try {
      // Use the selected time range instead of hardcoding 7 days
      final dateRange = _parseTimeRange(_selectedTimeRange);
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;

      return await WeatherService.getAverageTemperature(
        start: startDate,
        end: endDate,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => WeatherSummary.empty(),
      );
    } catch (e) {
      return WeatherSummary.empty();
    }
  }

  void _showCompletionRateModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Container(
              width:
                  MediaQuery.of(context).size.width > 700
                      ? 600
                      : MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fixed header with close button
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Completion Rate',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Scrollable content with FutureBuilder for ongoing status
                  Expanded(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: ScanRequestsService.getOngoingCompletionStatus(
                        timeRange: _selectedTimeRange,
                      ),
                      builder: (context, snapshot) {
                        final ongoingData = snapshot.data;
                        final hasOngoingData =
                            snapshot.connectionState == ConnectionState.done &&
                            ongoingData != null;

                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'What does this show?',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Percentage of scans submitted that were successfully reviewed within the selected time range.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    color: Colors.blueGrey.shade700,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Period Completion Rate (What\'s on the Card)',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Scans submitted AND completed within the selected time range.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blueGrey.shade200,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Completion Rate:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        Text(
                                          _completionRate ?? '—',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blueGrey.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Divider(
                                      color: Colors.blueGrey.shade300,
                                      thickness: 1.5,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'How is this calculated?',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.blueGrey.shade300,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'TOTAL SUBMITTED',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue.shade900,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Scans Submitted in Selected Period: $_totalScansSubmitted',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade900,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'COMPLETED WITHIN PERIOD',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        Colors.green.shade900,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Scans Submitted & Completed in Period: ${_completionRate != null && _completionRate != '—' ? ((_totalScansSubmitted * double.parse(_completionRate!.replaceAll('%', ''))) ~/ 100) : 0}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green.shade900,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '(Both submitted and reviewed within the time range)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.green.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.blueGrey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Formula:',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        Colors
                                                            .blueGrey
                                                            .shade900,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Scans Within Period = ${_completionRate != null && _completionRate != '—' ? ((_totalScansSubmitted * double.parse(_completionRate!.replaceAll('%', ''))) ~/ 100) : 0}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontFamily: 'monospace',
                                                    color:
                                                        Colors
                                                            .blueGrey
                                                            .shade700,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Total Submitted = $_totalScansSubmitted',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontFamily: 'monospace',
                                                    color:
                                                        Colors
                                                            .blueGrey
                                                            .shade700,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Period Completion Rate = ${_completionRate ?? "—"}',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        Colors
                                                            .blueGrey
                                                            .shade900,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.blue.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.blue.shade900,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: 'Key Point: ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  'This is the TRUE completion rate for the selected period - it only counts scans that were BOTH submitted AND reviewed within the time range. This gives you an accurate picture of performance during that specific period.',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Ongoing Status Section
                              if (hasOngoingData) ...[
                                const SizedBox(height: 24),
                                const Divider(thickness: 2),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.timeline,
                                      color: Colors.teal.shade700,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Ongoing Status (As of Today)',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'This section shows what happened to the scans submitted during ${_displayRangeLabel(_selectedTimeRange)}, including reviews completed after the period ended.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.teal.shade200,
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Current Overall Completion:',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.teal.shade900,
                                            ),
                                          ),
                                          Text(
                                            '${ongoingData['currentCompletionRate'].toStringAsFixed(0)}%',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.teal.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Divider(color: Colors.teal.shade300),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Breakdown:',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.teal.shade300,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Total Scans Submitted: ${ongoingData['totalSubmitted']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '├─ Completed within Period: ${ongoingData['completedInPeriod']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green.shade700,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '├─ Completed after Period: ${ongoingData['completedAfterPeriod']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue.shade700,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '└─ Still Pending Today: ${ongoingData['stillPending']}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.orange.shade700,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Divider(
                                              color: Colors.teal.shade200,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Total Completed (${ongoingData['totalCompleted']}) = ${ongoingData['currentCompletionRate'].toStringAsFixed(0)}%',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal.shade900,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.lightbulb_outline,
                                        color: Colors.green.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.green.shade900,
                                            ),
                                            children: [
                                              const TextSpan(
                                                text: 'Professional Insight: ',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              TextSpan(
                                                text:
                                                    ongoingData['completedAfterPeriod'] >
                                                            0
                                                        ? 'Of the ${ongoingData['totalSubmitted']} scans submitted during this period, ${ongoingData['completedAfterPeriod']} were reviewed after the period ended. This indicates backlog processing. The current completion rate of ${ongoingData['currentCompletionRate'].toStringAsFixed(0)}% reflects the real-time status of all submissions from this period.'
                                                        : ongoingData['stillPending'] >
                                                            0
                                                        ? 'All completed reviews from this period were processed within the timeframe. However, ${ongoingData['stillPending']} scans remain pending and require attention.'
                                                        : 'Excellent! All scans submitted during this period have been successfully reviewed, achieving 100% completion.',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (snapshot.connectionState ==
                                  ConnectionState.waiting) ...[
                                const SizedBox(height: 24),
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ],
                              if (_shouldShowWarningContent()) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.orange.shade300,
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.warning_amber,
                                            color: Colors.orange.shade700,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              _isCompletionRateOver100()
                                                  ? 'Why is this over 100%?'
                                                  : 'Notice: Backlog Reviews Detected',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange.shade300,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _reviewsCompleted >
                                                      _totalScansSubmitted
                                                  ? Icons.trending_up
                                                  : Icons.info_outline,
                                              color: Colors.orange.shade700,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: RichText(
                                                text: TextSpan(
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color:
                                                        Colors.orange.shade900,
                                                  ),
                                                  children: [
                                                    TextSpan(
                                                      text:
                                                          '${(_reviewsCompleted - _scansCompletedFromPeriod).abs()} ',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 18,
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text:
                                                          _reviewsCompleted >
                                                                  _scansCompletedFromPeriod
                                                              ? 'reviews were completed from previous submissions'
                                                              : 'reviews completed, but some are from backlog',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'This happens because:',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade900,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange.shade200,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    top: 6,
                                                    right: 8,
                                                  ),
                                                  width: 6,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.orange.shade700,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: RichText(
                                                    text: TextSpan(
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color:
                                                            Colors
                                                                .orange
                                                                .shade900,
                                                      ),
                                                      children: [
                                                        const TextSpan(
                                                          text:
                                                              'Reviews Completed',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        const TextSpan(
                                                          text:
                                                              ' counts scans that were ',
                                                        ),
                                                        const TextSpan(
                                                          text:
                                                              'reviewed (completed)',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        const TextSpan(
                                                          text:
                                                              ' within the selected time range, regardless of when they were submitted.',
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    top: 6,
                                                    right: 8,
                                                  ),
                                                  width: 6,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.orange.shade700,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: RichText(
                                                    text: TextSpan(
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color:
                                                            Colors
                                                                .orange
                                                                .shade900,
                                                      ),
                                                      children: [
                                                        const TextSpan(
                                                          text:
                                                              'Total Scans Submitted',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        const TextSpan(
                                                          text:
                                                              ' only counts scans that were ',
                                                        ),
                                                        const TextSpan(
                                                          text: 'submitted',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        const TextSpan(
                                                          text:
                                                              ' within the selected time range.',
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          '💡 Example: For "Last Month", you might have completed 200 reviews in total, while only 150 scans were submitted during that month — the extra 50 came from earlier backlog.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Container(
              width:
                  MediaQuery.of(context).size.width > 700
                      ? 600
                      : MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fixed header with close button
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Overdue Pending (>24h)',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _scanRequestsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final all = snapshot.data ?? [];
                          final filtered =
                              ScanRequestsService.filterByTimeRange(
                                all,
                                _selectedTimeRange,
                              );

                          // Calculate overdue scans by time buckets
                          int overdue24to48 = 0;
                          int overdue48to72 = 0;
                          int overdueOver72 = 0;
                          int totalOverdue = 0;
                          int totalPending = 0;

                          final now = DateTime.now();

                          for (final r in filtered) {
                            if ((r['status'] ?? '') == 'pending') {
                              totalPending++;
                              final createdAt = r['createdAt'];
                              DateTime? created;
                              if (createdAt is Timestamp) {
                                created = createdAt.toDate();
                              } else if (createdAt is String) {
                                created = DateTime.tryParse(createdAt);
                              }
                              if (created != null) {
                                final hrs =
                                    now.difference(created).inMinutes / 60.0;
                                if (hrs > 24.0) {
                                  totalOverdue++;
                                  if (hrs <= 48.0) {
                                    overdue24to48++;
                                  } else if (hrs <= 72.0) {
                                    overdue48to72++;
                                  } else {
                                    overdueOver72++;
                                  }
                                }
                              }
                            }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'What does this show?',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Number of pending scan reports that have been waiting for review for more than 24 hours within the selected time range.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Summary',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.shade200,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Overdue Pending:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        Text(
                                          '$totalOverdue',
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Divider(color: Colors.orange.shade200),
                                    const SizedBox(height: 8),
                                    _buildDetailRow(
                                      'Total Pending:',
                                      '$totalPending',
                                    ),
                                    _buildDetailRow(
                                      'Time Range:',
                                      _displayRangeLabel(_selectedTimeRange),
                                    ),
                                    _buildDetailRow(
                                      'Status:',
                                      'Pending > 24 hours',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Aging Breakdown',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    _buildAgingBucket(
                                      '⚠️ 24-48 hours',
                                      overdue24to48,
                                      totalOverdue,
                                      Colors.orange,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildAgingBucket(
                                      '⚠️ 48-72 hours',
                                      overdue48to72,
                                      totalOverdue,
                                      Colors.deepOrange,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildAgingBucket(
                                      '🔴 Over 72 hours',
                                      overdueOver72,
                                      totalOverdue,
                                      Colors.red,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'This metric tracks pending scans by their creation date, helping you identify backlogs that need immediate attention.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildInsightBox(
                                'Action Required',
                                _getOverduePendingInsight(
                                  totalOverdue,
                                  totalPending,
                                  overdueOver72,
                                ),
                                Icons.warning_amber,
                                Colors.orange,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAgingBucket(String label, int count, int total, Color color) {
    final percentage = total == 0 ? 0.0 : (count / total) * 100;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: total == 0 ? 0 : percentage / 100,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              '$count (${percentage.toStringAsFixed(0)}%)',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getOverduePendingInsight(
    int totalOverdue,
    int totalPending,
    int overdueOver72,
  ) {
    if (totalOverdue == 0) {
      return 'Excellent! No overdue pending scans. Your team is responding to all submissions within 24 hours.';
    } else if (totalOverdue < totalPending * 0.1) {
      return 'Good response time. Only ${((totalOverdue / totalPending) * 100).toStringAsFixed(0)}% of pending scans are overdue. Continue monitoring to maintain this performance.';
    } else if (overdueOver72 > 0) {
      return 'Critical: $overdueOver72 scans have been pending for over 72 hours. Immediate action required. Consider redistributing workload or adding more reviewers to clear the backlog.';
    } else {
      return 'Action needed: ${((totalOverdue / totalPending) * 100).toStringAsFixed(0)}% of pending scans are overdue (>24h). Review team capacity and prioritize older submissions to improve response times.';
    }
  }

  void _showReviewsCompletedModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Container(
              width:
                  MediaQuery.of(context).size.width > 700
                      ? 600
                      : MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fixed header with close button
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Reviews Completed',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'What does this show?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total number of scan reports reviewed by experts within the selected time range.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Calculation Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Reviews Completed:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      '$_reviewsCompleted',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Divider(color: Colors.green.shade200),
                                const SizedBox(height: 8),
                                _buildDetailRow(
                                  'Time Range:',
                                  _displayRangeLabel(_selectedTimeRange),
                                ),
                                _buildDetailRow(
                                  'Filters by:',
                                  'When review was completed',
                                ),
                                _buildDetailRow(
                                  'Status:',
                                  'Completed reports only',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'This counts when reports were REVIEWED, not when they were submitted.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Backlog note: show only when some reviews came from earlier submissions
                          if (_reviewsCompleted > _scansCompletedFromPeriod)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.history,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Includes backlog: ${_reviewsCompleted - _scansCompletedFromPeriod} reviews from earlier submissions',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.orange.shade900,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          _buildInsightBox(
                            'Insight',
                            _getReviewsCompletedInsight(),
                            Icons.lightbulb_outline,
                            Colors.amber,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTotalScansSubmittedModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Container(
              width:
                  MediaQuery.of(context).size.width > 700
                      ? 600
                      : MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fixed header with close button
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Total Scans Submitted',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'What does this show?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total number of scan requests submitted by farmers within the selected time range.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Calculation Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total Scans Submitted:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      '$_totalScansSubmitted',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Divider(color: Colors.blue.shade200),
                                const SizedBox(height: 8),
                                _buildDetailRow(
                                  'Time Range:',
                                  _displayRangeLabel(_selectedTimeRange),
                                ),
                                _buildDetailRow(
                                  'Filters by:',
                                  'When scan was submitted',
                                ),
                                _buildDetailRow(
                                  'Includes:',
                                  'All submitted scans (pending + completed)',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Comparing with Reviews',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow(
                                  'Scans Submitted:',
                                  '$_totalScansSubmitted',
                                ),
                                _buildDetailRow(
                                  'Reviews Completed:',
                                  '$_reviewsCompleted',
                                ),
                                const SizedBox(height: 8),
                                Divider(color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Gap:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      '${_totalScansSubmitted - _reviewsCompleted}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            (_totalScansSubmitted -
                                                        _reviewsCompleted) >
                                                    0
                                                ? Colors.orange.shade700
                                                : Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'This gap represents scans still pending or reviewed outside the time range.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildInsightBox(
                            'Insight',
                            _getTotalScansSubmittedInsight(),
                            Icons.analytics_outlined,
                            Colors.blue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showHealthyRateModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Container(
              width:
                  MediaQuery.of(context).size.width > 700
                      ? 600
                      : MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fixed header with close button
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Healthy Rate',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'What does this show?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.lightGreen,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Percentage of reviewed scans that came back as healthy (no disease detected).',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Calculation Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.lightGreen,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Healthy Rate:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      _healthyRate,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Divider(color: Colors.green.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  'Breakdown:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildDetailRow(
                                  'Healthy Scans:',
                                  '$_healthyScansCount',
                                ),
                                _buildDetailRow(
                                  'Diseased Scans:',
                                  '$_diseasedScansCount',
                                ),
                                const SizedBox(height: 4),
                                Divider(color: Colors.green.shade200),
                                const SizedBox(height: 4),
                                _buildDetailRow(
                                  'Total Reviewed:',
                                  '${_healthyScansCount + _diseasedScansCount}',
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.green.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    'Formula: ($_healthyScansCount ÷ ${_healthyScansCount + _diseasedScansCount}) × 100% = $_healthyRate',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade900,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Data Filters',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.lightGreen,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow(
                                  'Time Range:',
                                  _displayRangeLabel(_selectedTimeRange),
                                ),
                                _buildDetailRow(
                                  'Filters by:',
                                  'When review was completed',
                                ),
                                _buildDetailRow(
                                  'Status:',
                                  'Completed scans only',
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Excluded:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '• Tip Burn/Unknown (not considered a disease)\n'
                                  '• Pending/unreviewed scans',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Interpreting the results:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.lightGreen,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildHealthIndicator(
                            '80-100%',
                            'Excellent field health',
                            Colors.green,
                          ),
                          const SizedBox(height: 4),
                          _buildHealthIndicator(
                            '50-79%',
                            'Moderate disease presence',
                            Colors.orange,
                          ),
                          const SizedBox(height: 4),
                          _buildHealthIndicator(
                            '0-49%',
                            'High disease pressure',
                            Colors.red,
                          ),
                          const SizedBox(height: 16),
                          _buildInsightBox(
                            'Insight',
                            _getHealthyRateInsight(),
                            Icons.eco_outlined,
                            Colors.green,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHealthIndicator(String range, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          '$range: ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightBox(
    String title,
    String message,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[800],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getReviewsCompletedInsight() {
    if (_reviewsCompleted == 0) {
      return 'No reviews completed in this period. Check if experts are actively reviewing reports or if there are system issues.';
    }

    final avgPerDay = _reviewsCompleted / _getSelectedRangeDays();

    if (avgPerDay < 5) {
      return 'Low review activity detected (${avgPerDay.toStringAsFixed(1)} per day). Consider checking expert workload distribution or if additional support is needed.';
    } else if (avgPerDay >= 10) {
      return 'High productivity period! ${avgPerDay.toStringAsFixed(1)} reviews per day. This indicates strong expert engagement and efficient workflow.';
    } else {
      return 'Moderate review activity at ${avgPerDay.toStringAsFixed(1)} reviews per day. Monitor trends in the Avg. Response Time chart to ensure consistent service levels.';
    }
  }

  String _getTotalScansSubmittedInsight() {
    final gap = _totalScansSubmitted - _reviewsCompleted;

    if (gap <= 0) {
      return 'Excellent! All submitted scans have been reviewed. Your team is keeping up with demand effectively.';
    }

    final gapPercentage = (gap / _totalScansSubmitted) * 100;

    if (gapPercentage > 30) {
      return 'Significant backlog detected: $gap scans (${gapPercentage.toStringAsFixed(0)}%) are pending or reviewed outside the time range. Check "Overdue Pending >24h" and consider redistributing workload.';
    } else if (gapPercentage > 15) {
      return 'Moderate gap of $gap scans (${gapPercentage.toStringAsFixed(0)}%). Some reports may still be in review. Monitor the "Avg. Response Time" to ensure timely processing.';
    } else {
      return 'Small gap of $gap scans (${gapPercentage.toStringAsFixed(0)}%). This is normal as some scans may have been reviewed just outside the time window or are newly submitted.';
    }
  }

  String _getHealthyRateInsight() {
    final total = _healthyScansCount + _diseasedScansCount;

    if (total == 0) {
      return 'No data available for this period. Ensure scans are being submitted and reviewed.';
    }

    final rate = (_healthyScansCount / total) * 100;

    if (rate >= 80) {
      return 'Excellent field health! ${rate.toStringAsFixed(1)}% healthy rate indicates minimal disease pressure. Continue current management practices and monitor for any changes.';
    } else if (rate >= 50) {
      return 'Moderate disease presence at ${rate.toStringAsFixed(1)}% healthy. Review the Disease Distribution chart to identify primary threats. Consider targeted interventions for affected areas.';
    } else if (rate >= 30) {
      return 'Elevated disease pressure detected (${rate.toStringAsFixed(1)}% healthy). Check Disease Trends for patterns. Immediate attention may be needed for disease management.';
    } else {
      return 'Critical: High disease pressure with only ${rate.toStringAsFixed(1)}% healthy scans. Review Disease Distribution urgently and consider implementing comprehensive treatment interventions.';
    }
  }

  int _getSelectedRangeDays() {
    if (_selectedTimeRange.startsWith('Custom (') ||
        _selectedTimeRange.startsWith('Monthly (')) {
      final regex = RegExp(
        r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(_selectedTimeRange);
      if (match != null) {
        final start = DateTime.parse(match.group(1)!);
        final end = DateTime.parse(match.group(2)!);
        return end.difference(start).inDays + 1;
      }
    }

    switch (_selectedTimeRange) {
      case '1 Day':
        return 1;
      case 'Last 7 Days':
        return 7;
      case 'Last 30 Days':
        return 30;
      case 'Last 60 Days':
        return 60;
      case 'Last 90 Days':
        return 90;
      case 'Last Year':
        return 365;
      default:
        return 7;
    }
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
            selectedTimeRange: _selectedTimeRange,
          ),
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

class _StatCardWithWarning extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool showWarning;

  const _StatCardWithWarning({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    required this.showWarning,
  });

  @override
  State<_StatCardWithWarning> createState() => _StatCardWithWarningState();
}

class _StatCardWithWarningState extends State<_StatCardWithWarning>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.02,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.02,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_controller);

    _colorAnimation = ColorTween(
      begin: Colors.transparent,
      end: Colors.orange.withOpacity(0.1),
    ).animate(_controller);

    if (widget.showWarning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_StatCardWithWarning oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showWarning && !oldWidget.showWarning) {
      _controller.repeat();
    } else if (!widget.showWarning && oldWidget.showWarning) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showWarning) {
      return _buildCard();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3 * _controller.value),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: _buildCard(borderColor: _colorAnimation.value),
          ),
        );
      },
    );
  }

  Widget _buildCard({Color? borderColor}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            borderColor != null
                ? BorderSide(color: borderColor, width: 2)
                : BorderSide.none,
      ),
      child: InkWell(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Main content - always centered
            SizedBox.expand(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(widget.icon, size: 24, color: widget.color),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.value,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
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
            // Warning badge - positioned absolutely
            if (widget.showWarning)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AvgResponseTrendChart extends StatefulWidget {
  final List<Map<String, dynamic>> trend;
  final String selectedTimeRange;

  const AvgResponseTrendChart({
    Key? key,
    required this.trend,
    required this.selectedTimeRange,
  }) : super(key: key);

  @override
  State<AvgResponseTrendChart> createState() => _AvgResponseTrendChartState();
}

class _AvgResponseTrendChartState extends State<AvgResponseTrendChart> {
  String _chartMode = 'line'; // 'line' | 'bar'
  late Future<List<Map<String, dynamic>>> _scanRequestsFuture;

  @override
  void initState() {
    super.initState();
    // Cache the future to prevent infinite loading
    _scanRequestsFuture = ScanRequestsService.getScanRequests();

    // Load persisted chart mode
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('chart_mode_avg_response');
        if (saved == 'bar' || saved == 'line') {
          if (mounted) setState(() => _chartMode = saved!);
        }
      } catch (_) {}
    }();
  }

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

    final isEmpty = widget.trend.isEmpty;
    final int numPoints = widget.trend.length;
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
                Text(
                  _chartMode == 'line'
                      ? 'Avg Expert Response (hrs)'
                      : 'Response Time Distribution',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
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
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButton<String>(
                    value: _chartMode,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: 'line',
                        child: Text('Trend (Line)'),
                      ),
                      DropdownMenuItem(
                        value: 'bar',
                        child: Text('Distribution (Bar)'),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() {
                        _chartMode = v;
                      });
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('chart_mode_avg_response', v);
                      } catch (_) {}
                    },
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
              _chartMode == 'line'
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Legend for SLA zones
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildLegendItem(Colors.green, 'Excellent (≤24h)'),
                          const SizedBox(width: 12),
                          _buildLegendItem(Colors.orange, 'Warning (24-48h)'),
                          const SizedBox(width: 12),
                          _buildLegendItem(Colors.red, 'Critical (>48h)'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(height: 220, child: _buildLineChart(minX, maxX)),
                    ],
                  )
                  : _buildBarChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(double minX, double maxX) {
    return LineChart(
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
                final raw = (widget.trend[index]['date'] as String);
                String dateLabel;
                if (widget.selectedTimeRange == '1 Day') {
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
                final valueStr = '${barSpot.y.toStringAsFixed(1)} hrs';
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
              reservedSize: 56,
              interval: () {
                // Calculate the max value and use it as interval
                // This ensures we get called at 0 and maxVal
                if (widget.trend.isEmpty) return 1.0;
                final maxVal = widget.trend
                    .map((e) => (e['avgHours'] as double))
                    .reduce((a, b) => a > b ? a : b);
                return maxVal > 0 ? maxVal : 1.0;
              }(),
              getTitlesWidget: (value, meta) {
                // Only show 0 and max value labels
                if (widget.trend.isEmpty) return const SizedBox.shrink();
                final maxVal = widget.trend
                    .map((e) => (e['avgHours'] as double))
                    .reduce((a, b) => a > b ? a : b);

                if (value == 0) {
                  return const Text('0', style: TextStyle(fontSize: 10));
                }
                if (value >= maxVal * 0.99 && value <= maxVal * 1.01) {
                  final String label =
                      maxVal >= 10
                          ? maxVal.toStringAsFixed(0)
                          : maxVal.toStringAsFixed(1);
                  return Text(label, style: const TextStyle(fontSize: 10));
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval:
                  widget.selectedTimeRange == '1 Day'
                      ? 1
                      : _computeXInterval(widget.trend),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= widget.trend.length)
                  return const SizedBox.shrink();
                final raw = (widget.trend[i]['date'] as String);
                final label =
                    widget.selectedTimeRange == '1 Day'
                        ? raw // already in HH:00
                        : raw.split('-').sublist(1).join('-');
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(label, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: -5,
        maxY: () {
          // Calculate max value from trend data
          if (widget.trend.isEmpty) return 50.0;
          final maxVal = widget.trend
              .map((e) => (e['avgHours'] as double))
              .reduce((a, b) => a > b ? a : b);
          // Add 15% padding above the max value for breathing room
          return (maxVal * 1.15).toDouble();
        }(),
        // Add SLA threshold lines
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            // 24-hour SLA line
            HorizontalLine(
              y: 24,
              color: Colors.orange.withOpacity(0.4),
              strokeWidth: 2,
              dashArray: [5, 5],
            ),
            // 48-hour line
            HorizontalLine(
              y: 48,
              color: Colors.red.withOpacity(0.4),
              strokeWidth: 2,
              dashArray: [5, 5],
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            barWidth: 3,
            // Show a dot when there is only a single data point so the chart isn't blank
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: widget.trend.length <= 1 ? 5 : 3,
                  color: _getColorForValue(spot.y),
                  strokeWidth: 1.5,
                  strokeColor: Colors.white,
                );
              },
            ),
            // Use gradient or color segments
            gradient: LinearGradient(
              colors: _buildGradientColors(widget.trend),
              stops: _buildGradientStops(widget.trend),
            ),
            spots: [
              for (int i = 0; i < widget.trend.length; i++)
                FlSpot(
                  i.toDouble(),
                  (widget.trend[i]['avgHours'] as double).toDouble(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    // We need to calculate from actual scan requests, not aggregated trend data
    // This will be done with FutureBuilder to fetch the raw data
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _scanRequestsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('No data available'));
        }

        final all = snapshot.data!;

        // Build time window matching the selected range
        final DateTime now = DateTime.now();
        DateTime startInclusive;
        DateTime endExclusive;

        if (widget.selectedTimeRange.startsWith('Custom (') ||
            widget.selectedTimeRange.startsWith('Monthly (')) {
          final regex = RegExp(
            r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
          );
          final match = regex.firstMatch(widget.selectedTimeRange);
          if (match != null) {
            final s = DateTime.parse(match.group(1)!);
            final e = DateTime.parse(match.group(2)!);
            startInclusive = DateTime(s.year, s.month, s.day);
            endExclusive = DateTime(
              e.year,
              e.month,
              e.day,
            ).add(const Duration(days: 1));
          } else {
            startInclusive = now.subtract(const Duration(days: 7));
            endExclusive = now;
          }
        } else {
          switch (widget.selectedTimeRange) {
            case '1 Day':
              startInclusive = now.subtract(const Duration(days: 1));
              break;
            case 'Last 7 Days':
              startInclusive = now.subtract(const Duration(days: 7));
              break;
            case 'Last 30 Days':
              startInclusive = now.subtract(const Duration(days: 30));
              break;
            case 'Last 60 Days':
              startInclusive = now.subtract(const Duration(days: 60));
              break;
            case 'Last 90 Days':
              startInclusive = now.subtract(const Duration(days: 90));
              break;
            case 'Last Year':
              startInclusive = DateTime(now.year - 1, now.month, now.day);
              break;
            default:
              startInclusive = now.subtract(const Duration(days: 7));
          }
          endExclusive = now;
        }

        // Calculate buckets from individual reviews
        final Map<String, int> buckets = {
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
          if (createdAt is String) created = DateTime.tryParse(createdAt);
          if (reviewedAt is Timestamp) reviewed = reviewedAt.toDate();
          if (reviewedAt is String) reviewed = DateTime.tryParse(reviewedAt);

          if (created == null || reviewed == null) continue;

          // Filter by reviewedAt within window
          final inWindow =
              !reviewed.isBefore(startInclusive) &&
              reviewed.isBefore(endExclusive);
          if (!inWindow) continue;

          final hours = reviewed.difference(created).inMinutes / 60.0;

          if (hours <= 6) {
            buckets['0-6h'] = buckets['0-6h']! + 1;
          } else if (hours <= 12) {
            buckets['6-12h'] = buckets['6-12h']! + 1;
          } else if (hours <= 24) {
            buckets['12-24h'] = buckets['12-24h']! + 1;
          } else if (hours <= 48) {
            buckets['24-48h'] = buckets['24-48h']! + 1;
          } else {
            buckets['>48h'] = buckets['>48h']! + 1;
          }
        }

        final maxCount =
            buckets.values.isEmpty
                ? 0
                : buckets.values.reduce((a, b) => a > b ? a : b);
        final double chartMaxY = maxCount > 0 ? maxCount * 1.2 : 10.0;

        return _buildBarChartWidget(buckets, chartMaxY);
      },
    );
  }

  Widget _buildBarChartWidget(Map<String, int> buckets, double chartMaxY) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend - aligned to the right to match line chart
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  _buildBucketLegend(
                    ' 0-6h',
                    'Excellent',
                    const Color(0xFF4CAF50),
                  ),
                  _buildBucketLegend(' 6-12h', 'Good', const Color(0xFF8BC34A)),
                  _buildBucketLegend(
                    ' 12-24h',
                    'Acceptable',
                    const Color(0xFFFF9800),
                  ),
                  _buildBucketLegend(
                    ' 24-48h',
                    'Needs Improvement',
                    const Color(0xFFFF5722),
                  ),
                  _buildBucketLegend(
                    ' >48h',
                    'Critical',
                    const Color(0xFFF44336),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: chartMaxY,
              minY: 0,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  tooltipBgColor: Colors.blueGrey,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final label =
                        ['0-6h', '6-12h', '12-24h', '24-48h', '>48h'][group.x
                            .toInt()];
                    return BarTooltipItem(
                      '$label\n${rod.toY.toInt()} reviews',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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
                      const labels = [
                        '0-6h',
                        '6-12h',
                        '12-24h',
                        '24-48h',
                        '>48h',
                      ];
                      if (value.toInt() >= 0 && value.toInt() < labels.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            labels[value.toInt()],
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval:
                    chartMaxY > 10 ? (chartMaxY / 5).ceilToDouble() : 2,
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                _buildBarGroup(
                  0,
                  buckets['0-6h']!.toDouble(),
                  const Color(0xFF4CAF50),
                ),
                _buildBarGroup(
                  1,
                  buckets['6-12h']!.toDouble(),
                  const Color(0xFF8BC34A),
                ),
                _buildBarGroup(
                  2,
                  buckets['12-24h']!.toDouble(),
                  const Color(0xFFFF9800),
                ),
                _buildBarGroup(
                  3,
                  buckets['24-48h']!.toDouble(),
                  const Color(0xFFFF5722),
                ),
                _buildBarGroup(
                  4,
                  buckets['>48h']!.toDouble(),
                  const Color(0xFFF44336),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  BarChartGroupData _buildBarGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 32,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
      ],
    );
  }

  Widget _buildBucketLegend(String label, String description, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ($description)',
          style: const TextStyle(fontSize: 11, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black87),
        ),
      ],
    );
  }

  Color _getColorForValue(double hours) {
    if (hours <= 24) {
      return Colors.green;
    } else if (hours <= 48) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  List<Color> _buildGradientColors(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return [Colors.teal, Colors.teal];
    if (data.length == 1) {
      final hours = data[0]['avgHours'] as double;
      final color = _getColorForValue(hours);
      return [color, color];
    }

    List<Color> colors = [];
    for (var point in data) {
      final hours = point['avgHours'] as double;
      colors.add(_getColorForValue(hours));
    }
    return colors;
  }

  List<double> _buildGradientStops(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return [0.0, 1.0];
    if (data.length == 1) return [0.0, 1.0];

    List<double> stops = [];
    for (int i = 0; i < data.length; i++) {
      stops.add(i / (data.length - 1));
    }
    return stops;
  }

  double _computeXInterval(List<Map<String, dynamic>> data) {
    final n = data.length;
    if (n <= 1) return 1;
    if (n <= 10) return 1;
    return (n / 10).ceilToDouble();
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

class _ReportsListTableState extends State<ReportsListTable>
    with AutomaticKeepAliveClientMixin {
  String _searchQuery = '';
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _error;
  // Pagination and debounced search
  int _rowsPerPage = 10;
  int _page = 0;
  Timer? _searchDebounce;

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
        _page = 0; // reset page on data load
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

  List<Map<String, dynamic>> get _visibleReports {
    final total = _filteredReports.length;
    final start = _page * _rowsPerPage;
    if (start >= total) return const [];
    final endExclusive = start + _rowsPerPage;
    final safeEnd = endExclusive > total ? total : endExclusive;
    return _filteredReports.sublist(start, safeEnd);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // for AutomaticKeepAliveClientMixin
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
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                  if (!mounted) return;
                  setState(() {
                    _searchQuery = value;
                    _page = 0; // reset page when searching
                  });
                });
              },
            ),
          ),
        ),
        // Pagination controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text('Rows per page:'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _rowsPerPage,
                  items:
                      const [10, 25, 50, 100]
                          .map(
                            (n) =>
                                DropdownMenuItem(value: n, child: Text('$n')),
                          )
                          .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _rowsPerPage = v;
                      _page = 0;
                    });
                  },
                ),
              ],
            ),
            Row(
              children: [
                Builder(
                  builder: (context) {
                    final total = _filteredReports.length;
                    final start = total == 0 ? 0 : (_page * _rowsPerPage) + 1;
                    final end = ((_page + 1) * _rowsPerPage);
                    final shownEnd = end > total ? total : end;
                    return Text(
                      total == 0 ? '0 of 0' : '$start–$shownEnd of $total',
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed:
                      _page > 0
                          ? () {
                            setState(() {
                              _page -= 1;
                            });
                          }
                          : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed:
                      ((_page + 1) * _rowsPerPage) < _filteredReports.length
                          ? () {
                            setState(() {
                              _page += 1;
                            });
                          }
                          : null,
                ),
              ],
            ),
          ],
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
                    : RepaintBoundary(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Report ID')),
                          DataColumn(label: Text('User')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Disease')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows:
                            _visibleReports.map((report) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text((report['id'] ?? '').toString()),
                                  ),
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
                                                        CrossAxisAlignment
                                                            .start,
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
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                      if (report['image'] !=
                                                          null)
                                                        Container(
                                                          height: 180,
                                                          width: 180,
                                                          color:
                                                              Colors.grey[200],
                                                          child: Image.network(
                                                            report['image']
                                                                .toString(),
                                                            fit: BoxFit.cover,
                                                            filterQuality:
                                                                FilterQuality
                                                                    .low,
                                                            gaplessPlayback:
                                                                true,
                                                            // Hint to decoder to downscale to container size
                                                            cacheWidth: 360,
                                                            cacheHeight: 360,
                                                          ),
                                                        )
                                                      else
                                                        Container(
                                                          height: 180,
                                                          width: 180,
                                                          color:
                                                              Colors.grey[200],
                                                          child: const Center(
                                                            child: Text(
                                                              'No Image',
                                                            ),
                                                          ),
                                                        ),
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
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
  String _chartMode = 'bar'; // 'bar' | 'line'
  bool _loadingTrend = false;
  String? _trendError;
  bool _trendLoaded = false; // load cycle completed
  bool _trendIsEmpty = false; // last load returned empty data
  Timer? _trendEmptyGuardTimer; // avoids brief empty-state flash
  // Disease trend state (daily percentages)
  List<String> _trendLabels = const [];
  Map<String, List<double>> _seriesByDisease = const {};
  List<String> _topDiseasesOrder = const [];
  List<double> _healthySeries = const [];

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
    // Re-enable live updates with debounce to prevent flicker
    _streamSub = FirebaseFirestore.instance
        .collection('scan_requests')
        .snapshots()
        .listen((snap) {
          _lastSnapshot = snap;
          _scheduleDebouncedRecompute();
        });
    // Load saved chart mode preference
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('chart_mode_distribution');
        if (saved == 'bar' || saved == 'line') {
          if (mounted) {
            setState(() {
              _chartMode = saved!;
              if (saved == 'line') {
                _loadingTrend = true;
                _trendLoaded = false;
                _trendIsEmpty = false;
              }
            });
            if (saved == 'line') {
              _loadTrend();
            }
          }
        }
      } catch (_) {}
    }();
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
      if (_chartMode == 'line') {
        setState(() {
          _loadingTrend = true;
          _trendLoaded = false;
          _trendIsEmpty = false;
        });
        _loadTrend();
      }
    }
  }

  @override
  void dispose() {
    _trendEmptyGuardTimer?.cancel();
    _streamSub?.cancel();
    super.dispose();
  }

  Timer? _debounceTimer;
  void _scheduleDebouncedRecompute() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || _lastSnapshot == null) return;
      final agg = _aggregateFromSnapshot(
        _lastSnapshot,
        widget.selectedTimeRange,
      );
      setState(() {
        _liveAggregated = agg;
      });
      if (_chartMode == 'line') {
        setState(() {
          _loadingTrend = true;
          _trendLoaded = false;
          _trendIsEmpty = false;
        });
        _loadTrend();
      }
    });
  }

  Future<void> _loadTrend() async {
    setState(() {
      _loadingTrend = true;
      _trendError = null;
      _trendLoaded = false;
      _trendIsEmpty = false;
    });
    _trendEmptyGuardTimer?.cancel();
    try {
      // Compute disease daily percentages similar to PDF
      final range = _resolveDateRange(widget.selectedTimeRange);
      final DateTime start = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final DateTime endEx = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
      );

      final all = await ScanRequestsService.getScanRequests();
      final Map<String, int> diseaseByDay = {};
      final Map<String, int> healthyByDay = {};
      final Map<String, Map<String, int>> diseaseDayCounts = {};

      for (final r in all) {
        if ((r['status'] ?? '') != 'completed') continue;
        final createdAt = r['createdAt'];
        DateTime? dt;
        if (createdAt is Timestamp) dt = createdAt.toDate();
        if (createdAt is String) dt = DateTime.tryParse(createdAt);
        if (dt == null) continue;
        if (dt.isBefore(start) || !dt.isBefore(endEx)) continue;
        final key =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

        List<dynamic> diseaseSummary =
            (r['diseaseSummary'] as List<dynamic>?) ?? const [];
        if (diseaseSummary.isEmpty) {
          healthyByDay[key] = (healthyByDay[key] ?? 0) + 1;
          continue;
        }
        for (final d in diseaseSummary) {
          String name = 'Unknown';
          int count = 1;
          if (d is Map<String, dynamic>) {
            name =
                (d['name'] ?? d['label'] ?? d['disease'] ?? 'Unknown')
                    .toString();
            final c = d['count'] ?? d['confidence'] ?? 1;
            if (c is num) count = c.round();
          } else if (d is String) {
            name = d;
          }
          final lower = name.toLowerCase();
          if (lower == 'healthy') {
            healthyByDay[key] = (healthyByDay[key] ?? 0) + count;
            continue;
          }
          if (lower.contains('tip burn') || lower.contains('unknown')) continue;
          diseaseByDay[key] = (diseaseByDay[key] ?? 0) + count;
          final perDay = diseaseDayCounts[lower] ?? <String, int>{};
          perDay[key] = (perDay[key] ?? 0) + count;
          diseaseDayCounts[lower] = perDay;
        }
      }

      final keys =
          <String>{}
            ..addAll(diseaseByDay.keys)
            ..addAll(healthyByDay.keys);
      final labels = keys.toList()..sort();
      final totals =
          diseaseDayCounts.entries
              .map(
                (e) => MapEntry(
                  e.key,
                  e.value.values.fold<int>(0, (s, v) => s + v),
                ),
              )
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      final top = totals.take(4).map((e) => e.key).toList();

      final Map<String, List<double>> series = {};
      for (final name in top) {
        final perDay = diseaseDayCounts[name] ?? const <String, int>{};
        final s = <double>[];
        for (final k in labels) {
          final dCount =
              (perDay[k] ?? 0).toDouble(); // This specific disease count
          final allDiseasesCount =
              (diseaseByDay[k] ?? 0).toDouble(); // ALL diseases for that day
          final hCount = (healthyByDay[k] ?? 0).toDouble();
          final totalScans =
              allDiseasesCount + hCount; // Total scans = all diseases + healthy
          s.add(totalScans > 0 ? (dCount / totalScans) * 100.0 : 0.0);
        }
        series[name] = s;
      }

      // Healthy series (% healthy per day)
      final healthySeries = <double>[];
      for (final k in labels) {
        final d = (diseaseByDay[k] ?? 0).toDouble();
        final h = (healthyByDay[k] ?? 0).toDouble();
        final t = d + h;
        healthySeries.add(t > 0 ? (h / t) * 100.0 : 0.0);
      }

      final bool computedEmpty = labels.isEmpty || series.isEmpty;
      if (computedEmpty) {
        // Delay declaring empty a bit to avoid flicker right after loading
        _trendEmptyGuardTimer = Timer(const Duration(milliseconds: 7500), () {
          if (!mounted) return;
          setState(() {
            _trendLabels = labels;
            _seriesByDisease = series;
            _topDiseasesOrder = top;
            _healthySeries = healthySeries;
            _trendIsEmpty = true;
            _loadingTrend = false;
            _trendLoaded = true;
          });
        });
      } else {
        setState(() {
          _trendLabels = labels;
          _seriesByDisease = series;
          _topDiseasesOrder = top;
          _healthySeries = healthySeries;
          _trendIsEmpty = false;
          _loadingTrend = false;
          _trendLoaded = true;
        });
      }
    } catch (e) {
      setState(() {
        _trendError = e.toString();
        _loadingTrend = false;
        _trendLoaded = true;
        // keep _trendIsEmpty as-is
      });
    }
  }

  Widget _buildTrendLine() {
    // Treat view as loading until a load cycle fully completes
    if (_loadingTrend || !_trendLoaded) {
      return _buildLoading('Loading data…');
    }
    if (_trendError != null) {
      return Center(child: Text('Failed to load: $_trendError'));
    }
    // Only show "No data" after load completed and confirmed empty
    if (_trendIsEmpty) {
      return const Center(child: Text('No data available for this range.'));
    }
    // Downsample labels to ~8 ticks like the PDF
    List<String> _downsample(List<String> sorted) {
      if (sorted.length <= 8) return sorted;
      final step = (sorted.length / 8).ceil();
      final out = <String>[];
      for (int i = 0; i < sorted.length; i += step) {
        out.add(sorted[i]);
      }
      if (out.last != sorted.last) out.add(sorted.last);
      return out;
    }

    final displayKeys = _downsample(_trendLabels);
    final keyIndex = {
      for (int i = 0; i < _trendLabels.length; i++) _trendLabels[i]: i,
    };

    final datasets = <LineChartBarData>[];
    final legendItems = <Map<String, dynamic>>[]; // {name,color}
    final seriesLabels = <String>[]; // parallel to datasets order
    for (final name in _topDiseasesOrder) {
      final values = _seriesByDisease[name] ?? const <double>[];
      final spots = <FlSpot>[];
      for (final k in displayKeys) {
        final i = keyIndex[k] ?? 0;
        final v =
            (i >= 0 && i < values.length)
                ? (values[i].isFinite ? values[i] : 0.0)
                : 0.0;
        spots.add(FlSpot(spots.length.toDouble(), v));
      }
      final color = _getDiseaseColor(name);
      datasets.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 3,
          dotData: FlDotData(show: false),
        ),
      );
      legendItems.add({'name': name, 'color': color});
      seriesLabels.add(name);
    }

    // Healthy line
    if (_healthySeries.isNotEmpty) {
      final spots = <FlSpot>[];
      for (final k in displayKeys) {
        final i = keyIndex[k] ?? 0;
        final v =
            (i >= 0 && i < _healthySeries.length)
                ? (_healthySeries[i].isFinite ? _healthySeries[i] : 0.0)
                : 0.0;
        spots.add(FlSpot(spots.length.toDouble(), v));
      }
      datasets.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: const Color.fromARGB(255, 2, 119, 252), // Healthy blue
          barWidth: 3,
          dotData: FlDotData(show: false),
        ),
      );
      legendItems.add({
        'name': 'Healthy',
        'color': const Color.fromARGB(255, 2, 119, 252),
      });
      seriesLabels.add('Healthy');
    }
    // Limit bottom axis labels to at most 10 by stepping
    final int labelStep =
        displayKeys.length <= 10 ? 1 : (displayKeys.length / 10).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLegend(legendItems),
        const SizedBox(height: 8),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: displayKeys.isNotEmpty ? displayKeys.length - 1.0 : 0,
              minY: -15,
              maxY: 115,
              gridData: FlGridData(show: true, drawVerticalLine: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: const Color.fromARGB(255, 193, 221, 240),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final label =
                          (spot.barIndex >= 0 &&
                                  spot.barIndex < seriesLabels.length)
                              ? seriesLabels[spot.barIndex]
                              : '';
                      final valueStr = '${spot.y.toStringAsFixed(1)}%';
                      final Color seriesColor =
                          (spot.barIndex >= 0 &&
                                  spot.barIndex < datasets.length)
                              ? (datasets[spot.barIndex].color ?? Colors.white)
                              : Colors.white;
                      return LineTooltipItem(
                        '$label ($valueStr)',
                        TextStyle(
                          color: seriesColor,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: labelStep.toDouble(),
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= displayKeys.length)
                        return const SizedBox.shrink();
                      if (i % labelStep != 0) return const SizedBox.shrink();
                      final date = displayKeys[i];
                      // Reuse month/day label like bar labels used elsewhere
                      final parts = date.split('-');
                      final label =
                          parts.length > 2 ? '${parts[1]}/${parts[2]}' : date;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          label,
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: 25,
                    getTitlesWidget: (v, m) {
                      // Show 0%, 25%, 50%, 75%, 100% labels
                      if (v == 0) return const Text('0%');
                      if (v == 25) return const Text('25%');
                      if (v == 50) return const Text('50%');
                      if (v == 75) return const Text('75%');
                      if (v == 100) return const Text('100%');
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              lineBarsData: datasets,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegend(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children:
          items.map((e) {
            final Color c = e['color'] as Color;
            final String name = e['name'] as String;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }).toList(),
    );
  }

  List<Map<String, dynamic>> _aggregateFromSnapshot(
    dynamic source,
    String selectedRange,
  ) {
    // source can be a QuerySnapshot or a List<Map<String,dynamic>>
    final range = _resolveDateRange(selectedRange);
    final DateTime start = range.start;
    final DateTime end = range.end;

    final Map<String, int> diseaseToCount = {};
    int healthyCount = 0;

    final Iterable<Map<String, dynamic>> docs =
        source is QuerySnapshot
            ? source.docs.map(
              (d) => (d.data() as Map<String, dynamic>?) ?? const {},
            )
            : (source is List<Map<String, dynamic>> ? source : const []);

    for (final data in docs) {
      if (data.isEmpty) continue;

      // Only include expert-reviewed (completed) and anchor to createdAt (when disease occurred)
      final String status = (data['status'] ?? '').toString();
      if (status != 'completed') continue;
      final dynamic createdAtRaw = data['submittedAt'] ?? data['createdAt'];
      DateTime? created;
      if (createdAtRaw is Timestamp) {
        created = createdAtRaw.toDate();
      } else if (createdAtRaw is String) {
        created = DateTime.tryParse(createdAtRaw);
      }
      if (created == null) continue;
      if (created.isBefore(start) || !created.isBefore(end)) continue;

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
              children: [
                Text(
                  _chartMode == 'line' ? 'Trend' : 'Distribution',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
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
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButton<String>(
                    value: _chartMode,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: 'bar',
                        child: Text('Distribution (Bar)'),
                      ),
                      DropdownMenuItem(
                        value: 'line',
                        child: Text('Trend (Line)'),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() {
                        _chartMode = v;
                        if (v == 'line') {
                          // Only set loading if we don't have data yet
                          if (_seriesByDisease.isEmpty) {
                            _loadingTrend = true;
                            _trendLoaded = false;
                            _trendIsEmpty = false;
                          }
                        }
                      });
                      if (v == 'line' && _seriesByDisease.isEmpty) {
                        _loadTrend();
                      }
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('chart_mode_distribution', v);
                      } catch (_) {}
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Disease Distribution Chart or Trend Line
            Container(
              height: widget.height ?? 400,
              width: double.infinity,
              child:
                  _chartMode == 'line'
                      ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildTrendLine(),
                      )
                      : Row(
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
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
                                        (diseaseData.isEmpty &&
                                                _lastSnapshot == null)
                                            ? _buildLoading('Loading data…')
                                            : diseaseData.isEmpty
                                            ? const Center(
                                              child: Text(
                                                'No disease data available',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            )
                                            : Builder(
                                              builder: (context) {
                                                // Sort diseases by count ascending so it reads left → right (low → high)
                                                final List<Map<String, dynamic>>
                                                sortedDiseases = [
                                                  ...diseaseData,
                                                ]..sort(
                                                  (a, b) => (a['count'] as int)
                                                      .compareTo(
                                                        b['count'] as int,
                                                      ),
                                                );
                                                return BarChart(
                                                  BarChartData(
                                                    alignment:
                                                        BarChartAlignment
                                                            .spaceAround,
                                                    maxY:
                                                        sortedDiseases.isEmpty
                                                            ? 100.0
                                                            : sortedDiseases
                                                                    .map(
                                                                      (d) =>
                                                                          d['count']
                                                                              .toDouble(),
                                                                    )
                                                                    .reduce(
                                                                      (a, b) =>
                                                                          a > b
                                                                              ? a
                                                                              : b,
                                                                    ) *
                                                                1.2,
                                                    barTouchData: BarTouchData(
                                                      enabled: true,
                                                      touchTooltipData: BarTouchTooltipData(
                                                        tooltipBgColor:
                                                            Colors.blueGrey,
                                                        getTooltipItem: (
                                                          group,
                                                          groupIndex,
                                                          rod,
                                                          rodIndex,
                                                        ) {
                                                          if (groupIndex < 0 ||
                                                              groupIndex >=
                                                                  sortedDiseases
                                                                      .length ||
                                                              sortedDiseases
                                                                  .isEmpty) {
                                                            return null;
                                                          }
                                                          final disease =
                                                              sortedDiseases[groupIndex];
                                                          return BarTooltipItem(
                                                            '${disease['name']}\n${disease['count']} cases\n${(disease['percentage'] * 100).toStringAsFixed(1)}%',
                                                            const TextStyle(
                                                              color:
                                                                  Colors.white,
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
                                                          getTitlesWidget: (
                                                            value,
                                                            meta,
                                                          ) {
                                                            if (value < 0 ||
                                                                value >=
                                                                    sortedDiseases
                                                                        .length ||
                                                                sortedDiseases
                                                                    .isEmpty) {
                                                              return const SizedBox.shrink();
                                                            }
                                                            final disease =
                                                                sortedDiseases[value
                                                                    .toInt()];
                                                            return Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    top: 8.0,
                                                                  ),
                                                              child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  Text(
                                                                    disease['name'],
                                                                    style: TextStyle(
                                                                      color: _getDiseaseColor(
                                                                        disease['name'],
                                                                      ),
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontSize:
                                                                          14,
                                                                    ),
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 6,
                                                                  ),
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          2,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: _getDiseaseColor(
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
                                                                        color: _getDiseaseColor(
                                                                          disease['name'],
                                                                        ),
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                        fontSize:
                                                                            12,
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
                                                                final double
                                                                chartMaxY =
                                                                    sortedDiseases
                                                                            .isEmpty
                                                                        ? 100.0
                                                                        : sortedDiseases
                                                                                .map(
                                                                                  (
                                                                                    d,
                                                                                  ) =>
                                                                                      (d['count']
                                                                                              as num)
                                                                                          .toDouble(),
                                                                                )
                                                                                .reduce(
                                                                                  (
                                                                                    a,
                                                                                    b,
                                                                                  ) =>
                                                                                      a >
                                                                                              b
                                                                                          ? a
                                                                                          : b,
                                                                                ) *
                                                                            1.2;

                                                                // Calculate interval based on chart's actual maxY
                                                                if (chartMaxY <=
                                                                    12)
                                                                  return 2.0;
                                                                if (chartMaxY <=
                                                                    24)
                                                                  return 5.0;
                                                                if (chartMaxY <=
                                                                    60)
                                                                  return 10.0;
                                                                if (chartMaxY <=
                                                                    120)
                                                                  return 25.0;
                                                                if (chartMaxY <=
                                                                    240)
                                                                  return 50.0;
                                                                if (chartMaxY <=
                                                                    600)
                                                                  return 100.0;
                                                                if (chartMaxY <=
                                                                    1200)
                                                                  return 200.0;
                                                                if (chartMaxY <=
                                                                    2400)
                                                                  return 500.0;
                                                                if (chartMaxY <=
                                                                    6000)
                                                                  return 1000.0;
                                                                if (chartMaxY <=
                                                                    12000)
                                                                  return 2000.0;
                                                                if (chartMaxY <=
                                                                    24000)
                                                                  return 5000.0;
                                                                if (chartMaxY <=
                                                                    60000)
                                                                  return 10000.0;
                                                                // For extremely large numbers, use dynamic calculation
                                                                return (chartMaxY /
                                                                        5)
                                                                    .ceilToDouble();
                                                              })(),
                                                          getTitlesWidget: (
                                                            value,
                                                            meta,
                                                          ) {
                                                            return Text(
                                                              value
                                                                  .toInt()
                                                                  .toString(),
                                                              style: TextStyle(
                                                                color:
                                                                    Colors
                                                                        .grey[600],
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
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
                                                    borderData: FlBorderData(
                                                      show: false,
                                                    ),
                                                    gridData: FlGridData(
                                                      show: true,
                                                      drawVerticalLine: false,
                                                      horizontalInterval:
                                                          (() {
                                                            final double
                                                            maxVal =
                                                                sortedDiseases
                                                                        .isEmpty
                                                                    ? 100
                                                                    : sortedDiseases
                                                                        .map(
                                                                          (d) =>
                                                                              (d['count']
                                                                                      as num)
                                                                                  .toDouble(),
                                                                        )
                                                                        .reduce(
                                                                          (
                                                                            a,
                                                                            b,
                                                                          ) =>
                                                                              a > b
                                                                                  ? a
                                                                                  : b,
                                                                        );
                                                            if (maxVal <= 10)
                                                              return 2.0;
                                                            if (maxVal <= 20)
                                                              return 5.0;
                                                            if (maxVal <= 50)
                                                              return 10.0;
                                                            return 20.0;
                                                          })(),
                                                      getDrawingHorizontalLine: (
                                                        value,
                                                      ) {
                                                        return FlLine(
                                                          color:
                                                              Colors.grey[200],
                                                          strokeWidth: 1,
                                                        );
                                                      },
                                                    ),
                                                    barGroups:
                                                        sortedDiseases.isEmpty
                                                            ? []
                                                            : sortedDiseases.asMap().entries.map((
                                                              entry,
                                                            ) {
                                                              final index =
                                                                  entry.key;
                                                              final disease =
                                                                  entry.value;
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
                                                                          top: Radius.circular(
                                                                            8,
                                                                          ),
                                                                        ),
                                                                  ),
                                                                ],
                                                              );
                                                            }).toList(),
                                                  ),
                                                  swapAnimationDuration:
                                                      Duration(milliseconds: 0),
                                                  swapAnimationCurve:
                                                      Curves.linear,
                                                );
                                              },
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
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
                                                    BarChartAlignment
                                                        .spaceAround,
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
                                                                      a > b
                                                                          ? a
                                                                          : b,
                                                                ) *
                                                            1.2,
                                                barTouchData: BarTouchData(
                                                  enabled: true,
                                                  touchTooltipData: BarTouchTooltipData(
                                                    tooltipBgColor:
                                                        Colors.blueGrey,
                                                    getTooltipItem: (
                                                      group,
                                                      groupIndex,
                                                      rod,
                                                      rodIndex,
                                                    ) {
                                                      if (groupIndex < 0 ||
                                                          groupIndex >=
                                                              healthyData
                                                                  .length ||
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
                                                      getTitlesWidget: (
                                                        value,
                                                        meta,
                                                      ) {
                                                        if (value < 0 ||
                                                            value >=
                                                                healthyData
                                                                    .length ||
                                                            healthyData
                                                                .isEmpty) {
                                                          return const SizedBox.shrink();
                                                        }
                                                        final disease =
                                                            healthyData[value
                                                                .toInt()];
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 8.0,
                                                              ),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Text(
                                                                disease['name'],
                                                                style: TextStyle(
                                                                  color: _getDiseaseColor(
                                                                    disease['name'],
                                                                  ),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize: 14,
                                                                ),
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                              ),
                                                              const SizedBox(
                                                                height: 6,
                                                              ),
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          2,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: _getDiseaseColor(
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
                                                                    color: _getDiseaseColor(
                                                                      disease['name'],
                                                                    ),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                    fontSize:
                                                                        12,
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
                                                            final double
                                                            chartMaxY =
                                                                healthyData
                                                                        .isEmpty
                                                                    ? 100.0
                                                                    : healthyData
                                                                            .map(
                                                                              (
                                                                                d,
                                                                              ) =>
                                                                                  (d['count']
                                                                                          as num)
                                                                                      .toDouble(),
                                                                            )
                                                                            .reduce((a, b) => a > b ? a : b) *
                                                                        1.2;

                                                            // Calculate interval based on chart's actual maxY
                                                            if (chartMaxY <= 12)
                                                              return 2.0;
                                                            if (chartMaxY <= 24)
                                                              return 5.0;
                                                            if (chartMaxY <= 60)
                                                              return 10.0;
                                                            if (chartMaxY <=
                                                                120)
                                                              return 25.0;
                                                            if (chartMaxY <=
                                                                240)
                                                              return 50.0;
                                                            if (chartMaxY <=
                                                                600)
                                                              return 100.0;
                                                            if (chartMaxY <=
                                                                1200)
                                                              return 200.0;
                                                            if (chartMaxY <=
                                                                2400)
                                                              return 500.0;
                                                            if (chartMaxY <=
                                                                6000)
                                                              return 1000.0;
                                                            if (chartMaxY <=
                                                                12000)
                                                              return 2000.0;
                                                            if (chartMaxY <=
                                                                24000)
                                                              return 5000.0;
                                                            if (chartMaxY <=
                                                                60000)
                                                              return 10000.0;
                                                            // For extremely large numbers, use dynamic calculation
                                                            return (chartMaxY /
                                                                    5)
                                                                .ceilToDouble();
                                                          })(),
                                                      getTitlesWidget: (
                                                        value,
                                                        meta,
                                                      ) {
                                                        return Text(
                                                          value
                                                              .toInt()
                                                              .toString(),
                                                          style: TextStyle(
                                                            color:
                                                                Colors
                                                                    .grey[600],
                                                            fontWeight:
                                                                FontWeight.w500,
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
                                                borderData: FlBorderData(
                                                  show: false,
                                                ),
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
                                                                          a > b
                                                                              ? a
                                                                              : b,
                                                                    );
                                                        if (maxVal <= 10)
                                                          return 2.0;
                                                        if (maxVal <= 20)
                                                          return 5.0;
                                                        if (maxVal <= 50)
                                                          return 10.0;
                                                        return 20.0;
                                                      })(),
                                                  getDrawingHorizontalLine: (
                                                    value,
                                                  ) {
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
                                                          final index =
                                                              entry.key;
                                                          final disease =
                                                              entry.value;
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

  Widget _buildLoading(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.grey)),
        ],
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
  String _chartMode = 'bar'; // 'bar' | 'line'

  @override
  void initState() {
    super.initState();
    _loadTrend();
    // Load persisted chart mode to keep in sync with Reports/Dashboard
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('chart_mode_distribution');
        if (saved == 'bar' || saved == 'line') {
          if (mounted) setState(() => _chartMode = saved!);
        }
      } catch (_) {}
    }();
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
                    // Chart mode selector
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButton<String>(
                        value: _chartMode,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                            value: 'bar',
                            child: Text('Distribution (Bar)'),
                          ),
                          DropdownMenuItem(
                            value: 'line',
                            child: Text('Trend (Line)'),
                          ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() {
                            _chartMode = v;
                          });
                          try {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('chart_mode_distribution', v);
                          } catch (_) {}
                        },
                      ),
                    ),
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
                    _chartMode == 'bar'
                        ? (isManyBars
                            ? SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: chartWidth,
                                child: _buildBarChart(
                                  key: ValueKey(_selectedTimeRange),
                                ),
                              ),
                            )
                            : _buildBarChart(key: ValueKey(_selectedTimeRange)))
                        : _buildLineChartFromAggregated(
                          key: ValueKey('line_${_selectedTimeRange}'),
                        ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart({Key? key}) {
    // Debug print to trace data
    // debug logs removed
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

  // Simple line chart based on the same aggregated data used by the bar chart
  Widget _buildLineChartFromAggregated({Key? key}) {
    if (_aggregatedData.isEmpty) {
      return const Center(child: Text('No data available for this range.'));
    }

    final List<FlSpot> spots = [];
    for (int i = 0; i < _aggregatedData.length; i++) {
      final y = (_aggregatedData[i]['count'] as num).toDouble();
      spots.add(FlSpot(i.toDouble(), y));
    }

    final maxY = spots.map((e) => e.y).fold<double>(0, (a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: spots.isNotEmpty ? spots.length - 1.0 : 0,
        minY: 0,
        maxY: maxY * 1.2,
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval:
                  (() {
                    final len = _aggregatedData.length;
                    return (len <= 10 ? 1 : (len / 10).ceil()).toDouble();
                  })(),
              getTitlesWidget: (value, meta) {
                final int idx = value.round();
                if (idx < 0 || idx >= _aggregatedData.length)
                  return const SizedBox.shrink();
                final step =
                    _aggregatedData.length <= 10
                        ? 1
                        : (_aggregatedData.length / 10).ceil();
                if (idx % step != 0) return const SizedBox.shrink();
                final date = _aggregatedData[idx]['date'];
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _barLabel(idx, date),
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF2D7204),
            barWidth: 3,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
      key: key,
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
  final String selectedTimeRange;
  const AvgResponseTimeModal({
    Key? key,
    required this.scanRequests,
    required this.selectedTimeRange,
  }) : super(key: key);

  @override
  State<AvgResponseTimeModal> createState() => _AvgResponseTimeModalState();
}

class _AvgResponseTimeModalState extends State<AvgResponseTimeModal> {
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
    // debug log removed
    _loadExpertStats();
  }

  Future<void> _loadExpertStats() async {
    setState(() {
      _loading = true;
    });
    final scanRequests = widget.scanRequests;
    final selectedRange = widget.selectedTimeRange;
    // Build reviewedAt-anchored window
    final DateTime now = DateTime.now();
    DateTime? startInclusive;
    DateTime? endExclusive;
    if (selectedRange.startsWith('Custom (') ||
        selectedRange.startsWith('Monthly (')) {
      final regex = RegExp(
        r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(selectedRange);
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
      switch (selectedRange) {
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
      } else {
        reviewed = DateTime.tryParse(reviewedRaw) ?? DateTime.now();
      }
      // Filter by reviewedAt window
      bool inWindow;
      if (selectedRange == '1 Day') {
        inWindow = reviewed.isAfter(startInclusive);
      } else if (selectedRange.startsWith('Custom (') ||
          selectedRange.startsWith('Monthly (')) {
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
    // debug log removed

    // Fetch expert data from Firestore (experts are stored in users collection with role='expert')
    final Map<String, Map<String, dynamic>> experts = {};
    if (expertGroups.isNotEmpty) {
      try {
        final expertIds = expertGroups.keys.toList();

        // Handle case where we have more than 10 experts (Firestore whereIn limit)
        if (expertIds.length <= 10) {
          final QuerySnapshot expertSnapshot =
              await FirebaseFirestore.instance
                  .collection('users')
                  .where(FieldPath.documentId, whereIn: expertIds)
                  .where('role', isEqualTo: 'expert')
                  .get();

          for (final doc in expertSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            experts[doc.id] = data;
          }
        } else {
          // If more than 10 experts, fetch all experts and filter
          final QuerySnapshot allExpertsSnapshot =
              await FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'expert')
                  .get();

          for (final doc in allExpertsSnapshot.docs) {
            if (expertIds.contains(doc.id)) {
              final data = doc.data() as Map<String, dynamic>;
              experts[doc.id] = data;
            }
          }
        }
      } catch (e) {
        print('Error fetching expert data: $e');
        // Continue with empty experts map if fetch fails
      }
    }

    final List<_ExpertResponseStats> stats = [];
    int grandTotalSeconds = 0;
    int grandCompletedCount = 0;
    for (final entry in expertGroups.entries) {
      final expertId = entry.key;
      final requests = entry.value;
      final times = <double>[];
      int totalSeconds = 0;

      // Initialize distribution buckets
      final Map<String, int> distribution = {
        '0-6h': 0,
        '6-12h': 0,
        '12-24h': 0,
        '24-48h': 0,
        '>48h': 0,
      };

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
        final hours = seconds / 3600.0;
        totalSeconds += seconds;
        times.add(seconds.toDouble());

        // Categorize into distribution buckets
        if (hours <= 6) {
          distribution['0-6h'] = distribution['0-6h']! + 1;
        } else if (hours <= 12) {
          distribution['6-12h'] = distribution['6-12h']! + 1;
        } else if (hours <= 24) {
          distribution['12-24h'] = distribution['12-24h']! + 1;
        } else if (hours <= 48) {
          distribution['24-48h'] = distribution['24-48h']! + 1;
        } else {
          distribution['>48h'] = distribution['>48h']! + 1;
        }
      }
      final avgSeconds = requests.isEmpty ? 0 : totalSeconds ~/ requests.length;
      grandTotalSeconds += totalSeconds;
      grandCompletedCount += requests.length;
      final expert = experts[expertId];
      final firstReq = requests.isNotEmpty ? requests.first : null;
      final avatarUrl = expert?['imageProfile'] ?? '';
      stats.add(
        _ExpertResponseStats(
          expertId: expertId,
          name:
              expert?['fullName'] ??
              (firstReq?['expertReview']?['expertName'] ??
                  firstReq?['expertName'] ??
                  'Unknown'),
          avatar: avatarUrl,
          avgSeconds: avgSeconds,
          trend: times,
          count: requests.length,
          distribution: distribution,
        ),
      );
    }
    // debug log removed
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
    final selectedRange = widget.selectedTimeRange;
    // debug log removed
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 750,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Container(
          width:
              MediaQuery.of(context).size.width > 800
                  ? 750
                  : MediaQuery.of(context).size.width * 0.9,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fixed header with close button
              Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Average Response Time (per Expert)',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Time Range: ${_displayRangeLabel(selectedRange)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                    DataColumn(
                                      label: Text('Avg. Response Time'),
                                    ),
                                    DataColumn(label: Text('Reports')),
                                    DataColumn(label: Text('Distribution')),
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
                                                            (e
                                                                    .avatar
                                                                    .isNotEmpty)
                                                                ? NetworkImage(
                                                                  e.avatar,
                                                                )
                                                                : null,
                                                        child:
                                                            (e.avatar.isEmpty)
                                                                ? const Icon(
                                                                  Icons.person,
                                                                )
                                                                : null,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(e.name),
                                                    ],
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    _formatDuration(
                                                      e.avgSeconds,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(e.count.toString()),
                                                ),
                                                DataCell(
                                                  SizedBox(
                                                    width: 120,
                                                    height: 28,
                                                    child:
                                                        e.count > 0
                                                            ? _buildDistributionBar(
                                                              e.distribution,
                                                              e.count,
                                                            )
                                                            : const Text('-'),
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
                    ],
                  ),
                ),
              ),
              // Overall weighted summary at the bottom
              if (_totalCompletedReports > 0)
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      () {
                        final label = _displayRangeLabel(selectedRange);
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDistributionBar(Map<String, int> distribution, int total) {
    final List<MapEntry<String, int>> buckets = [
      MapEntry('0-6h', distribution['0-6h'] ?? 0),
      MapEntry('6-12h', distribution['6-12h'] ?? 0),
      MapEntry('12-24h', distribution['12-24h'] ?? 0),
      MapEntry('24-48h', distribution['24-48h'] ?? 0),
      MapEntry('>48h', distribution['>48h'] ?? 0),
    ];

    final List<Color> colors = [
      Colors.green,
      Colors.lightGreen,
      Colors.orange,
      Colors.deepOrange,
      Colors.red,
    ];

    final List<String> labels = [
      ' 0-6h',
      ' 6-12h',
      ' 12-24h',
      ' 24-48h',
      ' >48h',
    ];

    // Build tooltip content with breakdown
    final tooltipContent = buckets
        .asMap()
        .entries
        .map((entry) {
          final idx = entry.key;
          final bucket = entry.value;
          final count = bucket.value;
          final percentage = total == 0 ? 0.0 : (count / total * 100);
          return '${labels[idx]}: $count (${percentage.toStringAsFixed(1)}%)';
        })
        .join('\n');

    return Tooltip(
      message: tooltipContent,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontSize: 12,
        color: Colors.white,
        height: 1.5,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 16,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Row(
                  children: List.generate(buckets.length, (index) {
                    final percentage =
                        total == 0 ? 0.0 : (buckets[index].value / total);
                    if (percentage == 0) return const SizedBox.shrink();
                    return Expanded(
                      flex: (percentage * 1000).toInt(),
                      child: Container(color: colors[index]),
                    );
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Show dominant category icon
          _buildDominantIcon(buckets, colors),
        ],
      ),
    );
  }

  Widget _buildDominantIcon(
    List<MapEntry<String, int>> buckets,
    List<Color> colors,
  ) {
    // Find the dominant category
    int maxCount = 0;
    int dominantIndex = 0;
    for (int i = 0; i < buckets.length; i++) {
      if (buckets[i].value > maxCount) {
        maxCount = buckets[i].value;
        dominantIndex = i;
      }
    }

    final List<IconData> icons = [
      Icons.bolt, // 0-6h (Excellent)
      Icons.check_circle, // 6-12h (Good)
      Icons.access_time, // 12-24h (Acceptable)
      Icons.warning, // 24-48h (Needs Improvement)
      Icons.error, // >48h (Critical)
    ];

    return Icon(icons[dominantIndex], size: 14, color: colors[dominantIndex]);
  }
}

class _ExpertResponseStats {
  final String expertId;
  final String name;
  final String avatar;
  final int avgSeconds;
  final List<double> trend;
  final int count;
  final Map<String, int> distribution;
  _ExpertResponseStats({
    required this.expertId,
    required this.name,
    required this.avatar,
    required this.avgSeconds,
    required this.trend,
    required this.count,
    required this.distribution,
  });
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
                  // If user selects Monthly, immediately prompt for month/year
                  if (value == 'Monthly…') {
                    final now = DateTime.now();
                    _showMonthYearPicker(
                      context: context,
                      initialDate: _customStart ?? now,
                      firstDate: DateTime(2020),
                      lastDate: now,
                    ).then((picked) {
                      if (picked != null) {
                        final firstDay = DateTime(picked.year, picked.month, 1);
                        final lastDay = DateTime(
                          picked.year,
                          picked.month + 1,
                          0,
                        );
                        setState(() {
                          _customStart = firstDay;
                          _customEnd = lastDay;
                        });
                      }
                    });
                  }
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
              if (_customStart == null || _customEnd == null) {
                showDialog(
                  context: context,
                  builder:
                      (ctx) => AlertDialog(
                        title: const Text('Month required'),
                        content: const Text(
                          'Please choose a month to generate a Monthly report.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                );
                return;
              }
              final start = _customStart!;
              final end = _customEnd!;
              final startStr = start.toIso8601String().substring(0, 10);
              final endStr = end.toIso8601String().substring(0, 10);
              range = 'Monthly ($startStr to $endStr)';
            } else if (_selectedRange == 'Custom…') {
              if (_customStart == null || _customEnd == null) {
                showDialog(
                  context: context,
                  builder:
                      (ctx) => AlertDialog(
                        title: const Text('Date range required'),
                        content: const Text(
                          'Please choose a start and end date to generate a Custom report.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                );
                return;
              }
              final start = _customStart!;
              final end = _customEnd!;
              final startStr = start.toIso8601String().substring(0, 10);
              final endStr = end.toIso8601String().substring(0, 10);
              range = 'Custom ($startStr to $endStr)';
            }

            // Show confirmation dialog before generating PDF
            _showConfirmationDialog(context, range);
          },
        ),
      ],
    );
  }

  String _formatRangeForDisplay(String range) {
    // Check if it's a Monthly range
    if (range.startsWith('Monthly (')) {
      final regex = RegExp(
        r'Monthly \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        final startDate = DateTime.parse(match.group(1)!);
        // Format as "August 2025" for monthly reports
        return _formatMonthYear(startDate);
      }
    }
    // Check if it's a Custom range
    if (range.startsWith('Custom (')) {
      final regex = RegExp(
        r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(range);
      if (match != null) {
        final startDate = DateTime.parse(match.group(1)!);
        final endDate = DateTime.parse(match.group(2)!);
        return _formatDateRange(startDate, endDate);
      }
    }
    // For preset ranges like "Last 7 Days", return as is
    return range;
  }

  void _showConfirmationDialog(BuildContext context, String range) {
    final displayRange = _formatRangeForDisplay(range);

    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D7204),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.preview,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Report Preview',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Period Info
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  color: Color(0xFF2D7204),
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        range.startsWith('Monthly')
                                            ? 'Report Period: Monthly'
                                            : 'Report Period',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        displayRange,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          color: Color(0xFF2D7204),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Report Contents Section
                          const Text(
                            'Report Contents',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildPreviewSection(
                            icon: Icons.pie_chart,
                            title: 'Disease Distribution',
                            description:
                                'Breakdown of all detected diseases with percentages and visual charts.',
                            color: Colors.blue,
                          ),
                          const SizedBox(height: 10),
                          _buildPreviewSection(
                            icon: Icons.show_chart,
                            title: 'Health Trends',
                            description:
                                'Daily trends showing healthy vs diseased plant percentages over time.',
                            color: Colors.green,
                          ),
                          const SizedBox(height: 10),
                          _buildPreviewSection(
                            icon: Icons.thermostat,
                            title: 'Weather Summary',
                            description:
                                'Average temperature data for the selected period.',
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 10),
                          _buildPreviewSection(
                            icon: Icons.analytics,
                            title: 'Key Statistics',
                            description:
                                'Total scans, detection counts, and summary metrics.',
                            color: Colors.purple,
                          ),
                          const SizedBox(height: 20),
                          // Format Info
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.description,
                                  size: 20,
                                  color: Colors.grey[700],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Ready for download and print',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Footer Actions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 15, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf, size: 20),
                          label: const Text('Generate PDF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2D7204),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop(); // Close preview dialog
                            Navigator.pop(context, {
                              'range': range,
                              'pageSize': 'A4',
                            }); // Close main dialog and return result
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildPreviewSection({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, color: Colors.green[400], size: 20),
        ],
      ),
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
