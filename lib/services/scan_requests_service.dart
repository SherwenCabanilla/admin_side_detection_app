import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/foundation.dart';
import 'dart:async';

class ScanRequestsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Cache and throttle to avoid repeated reads and rebuilds
  static List<Map<String, dynamic>>? _cachedRequests;
  static DateTime? _cachedAt;
  static Future<List<Map<String, dynamic>>>? _inflight;
  static const Duration _cacheTtl = Duration(seconds: 20);

  // Fetch all scan requests from Firestore
  static Future<List<Map<String, dynamic>>> getScanRequests() async {
    // Serve from cache if fresh
    if (_cachedRequests != null && _cachedAt != null) {
      if (DateTime.now().difference(_cachedAt!) < _cacheTtl) {
        return _cachedRequests!;
      }
    }

    // If already fetching, await the same future
    if (_inflight != null) return await _inflight!;

    _inflight = _fetchScanRequests();
    try {
      final result = await _inflight!;
      _cachedRequests = result;
      _cachedAt = DateTime.now();
      return result;
    } finally {
      _inflight = null;
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchScanRequests() async {
    try {
      final QuerySnapshot snapshot =
          await _firestore.collection('scan_requests').get();
      // debugPrint('Found ${snapshot.docs.length} scan requests');

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        // debugPrint(
        //   'Document ${doc.id} data: $data',
        // ); // Debug: Print each document

        return {
          'id': doc.id,
          'userId': data['userId'] ?? '',
          'userName': data['userName'] ?? '',
          'status': data['status'] ?? 'pending',
          'createdAt':
              data['submittedAt'] ??
              data['createdAt'], // Use submittedAt as primary, createdAt as fallback
          'reviewedAt': data['reviewedAt'],
          'images': data['images'] ?? [],
          'diseaseSummary': data['diseaseSummary'] ?? [],
          'expertReview': data['expertReview'],
        };
      }).toList();
    } catch (e) {
      // debugPrint('Error fetching scan requests: $e');
      return [];
    }
  }

  // Force a fresh read and update cache immediately
  static Future<List<Map<String, dynamic>>> refreshScanRequests() async {
    _cachedAt = null;
    _cachedRequests = null;
    return await getScanRequests();
  }

  // Get disease statistics for a specific time range
  // Uses createdAt (when disease occurred) but only includes completed/validated scans
  static Future<List<Map<String, dynamic>>> getDiseaseStats({
    required String timeRange,
  }) async {
    try {
      final scanRequests = await getScanRequests();
      // debugPrint('Total scan requests: ${scanRequests.length}');

      // Filter by createdAt window and include only completed (validated) scans
      final DateTime now = DateTime.now();
      DateTime? startInclusive;
      DateTime? endExclusive;
      if (timeRange.startsWith('Custom (') ||
          timeRange.startsWith('Monthly (')) {
        final regex = RegExp(
          r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
        );
        final match = regex.firstMatch(timeRange);
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
        switch (timeRange) {
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

      final filteredRequests = <Map<String, dynamic>>[];
      for (final r in scanRequests) {
        // Only include completed (expert-validated) scans
        if ((r['status'] ?? '') != 'completed') continue;
        final createdAt = r['createdAt'];
        if (createdAt == null) continue;
        DateTime? created;
        if (createdAt is Timestamp) created = createdAt.toDate();
        if (createdAt is String) created = DateTime.tryParse(createdAt);
        if (created == null) continue;
        final inWindow =
            timeRange == '1 Day'
                ? created.isAfter(startInclusive)
                : (!created.isBefore(startInclusive) &&
                    created.isBefore(endExclusive));
        if (inWindow) filteredRequests.add(r);
      }
      // debugPrint(
      //   'Filtered requests for $timeRange: ${filteredRequests.length}',
      // );

      // Debug: Print details of filtered requests
      // for (final request in filteredRequests) {
      //   debug prints removed
      // }

      // Aggregate disease data
      final Map<String, int> diseaseCounts = {};
      int totalDetections = 0;

      for (final request in filteredRequests) {
        // Try different possible field names for disease data
        List<dynamic> diseaseSummary = [];

        if (request['diseaseSummary'] != null) {
          diseaseSummary = request['diseaseSummary'] as List<dynamic>? ?? [];
        } else if (request['diseases'] != null) {
          diseaseSummary = request['diseases'] as List<dynamic>? ?? [];
        } else if (request['detections'] != null) {
          diseaseSummary = request['detections'] as List<dynamic>? ?? [];
        } else if (request['results'] != null) {
          diseaseSummary = request['results'] as List<dynamic>? ?? [];
        }

        // debugPrint(
        //   'Processing request ${request['id']} with ${diseaseSummary.length} diseases',
        // );
        // debugPrint(
        //   'Disease summary data: $diseaseSummary',
        // ); // Debug: Print disease summary

        for (final disease in diseaseSummary) {
          // debugPrint(
          //   'Processing disease: $disease',
          // ); // Debug: Print each disease

          // Try different possible field names for disease name and count
          String diseaseName = 'Unknown';
          int count = 1; // Default to 1 if no count specified

          if (disease is Map<String, dynamic>) {
            diseaseName =
                disease['name'] ??
                disease['label'] ??
                disease['disease'] ??
                'Unknown';
            count = disease['count'] ?? disease['confidence'] ?? 1;
          } else if (disease is String) {
            diseaseName = disease;
            count = 1;
          }

          // Skip Tip Burn as it's not a disease but a scanning feature
          if (diseaseName.toLowerCase().contains('tip burn') ||
              diseaseName.toLowerCase().contains('unknown')) {
            // debugPrint('Skipping Tip Burn/Unknown: $diseaseName');
            continue;
          }

          diseaseCounts[diseaseName] =
              (diseaseCounts[diseaseName] ?? 0) + count;
          totalDetections += count;
        }
      }

      // debugPrint('Disease counts: $diseaseCounts');
      // debugPrint('Total detections: $totalDetections');

      // Convert to list format with percentages
      final List<Map<String, dynamic>> diseaseStats = [];

      diseaseCounts.forEach((diseaseName, count) {
        final percentage = totalDetections > 0 ? count / totalDetections : 0.0;
        diseaseStats.add({
          'name': diseaseName,
          'count': count,
          'percentage': percentage,
          'type':
              diseaseName.toLowerCase() == 'healthy' ? 'healthy' : 'disease',
        });
      });

      // Do not inject dummy data; return only real disease stats

      // Sort by count (descending)
      diseaseStats.sort(
        (a, b) => (b['count'] as int).compareTo(a['count'] as int),
      );

      // debugPrint('Final disease stats: $diseaseStats');
      return diseaseStats;
    } catch (e) {
      // debugPrint('Error getting disease stats: $e');
      return [];
    }
  }

  // Get reports trend data for a specific time range
  // Uses createdAt (when disease occurred) but only includes completed/validated scans
  static Future<List<Map<String, dynamic>>> getReportsTrend({
    required String timeRange,
  }) async {
    try {
      final scanRequests = await getScanRequests();

      // Filter by createdAt window and include only completed (validated) scans
      final DateTime now = DateTime.now();
      DateTime? startInclusive;
      DateTime? endExclusive;
      if (timeRange.startsWith('Custom (') ||
          timeRange.startsWith('Monthly (')) {
        final regex = RegExp(
          r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
        );
        final match = regex.firstMatch(timeRange);
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
        switch (timeRange) {
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

      final filteredRequests = <Map<String, dynamic>>[];
      for (final r in scanRequests) {
        // Only include completed (expert-validated) scans
        if ((r['status'] ?? '') != 'completed') continue;
        final createdAt = r['createdAt'];
        if (createdAt == null) continue;
        DateTime? created;
        if (createdAt is Timestamp) created = createdAt.toDate();
        if (createdAt is String) created = DateTime.tryParse(createdAt);
        if (created == null) continue;
        final inWindow =
            timeRange == '1 Day'
                ? created.isAfter(startInclusive)
                : (!created.isBefore(startInclusive) &&
                    created.isBefore(endExclusive));
        if (inWindow) filteredRequests.add(r);
      }

      // Group by createdAt date (when disease occurred)
      final Map<String, int> dailyCounts = {};

      for (final request in filteredRequests) {
        final createdAt = request['createdAt'];
        if (createdAt != null) {
          final date = _formatDateForGrouping(createdAt);
          dailyCounts[date] = (dailyCounts[date] ?? 0) + 1;
        }
      }

      // Convert to list format and sort by date
      final List<Map<String, dynamic>> trendData =
          dailyCounts.entries
              .map((entry) => {'date': entry.key, 'count': entry.value})
              .toList();

      trendData.sort((a, b) => a['date'].compareTo(b['date']));

      return trendData;
    } catch (e) {
      // debugPrint('Error getting reports trend: $e');
      return [];
    }
  }

  // Get total reports count
  static Future<int> getTotalReportsCount() async {
    try {
      final QuerySnapshot snapshot =
          await _firestore.collection('scan_requests').get();
      return snapshot.docs.length;
    } catch (e) {
      // debugPrint('Error getting total reports count: $e');
      return 0;
    }
  }

  // Get pending reports count
  static Future<int> getPendingReportsCount() async {
    try {
      final QuerySnapshot snapshot =
          await _firestore
              .collection('scan_requests')
              .where('status', isEqualTo: 'pending')
              .get();
      return snapshot.docs.length;
    } catch (e) {
      // debugPrint('Error getting pending reports count: $e');
      return 0;
    }
  }

  // Get completed reports count
  static Future<int> getCompletedReportsCount() async {
    try {
      final QuerySnapshot snapshot =
          await _firestore
              .collection('scan_requests')
              .where('status', isEqualTo: 'completed')
              .get();
      return snapshot.docs.length;
    } catch (e) {
      // debugPrint('Error getting completed reports count: $e');
      return 0;
    }
  }

  // Helper method to filter requests by time range
  static List<Map<String, dynamic>> filterByTimeRange(
    List<Map<String, dynamic>> requests,
    String timeRange,
  ) {
    final now = DateTime.now();
    DateTime startDate;

    // Handle custom date range and monthly range
    if (timeRange.startsWith('Custom (') || timeRange.startsWith('Monthly (')) {
      // debugPrint('==== FILTERING Custom/Monthly Range ====');
      // debugPrint('Time Range String: $timeRange');
      // Extract dates from "Custom (2025-08-01 to 2025-08-07)" or "Monthly (2025-08-01 to 2025-08-31)"
      final regex = RegExp(
        r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(timeRange);

      if (match != null) {
        final startDateStr = match.group(1)!;
        final endDateStr = match.group(2)!;
        // debugPrint('Extracted Start: $startDateStr, End: $endDateStr');

        final customStartDate = DateTime.parse(startDateStr);
        final customEndDate = DateTime.parse(endDateStr);
        // debugPrint('Parsed Start: $customStartDate, End: $customEndDate');

        // For custom ranges, we'll use the provided dates
        return _filterByCustomDateRange(
          requests,
          customStartDate,
          customEndDate,
        );
      } else {
        // debugPrint('REGEX DID NOT MATCH!');
      }
    }

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
        startDate = now.subtract(const Duration(days: 365));
        break;
      default:
        startDate = now.subtract(const Duration(days: 7));
    }

    // debugPrint('=== TIME RANGE FILTERING DEBUG ===');
    // debugPrint('Time Range: $timeRange');
    // debugPrint('Now: $now');
    // debugPrint('Start Date: $startDate');
    if (timeRange != '1 Day') {
      // debugPrint(
      //   'Effective range: ${startDate.toString().split(' ')[0]} to today (including today)',
      // );
    }
    // debugPrint('Total requests to filter: ${requests.length}');
    // debugPrint('==================================');

    final filteredRequests =
        requests.where((request) {
          final createdAt = request['createdAt'];
          if (createdAt == null) {
            // debugPrint('Request ${request['id']} has no createdAt date');
            return false;
          }

          DateTime requestDate;
          if (createdAt is Timestamp) {
            requestDate = createdAt.toDate();
          } else if (createdAt is String) {
            // Handle ISO string format like "2025-08-01T18:47:52.592255"
            requestDate = DateTime.tryParse(createdAt) ?? DateTime.now();
            // debugPrint('Parsed date from string: $requestDate');
          } else {
            // debugPrint(
            //   'Request ${request['id']} has invalid createdAt format: $createdAt',
            // );
            return false;
          }

          // Define the time range logic:
          // - "1 Day": Only today's scans (last 24 hours)
          // - "Last 7 Days": Scans from 7 days ago up to today (including today)
          // - "Last 30 Days": Scans from 30 days ago up to today (including today)
          // - etc.
          bool isInRange;
          if (timeRange == '1 Day') {
            // For 1 Day: only include scans from the last 24 hours (today)
            isInRange = requestDate.isAfter(
              now.subtract(const Duration(days: 1)),
            );
          } else {
            // For other ranges: include scans from startDate up to today
            // This includes today's scans in longer time ranges
            isInRange = requestDate.isAfter(
              startDate.subtract(const Duration(days: 1)),
            );
          }

          if (timeRange == '1 Day') {
            // debugPrint(
            // 'Request ${request['id']} date: $requestDate, timeRange: $timeRange (today only), in range: $isInRange',
            // );
          } else {
            // debugPrint(
            //   'Request ${request['id']} date: $requestDate, timeRange: $timeRange (${startDate.toString().split(' ')[0]} to today), in range: $isInRange',
            // );
          }
          return isInRange;
        }).toList();

    // debugPrint(
    //   'Filtered ${filteredRequests.length} requests out of ${requests.length}',
    // );
    return filteredRequests;
  }

  // Helper method to filter by custom date range
  static List<Map<String, dynamic>> _filterByCustomDateRange(
    List<Map<String, dynamic>> requests,
    DateTime startDate,
    DateTime endDate,
  ) {
    // debugPrint('Filtering requests from $startDate to $endDate');

    final filteredRequests =
        requests.where((request) {
          final createdAt = request['createdAt'];
          if (createdAt == null) {
            // debugPrint('Request ${request['id']} has no createdAt date');
            return false;
          }

          DateTime requestDate;
          if (createdAt is Timestamp) {
            requestDate = createdAt.toDate();
          } else if (createdAt is String) {
            requestDate = DateTime.tryParse(createdAt) ?? DateTime.now();
            // debugPrint('Parsed date from string: $requestDate');
          } else {
            // debugPrint(
            //   'Request ${request['id']} has invalid createdAt format: $createdAt',
            // );
            return false;
          }

          // Inclusive date range: [startDate 00:00, endDate 23:59:59]
          final DateTime startOfDay = DateTime(
            startDate.year,
            startDate.month,
            startDate.day,
          );
          final DateTime endExclusive = DateTime(
            endDate.year,
            endDate.month,
            endDate.day,
          ).add(const Duration(days: 1));
          final bool isInRange =
              !requestDate.isBefore(startOfDay) &&
              requestDate.isBefore(endExclusive);

          // debugPrint(
          //   'Request ${request['id']} date: $requestDate, in range: $isInRange',
          // );
          return isInRange;
        }).toList();

    // debugPrint(
    //   'Filtered ${filteredRequests.length} requests out of ${requests.length}',
    // );
    return filteredRequests;
  }

  // Helper method to format date for grouping
  static String _formatDateForGrouping(dynamic date) {
    if (date is Timestamp) {
      final dateTime = date.toDate();
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } else if (date is String) {
      // Handle ISO string format like "2025-08-01T18:47:52.592255"
      final dateTime = DateTime.tryParse(date);
      if (dateTime != null) {
        return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
      }
    }
    return DateTime.now().toString().split(' ')[0];
  }

  // Get average response time
  static Future<String> getAverageResponseTime({
    required String timeRange,
  }) async {
    try {
      final scanRequests = await getScanRequests();

      // Resolve window anchored to reviewedAt (completion time)
      final DateTime now = DateTime.now();
      DateTime? startInclusive;
      DateTime? endExclusive;
      if (timeRange.startsWith('Custom (') ||
          timeRange.startsWith('Monthly (')) {
        final regex = RegExp(
          r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
        );
        final match = regex.firstMatch(timeRange);
        if (match != null) {
          final startDate = DateTime.parse(match.group(1)!);
          final endDate = DateTime.parse(match.group(2)!);
          startInclusive = DateTime(
            startDate.year,
            startDate.month,
            startDate.day,
          );
          endExclusive = DateTime(
            endDate.year,
            endDate.month,
            endDate.day,
          ).add(const Duration(days: 1));
        }
      }
      if (startInclusive == null || endExclusive == null) {
        switch (timeRange) {
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

      // debugPrint('=== AVG RESPONSE TIME (OVERALL) DEBUG ===');
      // debugPrint('Time Range: $timeRange');
      // debugPrint('Now: $now');
      // debugPrint('Start (reviewedAt): $startInclusive');
      // debugPrint('End (exclusive, reviewedAt): $endExclusive');

      int completedCount = 0;
      int totalSeconds = 0;

      for (final request in scanRequests) {
        if ((request['status'] ?? '') != 'completed') continue;
        final createdAtRaw = request['createdAt'];
        final reviewedAtRaw = request['reviewedAt'];
        if (createdAtRaw == null || reviewedAtRaw == null) continue;

        DateTime createdAt;
        DateTime reviewedAt;

        if (createdAtRaw is Timestamp) {
          createdAt = createdAtRaw.toDate();
        } else if (createdAtRaw is String) {
          createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
        } else {
          continue;
        }

        if (reviewedAtRaw is Timestamp) {
          reviewedAt = reviewedAtRaw.toDate();
        } else if (reviewedAtRaw is String) {
          reviewedAt = DateTime.tryParse(reviewedAtRaw) ?? createdAt;
        } else {
          continue;
        }

        // Filter by reviewedAt window
        final bool inWindow;
        if (timeRange == '1 Day') {
          inWindow = reviewedAt.isAfter(startInclusive);
        } else if (timeRange.startsWith('Custom (') ||
            timeRange.startsWith('Monthly (')) {
          inWindow =
              !reviewedAt.isBefore(startInclusive) &&
              reviewedAt.isBefore(endExclusive);
        } else {
          // Use end-exclusive to align with UI logic and avoid boundary double-counting
          inWindow =
              !reviewedAt.isBefore(startInclusive) &&
              reviewedAt.isBefore(endExclusive);
        }
        if (!inWindow) continue;

        final seconds = reviewedAt.difference(createdAt).inSeconds;
        totalSeconds += seconds;
        completedCount += 1;
      }

      if (completedCount == 0) {
        // debugPrint('No completed requests in range. Returning 0 hours');
        return '0 hours';
      }

      final double averageSeconds = totalSeconds / completedCount;
      final double averageHours = averageSeconds / 3600.0;

      // debugPrint(
      //   'Overall average across $completedCount requests: '
      //   '${averageSeconds.toStringAsFixed(2)} seconds '
      //   '(${averageHours.toStringAsFixed(2)} hours)',
      // );
      // debugPrint('================================');

      // Always return in hours for UI consistency
      return '${averageHours.toStringAsFixed(2)} hours';
    } catch (e) {
      // debugPrint('Error getting average response time: $e');
      return '0 hours';
    }
  }

  // Compute completed, pending, and overdue-pending (>24h) counts using createdAt window
  static Future<Map<String, int>> getCountsForTimeRange({
    required String timeRange,
  }) async {
    final List<Map<String, dynamic>> all = await getScanRequests();
    final List<Map<String, dynamic>> filtered = filterByTimeRange(
      all,
      timeRange,
    );
    int completed = 0;
    int pending = 0;
    int overduePending = 0;
    for (final r in filtered) {
      final status = (r['status'] ?? '').toString();
      if (status == 'completed') {
        completed++;
      } else if (status == 'pending') {
        pending++;
        final createdAt = r['createdAt'];
        DateTime? created;
        if (createdAt is Timestamp) {
          created = createdAt.toDate();
        } else if (createdAt is String) {
          created = DateTime.tryParse(createdAt);
        }
        if (created != null) {
          final double hrs =
              DateTime.now().difference(created).inMinutes / 60.0;
          if (hrs > 24.0) overduePending++;
        }
      }
    }
    return {
      'completed': completed,
      'pending': pending,
      'overduePending': overduePending,
    };
  }

  // Get ongoing completion status for scans submitted in a time range
  // Returns current status of all scans from that period (completed anytime + still pending)
  static Future<Map<String, dynamic>> getOngoingCompletionStatus({
    required String timeRange,
  }) async {
    final List<Map<String, dynamic>> all = await getScanRequests();

    // Get all scans submitted in the time range (by createdAt)
    final List<Map<String, dynamic>> submittedInPeriod = filterByTimeRange(
      all,
      timeRange,
    );

    // Parse time range to get period boundaries
    final now = DateTime.now();
    DateTime? periodStart;
    DateTime? periodEnd;

    if (timeRange.startsWith('Custom (') || timeRange.startsWith('Monthly (')) {
      final regex = RegExp(
        r'(?:Custom|Monthly) \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(timeRange);
      if (match != null) {
        final startDateStr = match.group(1)!;
        final endDateStr = match.group(2)!;
        periodStart = DateTime.parse(startDateStr);
        periodEnd = DateTime.parse(endDateStr).add(const Duration(days: 1));
      }
    } else {
      switch (timeRange) {
        case '1 Day':
          periodStart = now.subtract(const Duration(days: 1));
          periodEnd = now;
          break;
        case 'Last 7 Days':
          periodStart = now.subtract(const Duration(days: 7));
          periodEnd = now;
          break;
        case 'Last 30 Days':
          periodStart = now.subtract(const Duration(days: 30));
          periodEnd = now;
          break;
        case 'Last 60 Days':
          periodStart = now.subtract(const Duration(days: 60));
          periodEnd = now;
          break;
        case 'Last 90 Days':
          periodStart = now.subtract(const Duration(days: 90));
          periodEnd = now;
          break;
        case 'Last Year':
          periodStart = now.subtract(const Duration(days: 365));
          periodEnd = now;
          break;
        default:
          periodStart = now.subtract(const Duration(days: 7));
          periodEnd = now;
      }
    }

    int totalSubmitted = submittedInPeriod.length;
    int completedInPeriod = 0; // Completed within the period
    int completedAfterPeriod = 0; // Completed after the period ended
    int stillPending = 0; // Still pending today

    for (final scan in submittedInPeriod) {
      final status = (scan['status'] ?? '').toString();

      if (status == 'completed') {
        final reviewedAtRaw = scan['reviewedAt'];
        DateTime? reviewedAt;

        if (reviewedAtRaw is Timestamp) {
          reviewedAt = reviewedAtRaw.toDate();
        } else if (reviewedAtRaw is String) {
          reviewedAt = DateTime.tryParse(reviewedAtRaw);
        }

        if (reviewedAt != null && periodStart != null && periodEnd != null) {
          // Check if completed within or after the period
          if (reviewedAt.isBefore(periodEnd)) {
            completedInPeriod++;
          } else {
            completedAfterPeriod++;
          }
        } else {
          // If we can't determine, assume it's completed
          completedInPeriod++;
        }
      } else if (status == 'pending') {
        stillPending++;
      }
    }

    int totalCompleted = completedInPeriod + completedAfterPeriod;
    double currentCompletionRate =
        totalSubmitted > 0 ? (totalCompleted / totalSubmitted) * 100 : 0.0;

    return {
      'totalSubmitted': totalSubmitted,
      'completedInPeriod': completedInPeriod,
      'completedAfterPeriod': completedAfterPeriod,
      'stillPending': stillPending,
      'totalCompleted': totalCompleted,
      'currentCompletionRate': currentCompletionRate,
    };
  }
}
