import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../shared/total_users_card.dart';
import '../shared/pending_approvals_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/scan_requests_service.dart';
import 'admin_dashboard.dart' show ScanRequestsSnapshot;
import 'package:provider/provider.dart';
import '../models/user_store.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateStatsFromSnapshot();
  }

  void _updateStatsFromSnapshot() async {
    final scanRequestsProvider = Provider.of<ScanRequestsSnapshot?>(context);
    final snapshot = scanRequestsProvider?.snapshot;
    if (snapshot == null) return;
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
    final filteredRequests = ScanRequestsService.filterByTimeRange(
      scanRequests,
      _selectedTimeRange,
    );
    int totalResponseTime = 0;
    int completedRequests = 0;
    for (final request in filteredRequests) {
      if (request['status'] == 'completed' &&
          request['createdAt'] != null &&
          request['reviewedAt'] != null) {
        DateTime createdAt, reviewedAt;
        if (request['createdAt'] is Timestamp) {
          createdAt = request['createdAt'].toDate();
        } else if (request['createdAt'] is String) {
          createdAt = DateTime.tryParse(request['createdAt']) ?? DateTime.now();
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
        totalResponseTime += difference.inHours;
        completedRequests++;
      }
    }
    final averageResponseTime =
        completedRequests == 0
            ? '0 hours'
            : '${(totalResponseTime / completedRequests).toStringAsFixed(2)} hours';
    setState(() {
      _stats['averageResponseTime'] = averageResponseTime;
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
      final completedReports =
          await ScanRequestsService.getCompletedReportsCount();
      final pendingReports = await ScanRequestsService.getPendingReportsCount();
      final averageResponseTime =
          await ScanRequestsService.getAverageResponseTime(
            timeRange: 'Last 7 Days', // Always use 'Last 7 Days' for the card
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
                    ElevatedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Generate Report'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2D7204),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final selectedRange = await showDialog<String>(
                          context: context,
                          builder: (context) => const GenerateReportDialog(),
                        );
                        if (selectedRange != null) {
                          // TODO: Implement PDF generation logic for selectedRange
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Generate PDF for: '
                                ' [1m$selectedRange [0m',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
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
                      builder:
                          (context) => Dialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Container(
                              width: MediaQuery.of(context).size.width * 0.9,
                              height: MediaQuery.of(context).size.height * 0.8,
                              padding: const EdgeInsets.all(20),
                              child: ReportsModalContent(),
                            ),
                          ),
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
                      setState(() {
                        _selectedTimeRange = newTimeRange;
                        _isLoading = true;
                      });
                      await _loadData();
                    },
                  ),
                ),
              ],
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
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 16),

              // Number
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              // Title
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
              // Update the card's time range when modal dropdown changes
              _updateAvgResponseTimeForRange(newTimeRange);
            },
          ),
    );
  }

  void _updateAvgResponseTimeForRange(String timeRange) async {
    print('=== CARD UPDATE DEBUG ===');
    print('Updating card for time range: $timeRange');
    try {
      final averageResponseTime =
          await ScanRequestsService.getAverageResponseTime(
            timeRange: timeRange,
          );
      print('Card received average response time: $averageResponseTime');
      setState(() {
        _stats['averageResponseTime'] = averageResponseTime;
      });
      print('Card updated with new value: ${_stats['averageResponseTime']}');
    } catch (e) {
      print('Error updating avg response time: $e');
    }
    print('=== END CARD UPDATE DEBUG ===');
  }
}

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
  final List<Map<String, dynamic>> _dummyReports = [
    {
      'id': 'RPT-001',
      'user': 'John Doe',
      'date': '2025-05-01',
      'disease': 'Anthracnose',
      'status': 'Reviewed',
      'image': null,
      'details': 'Leaf spots and necrosis detected.',
      'expert': 'Dr. Smith',
      'feedback': 'Confirmed Anthracnose. Apply fungicide.',
    },
    {
      'id': 'RPT-002',
      'user': 'Jane Smith',
      'date': '2025-05-02',
      'disease': 'Healthy',
      'status': 'Reviewed',
      'image': null,
      'details': 'No disease detected.',
      'expert': 'Dr. Lee',
      'feedback': 'No action needed.',
    },
    {
      'id': 'RPT-003',
      'user': 'Mike Johnson',
      'date': '2025-05-03',
      'disease': 'Powdery Mildew',
      'status': 'Pending',
      'image': null,
      'details': 'White powdery spots on leaves.',
      'expert': '',
      'feedback': '',
    },
  ];

  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredReports {
    if (_searchQuery.isEmpty) return _dummyReports;
    return _dummyReports.where((report) {
      final query = _searchQuery.toLowerCase();
      return report['user'].toString().toLowerCase().contains(query) ||
          report['disease'].toString().toLowerCase().contains(query) ||
          report['status'].toString().toLowerCase().contains(query);
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
                  _filteredReports.map((report) {
                    return DataRow(
                      cells: [
                        DataCell(Text(report['id'])),
                        DataCell(Text(report['user'])),
                        DataCell(Text(report['date'])),
                        DataCell(Text(report['disease'])),
                        DataCell(Text(report['status'])),
                        DataCell(
                          ElevatedButton(
                            child: const Text('View'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder:
                                    (context) => AlertDialog(
                                      title: Text(
                                        'Report Details: ${report['id']}',
                                      ),
                                      content: SingleChildScrollView(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Report ID: ${report['id']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text('User: ${report['user']}'),
                                            Text('Date: ${report['date']}'),
                                            Text(
                                              'Disease: ${report['disease']}',
                                            ),
                                            Text('Status: ${report['status']}'),
                                            const SizedBox(height: 16),
                                            if (report['image'] != null)
                                              Container(
                                                height: 180,
                                                width: 180,
                                                color: Colors.grey[200],
                                                child: Image.network(
                                                  report['image'],
                                                  fit: BoxFit.cover,
                                                ),
                                              )
                                            else
                                              Container(
                                                height: 180,
                                                width: 180,
                                                color: Colors.grey[200],
                                                child: const Center(
                                                  child: Text('No Image'),
                                                ),
                                              ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'Details: ${report['details']}',
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Expert: ${report['expert'] ?? "-"}',
                                            ),
                                            Text(
                                              'Feedback: ${report['feedback'] ?? "-"}',
                                            ),
                                          ],
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              () => Navigator.pop(context),
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
  List<Map<String, dynamic>> get _currentData => widget.diseaseStats;

  List<Map<String, dynamic>> get _diseaseData =>
      _currentData.where((item) => item['type'] == 'disease').toList();

  List<Map<String, dynamic>> get _healthyData =>
      _currentData.where((item) => item['type'] == 'healthy').toList();

  Color _getDiseaseColor(String disease) {
    switch (disease.toLowerCase()) {
      case 'anthracnose':
        return Colors.orange;
      case 'bacterial blackspot':
        return Colors.purple;
      case 'powdery mildew':
        return const Color.fromARGB(255, 9, 46, 2);
      case 'dieback':
        return Colors.red;
      case 'tip burn':
        return Colors.amber;
      case 'healthy':
        return const Color.fromARGB(255, 2, 119, 252);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: widget.selectedTimeRange,
                    items: [
                      ...[
                        '1 Day',
                        'Last 7 Days',
                        'Last 30 Days',
                        'Last 60 Days',
                        'Last 90 Days',
                        'Last Year',
                        'Custom',
                      ].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }),
                      // Add dynamic custom range if it exists and doesn't match 'Custom'
                      if (widget.selectedTimeRange.startsWith('Custom (') &&
                          widget.selectedTimeRange != 'Custom')
                        DropdownMenuItem<String>(
                          value: widget.selectedTimeRange,
                          child: Text(
                            widget.selectedTimeRange,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (String? newValue) async {
                      if (newValue != null) {
                        if (newValue == 'Custom') {
                          try {
                            // Show date range picker for custom dates
                            final DateTimeRange? pickedRange =
                                await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  initialDateRange: DateTimeRange(
                                    start: DateTime.now().subtract(
                                      const Duration(days: 7),
                                    ),
                                    end: DateTime.now(),
                                  ),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: Theme.of(context)
                                            .colorScheme
                                            .copyWith(primary: Colors.blue),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );

                            if (pickedRange != null) {
                              // Format the custom range for display
                              final startDate =
                                  '${pickedRange.start.year}-${pickedRange.start.month.toString().padLeft(2, '0')}-${pickedRange.start.day.toString().padLeft(2, '0')}';
                              final endDate =
                                  '${pickedRange.end.year}-${pickedRange.end.month.toString().padLeft(2, '0')}-${pickedRange.end.day.toString().padLeft(2, '0')}';
                              final customRange =
                                  'Custom ($startDate to $endDate)';

                              // Call the callback with custom range info
                              widget.onTimeRangeChanged?.call(customRange);
                            }
                          } catch (e) {
                            print('Error showing date picker: $e');
                            // Show error message to user
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Error selecting date range. Using default range.',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            // Fallback to default range if picker fails
                            widget.onTimeRangeChanged?.call('Last 7 Days');
                          }
                        } else {
                          // Call the callback to notify parent
                          widget.onTimeRangeChanged?.call(newValue);
                        }
                      }
                    },
                    underline: const SizedBox(),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.black87,
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
                                'Total: ${_diseaseData.isEmpty ? 0 : _diseaseData.fold<int>(0, (sum, item) => sum + (item['count'] as int))} cases',
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
                                _diseaseData.isEmpty
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
                                            _diseaseData.isEmpty
                                                ? 100.0
                                                : _diseaseData
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
                                                      _diseaseData.length ||
                                                  _diseaseData.isEmpty) {
                                                return null;
                                              }
                                              final disease =
                                                  _diseaseData[groupIndex];
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
                                                        _diseaseData.length ||
                                                    _diseaseData.isEmpty) {
                                                  return const SizedBox.shrink();
                                                }
                                                final disease =
                                                    _diseaseData[value.toInt()];
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
                                              getTitlesWidget: (value, meta) {
                                                if (value % 50 == 0) {
                                                  return Text(
                                                    value.toInt().toString(),
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontSize: 12,
                                                    ),
                                                  );
                                                }
                                                return const SizedBox.shrink();
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
                                          horizontalInterval: 50,
                                          getDrawingHorizontalLine: (value) {
                                            return FlLine(
                                              color: Colors.grey[200],
                                              strokeWidth: 1,
                                            );
                                          },
                                        ),
                                        barGroups:
                                            _diseaseData.isEmpty
                                                ? []
                                                : _diseaseData.asMap().entries.map((
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
                                'Total: ${_healthyData.isEmpty ? 0 : _healthyData.fold<int>(0, (sum, item) => sum + (item['count'] as int))} cases',
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
                                _healthyData.isEmpty
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
                                            _healthyData.isEmpty
                                                ? 100.0
                                                : _healthyData
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
                                                      _healthyData.length ||
                                                  _healthyData.isEmpty) {
                                                return null;
                                              }
                                              final disease =
                                                  _healthyData[groupIndex];
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
                                                        _healthyData.length ||
                                                    _healthyData.isEmpty) {
                                                  return const SizedBox.shrink();
                                                }
                                                final disease =
                                                    _healthyData[value.toInt()];
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
                                              getTitlesWidget: (value, meta) {
                                                if (value % 50 == 0) {
                                                  return Text(
                                                    value.toInt().toString(),
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontSize: 12,
                                                    ),
                                                  );
                                                }
                                                return const SizedBox.shrink();
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
                                          horizontalInterval: 50,
                                          getDrawingHorizontalLine: (value) {
                                            return FlLine(
                                              color: Colors.grey[200],
                                              strokeWidth: 1,
                                            );
                                          },
                                        ),
                                        barGroups:
                                            _healthyData.isEmpty
                                                ? []
                                                : _healthyData.asMap().entries.map((
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
}

class ReportsTrendDialog extends StatefulWidget {
  @override
  State<ReportsTrendDialog> createState() => _ReportsTrendDialogState();
}

class _ReportsTrendDialogState extends State<ReportsTrendDialog> {
  String _selectedTimeRange = 'Last 7 Days';

  // Dummy data for different time ranges
  final Map<String, List<Map<String, dynamic>>> _timeRangeData = {
    '1 Day': [
      {'date': '2024-03-07', 'count': 68},
    ],
    'Last 7 Days': [
      {'date': '2024-03-01', 'count': 45},
      {'date': '2024-03-02', 'count': 52},
      {'date': '2024-03-03', 'count': 48},
      {'date': '2024-03-04', 'count': 65},
      {'date': '2024-03-05', 'count': 58},
      {'date': '2024-03-06', 'count': 72},
      {'date': '2024-03-07', 'count': 68},
    ],
    'Last 30 Days': List.generate(
      30,
      (i) => {
        'date': '2024-03-${(i + 1).toString().padLeft(2, '0')}',
        'count': 40 + (i % 10) * 2,
      },
    ),
    'Last 60 Days': List.generate(
      60,
      (i) => {
        'date':
            '2024-02-${(i < 29 ? (i + 1) : (i - 28)).toString().padLeft(2, '0')}',
        'count': 35 + (i % 15),
      },
    ),
    'Last 90 Days': List.generate(
      90,
      (i) => {
        'date':
            '2024-01-${(i < 31 ? (i + 1) : (i - 30)).toString().padLeft(2, '0')}',
        'count': 30 + (i % 20),
      },
    ),
    'Last Year': List.generate(
      12,
      (i) => {
        'date': '2023-${(i + 1).toString().padLeft(2, '0')}',
        'count': 100 + i * 10,
      },
    ),
  };

  List<Map<String, dynamic>> get _currentData =>
      _timeRangeData[_selectedTimeRange] ?? _timeRangeData['Last 7 Days']!;

  List<Map<String, dynamic>> get _aggregatedData {
    // For large ranges, aggregate by week
    if (_selectedTimeRange == 'Last 30 Days' ||
        _selectedTimeRange == 'Last 60 Days' ||
        _selectedTimeRange == 'Last 90 Days') {
      final data = _currentData;
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
    return _currentData;
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
                          [
                                '1 Day',
                                'Last 7 Days',
                                'Last 30 Days',
                                'Last 60 Days',
                                'Last 90 Days',
                                'Last Year',
                              ]
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
            if (_aggregatedData.isEmpty)
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
    final filteredRequests = ScanRequestsService.filterByTimeRange(
      scanRequests,
      _selectedRange,
    );
    final Map<String, List<Map<String, dynamic>>> expertGroups = {};
    for (final req in filteredRequests) {
      if (req['status'] == 'completed') {
        final expertId =
            req['expertReview']?['expertId'] ??
            req['expertUid'] ??
            req['expertId'];
        print(
          '[DEBUG] For request \'${req['id']}\', found expertId: $expertId',
        );
        if (expertId != null &&
            req['createdAt'] != null &&
            req['reviewedAt'] != null) {
          expertGroups.putIfAbsent(expertId, () => []).add(req);
        } else {
          print(
            '[DEBUG] Skipped completed request (no expertId): ${req['id']} expertReview=${req['expertReview']} expertUid=${req['expertUid']}',
          );
        }
      }
    }
    print('[DEBUG] expertGroups keys: \'${expertGroups.keys.toList()}\'');
    final users = await UserStore.getUsers();
    final experts = {
      for (var u in users)
        if (u['role'] == 'expert') u['userId']: u,
    };
    final List<_ExpertResponseStats> stats = [];
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
        width: 700,
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
                const Text(
                  'Average Response Time (per Expert)',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    DropdownButton<String>(
                      value: _selectedRange,
                      items:
                          [
                                '1 Day',
                                'Last 7 Days',
                                'Last 30 Days',
                                'Last 60 Days',
                                'Last 90 Days',
                                'Last Year',
                              ]
                              .map(
                                (range) => DropdownMenuItem(
                                  value: range,
                                  child: Text(range),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        print('=== DROPDOWN ONCHANGED CALLED ===');
                        print('Dropdown onChanged called with value: $value');
                        if (value != null) {
                          print('=== MODAL DROPDOWN DEBUG ===');
                          print('Modal dropdown changed to: $value');
                          setState(() {
                            _selectedRange = value;
                          });
                          print('Calling onTimeRangeChanged callback...');
                          widget.onTimeRangeChanged?.call(value);
                          print('Callback called, now loading expert stats...');
                          _loadExpertStats();
                          print('=== END MODAL DROPDOWN DEBUG ===');
                        }
                      },
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
  _ExpertResponseStats({
    required this.expertId,
    required this.name,
    required this.avatar,
    required this.avgSeconds,
    required this.trend,
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
  ];

  Map<String, dynamic> get _selectedRangeData =>
      _ranges.firstWhere((r) => r['label'] == _selectedRange);

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
                  _ranges.map((range) {
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
                  }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedRange = value;
                  });
                }
              },
            ),
          ),
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
                          'Includes: Disease Distribution, Response Times',
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
            Navigator.pop(context, _selectedRange);
          },
        ),
      ],
    );
  }
}
