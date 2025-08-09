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

      // Filter by time range
      final filteredRequests = filterByTimeRange(scanRequests, timeRange);
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

          // Check if request date is within the custom range (inclusive)
          final isInRange =
              requestDate.isAfter(
                startDate.subtract(const Duration(days: 1)),
              ) &&
              requestDate.isBefore(endDate.add(const Duration(days: 1)));

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
      final filteredRequests = filterByTimeRange(scanRequests, timeRange);

      print('=== AVG RESPONSE TIME DEBUG ===');
      print('Time Range: $timeRange');
      print('Total scan requests: ${scanRequests.length}');
      print('Filtered requests: ${filteredRequests.length}');

      // Group requests by expert
      final Map<String, List<Map<String, dynamic>>> expertGroups = {};

      for (final request in filteredRequests) {
        if (request['status'] == 'completed' &&
            request['createdAt'] != null &&
            request['reviewedAt'] != null) {
          final expertId =
              request['expertReview']?['expertUid'] ??
              request['expertUid'] ??
              request['expertId'];

          print('Request ${request['id']}: expertId = $expertId');
          print('  expertReview: ${request['expertReview']}');
          print('  expertUid: ${request['expertUid']}');
          print('  expertId: ${request['expertId']}');

          if (expertId != null) {
            expertGroups.putIfAbsent(expertId, () => []).add(request);
          }
        }
      }

      print('Expert groups: ${expertGroups.keys.toList()}');
      print('Number of experts: ${expertGroups.length}');

      if (expertGroups.isEmpty) {
        print('No expert groups found, returning 0 hours');
        return '0 hours';
      }

      // Calculate average response time for each expert
      final List<double> expertAverages = [];

      for (final entry in expertGroups.entries) {
        final expertId = entry.key;
        final expertRequests = entry.value;
        int totalSeconds = 0;

        print(
          'Processing expert $expertId with ${expertRequests.length} requests',
        );

        for (final request in expertRequests) {
          DateTime createdAt, reviewedAt;

          if (request['createdAt'] is Timestamp) {
            createdAt = request['createdAt'].toDate();
          } else if (request['createdAt'] is String) {
            createdAt =
                DateTime.tryParse(request['createdAt']) ?? DateTime.now();
          } else {
            createdAt = DateTime.now();
          }

          if (request['reviewedAt'] is Timestamp) {
            reviewedAt = request['reviewedAt'].toDate();
          } else {
            reviewedAt =
                DateTime.tryParse(request['reviewedAt']) ?? DateTime.now();
          }

          final difference = reviewedAt.difference(createdAt);
          final seconds = difference.inSeconds;
          totalSeconds += seconds;

          print('  Request ${request['id']}: ${seconds} seconds');
        }

        // Calculate average for this expert
        final expertAverageSeconds = totalSeconds / expertRequests.length;
        expertAverages.add(expertAverageSeconds);

        print(
          '  Expert $expertId average: ${expertAverageSeconds} seconds (${expertAverageSeconds / 60} minutes)',
        );
      }

      // Calculate average of per-expert averages
      final averageSeconds =
          expertAverages.reduce((a, b) => a + b) / expertAverages.length;
      final averageHours = averageSeconds / 3600; // Convert seconds to hours

      print('Final average: ${averageSeconds} seconds (${averageHours} hours)');
      print('Expert averages: $expertAverages');
      print('================================');

      // Format the result appropriately
      if (averageHours < 1) {
        // Less than 1 hour, show in minutes
        final minutes = averageSeconds / 60;
        return '${minutes.toStringAsFixed(1)} minutes';
      } else {
        // 1 hour or more, show in hours
        return '${averageHours.toStringAsFixed(2)} hours';
      }
    } catch (e) {
      print('Error getting average response time: $e');
      return '0 hours';
    }
  }
}
