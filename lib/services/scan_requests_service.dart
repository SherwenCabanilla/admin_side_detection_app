import 'package:cloud_firestore/cloud_firestore.dart';

class ScanRequestsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Fetch all scan requests from Firestore
  static Future<List<Map<String, dynamic>>> getScanRequests() async {
    try {
      print('Fetching scan requests from Firestore...');
      final QuerySnapshot snapshot =
          await _firestore.collection('scan_requests').get();
      print('Found ${snapshot.docs.length} scan requests');

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        print('Document ${doc.id} data: $data'); // Debug: Print each document

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
      print('Error fetching scan requests: $e');
      return [];
    }
  }

  // Get disease statistics for a specific time range
  static Future<List<Map<String, dynamic>>> getDiseaseStats({
    required String timeRange,
  }) async {
    try {
      final scanRequests = await getScanRequests();
      print('Total scan requests: ${scanRequests.length}');

      // Filter by reviewedAt window and include only completed
      final DateTime now = DateTime.now();
      DateTime? startInclusive;
      DateTime? endExclusive;
      if (timeRange.startsWith('Custom (')) {
        final regex = RegExp(
          r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
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
        if ((r['status'] ?? '') != 'completed') continue;
        final reviewedAt = r['reviewedAt'];
        if (reviewedAt == null) continue;
        DateTime? reviewed;
        if (reviewedAt is Timestamp) reviewed = reviewedAt.toDate();
        if (reviewedAt is String) reviewed = DateTime.tryParse(reviewedAt);
        if (reviewed == null) continue;
        final inWindow =
            timeRange == '1 Day'
                ? reviewed.isAfter(startInclusive)
                : (!reviewed.isBefore(startInclusive) &&
                    reviewed.isBefore(endExclusive));
        if (inWindow) filteredRequests.add(r);
      }
      print('Filtered requests for $timeRange: ${filteredRequests.length}');

      // Debug: Print details of filtered requests
      for (final request in filteredRequests) {
        print(
          'Filtered request: ${request['id']} - ${request['userName']} - ${request['createdAt']} - ${request['diseaseSummary']}',
        );
      }

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

        print(
          'Processing request ${request['id']} with ${diseaseSummary.length} diseases',
        );
        print(
          'Disease summary data: $diseaseSummary',
        ); // Debug: Print disease summary

        for (final disease in diseaseSummary) {
          print('Processing disease: $disease'); // Debug: Print each disease

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
            print('Skipping Tip Burn/Unknown: $diseaseName');
            continue;
          }

          diseaseCounts[diseaseName] =
              (diseaseCounts[diseaseName] ?? 0) + count;
          totalDetections += count;
        }
      }

      print('Disease counts: $diseaseCounts');
      print('Total detections: $totalDetections');

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

      print('Final disease stats: $diseaseStats');
      return diseaseStats;
    } catch (e) {
      print('Error getting disease stats: $e');
      return [];
    }
  }

  // Get reports trend data for a specific time range
  static Future<List<Map<String, dynamic>>> getReportsTrend({
    required String timeRange,
  }) async {
    try {
      final scanRequests = await getScanRequests();

      // Filter by time range
      final filteredRequests = filterByTimeRange(scanRequests, timeRange);

      // Group by date
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
      print('Error getting reports trend: $e');
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
      print('Error getting total reports count: $e');
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
      print('Error getting pending reports count: $e');
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
      print('Error getting completed reports count: $e');
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

    // Handle custom date range
    if (timeRange.startsWith('Custom (')) {
      // Extract dates from "Custom (2025-08-01 to 2025-08-07)"
      final regex = RegExp(
        r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
      );
      final match = regex.firstMatch(timeRange);

      if (match != null) {
        final startDateStr = match.group(1)!;
        final endDateStr = match.group(2)!;

        final customStartDate = DateTime.parse(startDateStr);
        final customEndDate = DateTime.parse(endDateStr);

        // For custom ranges, we'll use the provided dates
        return _filterByCustomDateRange(
          requests,
          customStartDate,
          customEndDate,
        );
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

    print('=== TIME RANGE FILTERING DEBUG ===');
    print('Time Range: $timeRange');
    print('Now: $now');
    print('Start Date: $startDate');
    if (timeRange != '1 Day') {
      print(
        'Effective range: ${startDate.toString().split(' ')[0]} to today (including today)',
      );
    }
    print('Total requests to filter: ${requests.length}');
    print('==================================');

    final filteredRequests =
        requests.where((request) {
          final createdAt = request['createdAt'];
          if (createdAt == null) {
            print('Request ${request['id']} has no createdAt date');
            return false;
          }

          DateTime requestDate;
          if (createdAt is Timestamp) {
            requestDate = createdAt.toDate();
          } else if (createdAt is String) {
            // Handle ISO string format like "2025-08-01T18:47:52.592255"
            requestDate = DateTime.tryParse(createdAt) ?? DateTime.now();
            print('Parsed date from string: $requestDate');
          } else {
            print(
              'Request ${request['id']} has invalid createdAt format: $createdAt',
            );
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
            print(
              'Request ${request['id']} date: $requestDate, timeRange: $timeRange (today only), in range: $isInRange',
            );
          } else {
            print(
              'Request ${request['id']} date: $requestDate, timeRange: $timeRange (${startDate.toString().split(' ')[0]} to today), in range: $isInRange',
            );
          }
          return isInRange;
        }).toList();

    print(
      'Filtered ${filteredRequests.length} requests out of ${requests.length}',
    );
    return filteredRequests;
  }

  // Helper method to filter by custom date range
  static List<Map<String, dynamic>> _filterByCustomDateRange(
    List<Map<String, dynamic>> requests,
    DateTime startDate,
    DateTime endDate,
  ) {
    print('Filtering requests from $startDate to $endDate');

    final filteredRequests =
        requests.where((request) {
          final createdAt = request['createdAt'];
          if (createdAt == null) {
            print('Request ${request['id']} has no createdAt date');
            return false;
          }

          DateTime requestDate;
          if (createdAt is Timestamp) {
            requestDate = createdAt.toDate();
          } else if (createdAt is String) {
            requestDate = DateTime.tryParse(createdAt) ?? DateTime.now();
            print('Parsed date from string: $requestDate');
          } else {
            print(
              'Request ${request['id']} has invalid createdAt format: $createdAt',
            );
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

          print(
            'Request ${request['id']} date: $requestDate, in range: $isInRange',
          );
          return isInRange;
        }).toList();

    print(
      'Filtered ${filteredRequests.length} requests out of ${requests.length}',
    );
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
      if (timeRange.startsWith('Custom (')) {
        final regex = RegExp(
          r'Custom \((\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})\)',
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

      print('=== AVG RESPONSE TIME (OVERALL) DEBUG ===');
      print('Time Range: $timeRange');
      print('Now: $now');
      print('Start (reviewedAt): $startInclusive');
      print('End (exclusive, reviewedAt): $endExclusive');

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
        } else if (timeRange.startsWith('Custom (')) {
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
        print('No completed requests in range. Returning 0 hours');
        return '0 hours';
      }

      final double averageSeconds = totalSeconds / completedCount;
      final double averageHours = averageSeconds / 3600.0;

      print(
        'Overall average across $completedCount requests: '
        '${averageSeconds.toStringAsFixed(2)} seconds '
        '(${averageHours.toStringAsFixed(2)} hours)',
      );
      print('================================');

      // Always return in hours for UI consistency
      return '${averageHours.toStringAsFixed(2)} hours';
    } catch (e) {
      print('Error getting average response time: $e');
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
}
