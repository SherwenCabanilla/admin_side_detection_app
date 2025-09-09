import 'date_range_picker.dart';
import 'package:flutter/material.dart';
// import '../models/user_store.dart';
import '../services/scan_requests_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../screens/admin_dashboard.dart';
import 'package:firebase_storage/firebase_storage.dart';

// Resolve a possibly non-HTTP image reference (e.g., Firebase Storage path)
// to a downloadable URL. Accepts strings, maps with common url keys, or other.
Future<String> resolveStorageImageUrl(dynamic imageData) async {
  String candidate = '';
  String storagePath = '';
  if (imageData is String) {
    candidate = imageData.trim();
  } else if (imageData is Map<String, dynamic>) {
    // Prefer a direct Firebase Storage path when available
    final dynamic sp = imageData['storagePath'] ?? imageData['path'];
    if (sp is String && sp.trim().isNotEmpty) {
      storagePath = sp.trim();
    }
    final dynamic url =
        imageData['url'] ??
        imageData['imageUrl'] ??
        imageData['image'] ??
        imageData['src'] ??
        imageData['link'] ??
        imageData['downloadURL'] ??
        imageData['storageURL'] ??
        '';
    candidate = url.toString().trim();
  } else if (imageData != null) {
    candidate = imageData.toString().trim();
  }

  // Remove accidental line breaks/spaces that corrupt URLs
  candidate = candidate.replaceAll('\n', '').replaceAll('\r', '').trim();
  if (candidate.isEmpty && storagePath.isEmpty) return '';
  final bool isHttp =
      candidate.startsWith('http://') || candidate.startsWith('https://');
  if (isHttp) {
    // Use the URL as-is. Both .appspot.com and .firebasestorage.app are valid
    // bucket domains depending on when the project was created.
    return candidate;
  }

  try {
    if (candidate.startsWith('gs://')) {
      final ref = FirebaseStorage.instance.refFromURL(candidate);
      return await ref.getDownloadURL();
    }
    // Treat as relative path inside default bucket (prefer storagePath if present)
    final String pathToUse = storagePath.isNotEmpty ? storagePath : candidate;
    final ref = FirebaseStorage.instance.ref(pathToUse);
    return await ref.getDownloadURL();
  } catch (_) {
    // Fallback to original; Image.network will likely fail but UI handles errorBuilder
    return candidate.isNotEmpty ? candidate : storagePath;
  }
}

// Shared disease-to-color mapping used across modals and cards
Color diseaseColor(String disease) {
  final normalized =
      (disease.toString())
          .replaceAll(RegExp(r'[\-_]+'), ' ')
          .trim()
          .toLowerCase();
  if (normalized.contains('healthy')) return Colors.blue;
  if (normalized.contains('powdery') || normalized.contains('mildew')) {
    return Colors.green.shade900;
  }
  if (normalized.contains('dieback')) return Colors.redAccent;
  if (normalized.contains('bacterial') && normalized.contains('spot')) {
    return Colors.purple;
  }
  if (normalized.contains('anthracnose')) return Colors.orange;
  if (normalized.contains('tip burn') || normalized.contains('tipburn')) {
    return Colors.brown;
  }
  if (normalized == 'unknown') return Colors.blueGrey;
  if (normalized.contains('rust')) return Colors.orange;
  if (normalized.contains('blight')) return Colors.deepOrange;
  if (normalized.contains('spot')) return Colors.teal;
  return Colors.redAccent;
}

class TotalUsersCard extends StatefulWidget {
  final VoidCallback? onTap;
  const TotalUsersCard({Key? key, this.onTap}) : super(key: key);

  @override
  State<TotalUsersCard> createState() => _TotalUsersCardState();
}

class TotalReportsReviewedCard extends StatefulWidget {
  final int totalReports;
  final List<Map<String, dynamic>> reportsTrend;
  final VoidCallback? onTap;

  const TotalReportsReviewedCard({
    Key? key,
    required this.totalReports,
    required this.reportsTrend,
    this.onTap,
  }) : super(key: key);

  @override
  State<TotalReportsReviewedCard> createState() =>
      _TotalReportsReviewedCardState();
}

class _TotalReportsReviewedCardState extends State<TotalReportsReviewedCard> {
  int _completedReports = 0;
  int _pendingReports = 0;
  bool _isLoading = true;
  bool _showBoundingBoxes =
      false; // Toggle for bounding boxes visibility (default disabled)
  final ValueNotifier<bool> _isHovered = ValueNotifier(false);

  String _fixDiseaseName(String disease) {
    // Normalize separators and case for robust comparisons
    final String raw = (disease).toString();
    final String normalized =
        raw.replaceAll(RegExp(r'[_\-]+'), ' ').trim().toLowerCase();

    // Fix common spelling issues
    if (normalized == 'backterial b' ||
        normalized == 'backterial blackspot' ||
        normalized == 'bacterial b') {
      return 'bacterial_blackspot';
    }

    // Map all tip burn variants to Unknown
    if (normalized == 'tip burn' || normalized == 'tipburn') {
      return 'Unknown';
    }

    return raw;
  }

  Color _colorForDisease(String disease) {
    return diseaseColor(_fixDiseaseName(disease));
  }

  // Reuse existing color mapping to ensure consistency
  Color _getColorForDisease(String disease) {
    return diseaseColor(_fixDiseaseName(disease));
  }

  List<Widget> _buildRecommendationsList(dynamic recommendations) {
    if (recommendations == null) return [];

    if (recommendations is List) {
      return recommendations.map<Widget>((rec) {
        if (rec is Map<String, dynamic>) {
          final treatment = rec['treatment'] ?? '';
          final dosage = rec['dosage'] ?? '';
          final frequency = rec['frequency'] ?? '';
          final duration = rec['duration'] ?? '';

          String displayText = '';
          if (treatment.isNotEmpty) displayText += 'Treatment: $treatment';
          if (dosage.isNotEmpty)
            displayText +=
                '${displayText.isNotEmpty ? ', ' : ''}Dosage: $dosage';
          if (frequency.isNotEmpty)
            displayText +=
                '${displayText.isNotEmpty ? ', ' : ''}Frequency: $frequency';
          if (duration.isNotEmpty)
            displayText +=
                '${displayText.isNotEmpty ? ', ' : ''}Duration: $duration';

          if (displayText.isEmpty) displayText = 'No details available';

          return Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Text(
              '• $displayText',
              style: const TextStyle(fontSize: 11, color: Colors.green),
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Text(
              '• ${rec.toString()}',
              style: const TextStyle(fontSize: 11, color: Colors.green),
            ),
          );
        }
      }).toList();
    } else {
      return [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Text(
            '• ${recommendations.toString()}',
            style: const TextStyle(fontSize: 11, color: Colors.green),
          ),
        ),
      ];
    }
  }

  List<Widget> _buildPreventiveMeasuresList(dynamic preventiveMeasures) {
    if (preventiveMeasures == null) return [];

    if (preventiveMeasures is List) {
      return preventiveMeasures.map<Widget>((measure) {
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Text(
            '• ${measure.toString()}',
            style: const TextStyle(fontSize: 11, color: Colors.green),
          ),
        );
      }).toList();
    } else {
      return [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Text(
            '• ${preventiveMeasures.toString()}',
            style: const TextStyle(fontSize: 11, color: Colors.green),
          ),
        ),
      ];
    }
  }

  Widget _buildExpertReviewWidget(dynamic expertReview) {
    try {
      if (expertReview == null) {
        return const Text(
          'No expert review available.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        );
      }

      // Debug: Print the actual data structure
      print('Expert review data type: ${expertReview.runtimeType}');
      print('Expert review data: $expertReview');

      // If it's already a Map (most likely case)
      if (expertReview is Map<String, dynamic>) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (expertReview['expertName'] != null) ...[
              Text(
                'Expert: ${expertReview['expertName']}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (expertReview['comment'] != null &&
                expertReview['comment'].toString().isNotEmpty) ...[
              Text(
                'Comment: ${expertReview['comment']}',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
              const SizedBox(height: 4),
            ],
            if (expertReview['severityAssessment'] != null) ...[
              Builder(
                builder: (context) {
                  final severity = expertReview['severityAssessment'];
                  if (severity is Map<String, dynamic> &&
                      severity['level'] != null) {
                    return Text(
                      'Severity: ${severity['level']}',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    );
                  } else if (severity is String) {
                    return Text(
                      'Severity: $severity',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: 4),
            ],
            if (expertReview['treatmentPlan'] != null) ...[
              Builder(
                builder: (context) {
                  final treatmentPlan = expertReview['treatmentPlan'];
                  if (treatmentPlan is Map<String, dynamic>) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (treatmentPlan['recommendations'] != null) ...[
                          Text(
                            'Recommendations:',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ..._buildRecommendationsList(
                            treatmentPlan['recommendations'],
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (treatmentPlan['preventiveMeasures'] != null) ...[
                          Text(
                            'Preventive Measures:',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ..._buildPreventiveMeasuresList(
                            treatmentPlan['preventiveMeasures'],
                          ),
                          const SizedBox(height: 4),
                        ],
                      ],
                    );
                  } else {
                    return Text(
                      'Treatment Plan: $treatmentPlan',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    );
                  }
                },
              ),
              const SizedBox(height: 4),
            ],
          ],
        );
      }

      // Try to parse as JSON string
      if (expertReview is String) {
        try {
          // Remove any extra formatting and parse
          final cleanString = expertReview.replaceAll(RegExp(r'[{}]'), '');
          final parts = cleanString.split(',');

          Map<String, String> reviewData = {};
          for (String part in parts) {
            final keyValue = part.split(':');
            if (keyValue.length >= 2) {
              final key = keyValue[0].trim();
              final value = keyValue.sublist(1).join(':').trim();
              reviewData[key] = value;
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reviewData['expertName'] != null) ...[
                Text(
                  'Expert: ${reviewData['expertName']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (reviewData['comment'] != null &&
                  reviewData['comment']!.isNotEmpty) ...[
                Text(
                  'Comment: ${reviewData['comment']}',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
                const SizedBox(height: 4),
              ],
              if (reviewData['severityAssessment'] != null) ...[
                Text(
                  'Severity: ${reviewData['severityAssessment']}',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
                const SizedBox(height: 4),
              ],
              if (reviewData['treatmentPlan'] != null) ...[
                Text(
                  'Treatment Plan: ${reviewData['treatmentPlan']}',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
                const SizedBox(height: 4),
              ],
            ],
          );
        } catch (e) {
          // If parsing fails, show as plain text
          return Text(
            expertReview,
            style: TextStyle(fontSize: 14, color: Colors.green[700]),
          );
        }
      }

      return Text(
        expertReview.toString(),
        style: TextStyle(fontSize: 14, color: Colors.green[700]),
      );
    } catch (e) {
      return Text(
        'Error parsing expert review: $e',
        style: TextStyle(fontSize: 14, color: Colors.red[600]),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get actual counts from the service
      final completedCount =
          await ScanRequestsService.getCompletedReportsCount();
      final pendingCount = await ScanRequestsService.getPendingReportsCount();

      if (!mounted) return;
      setState(() {
        _completedReports = completedCount;
        _pendingReports = pendingCount;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isClickable = widget.onTap != null;
    final ScanRequestsSnapshot? scanRequestsProvider =
        Provider.of<ScanRequestsSnapshot?>(context);
    final QuerySnapshot? scanRequestsSnapshot = scanRequestsProvider?.snapshot;
    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      cursor: isClickable ? SystemMouseCursors.click : MouseCursor.defer,
      child: ValueListenableBuilder<bool>(
        valueListenable: _isHovered,
        builder: (context, isHovered, child) {
          return Card(
            elevation: isHovered && isClickable ? 8 : 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: widget.onTap ?? () => _showReportsModal(context),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: child, // Use the child below
              ),
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header (no refresh button)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 24), // Spacer to center the content
                const Spacer(),
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
            const SizedBox(height: 12),
            // Number (real-time count)
            Builder(
              builder: (context) {
                if (scanRequestsSnapshot == null) {
                  return const CircularProgressIndicator();
                }
                final docs = scanRequestsSnapshot.docs;
                final completedReports =
                    docs.where((doc) => doc['status'] == 'completed').length;
                final pendingReports =
                    docs.where((doc) => doc['status'] == 'pending').length;
                return Column(
                  children: [
                    Text(
                      '$completedReports',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Total Reports Reviewed',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
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
                              '$completedReports Completed',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                              '$pendingReports Pending Review',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showReportsModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(20),
            child: ReportsModalContent(),
          ),
        );
      },
    );
  }

  Widget _buildCompletedReportsTab(bool showBoundingBoxes) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getCompletedReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final reports = snapshot.data ?? [];

        if (reports.isEmpty) {
          return const Center(
            child: Text(
              'No completed reports found',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            return _buildReportCard(report, true, showBoundingBoxes);
          },
        );
      },
    );
  }

  Widget _buildPendingReportsTab(bool showBoundingBoxes) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getPendingReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final reports = snapshot.data ?? [];

        if (reports.isEmpty) {
          return const Center(
            child: Text(
              'No pending reports found',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            return _buildReportCard(report, false, showBoundingBoxes);
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getCompletedReports() async {
    try {
      final allReports = await ScanRequestsService.getScanRequests();
      final completedReports =
          allReports
              .where((report) => report['status'] == 'completed')
              .toList();

      // Sort by createdAt date in descending order (most recent first)
      completedReports.sort((a, b) {
        final aDate = _parseDate(a['createdAt']);
        final bDate = _parseDate(b['createdAt']);
        return bDate.compareTo(aDate); // Descending order
      });

      return completedReports;
    } catch (e) {
      print('Error getting completed reports: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getPendingReports() async {
    try {
      final allReports = await ScanRequestsService.getScanRequests();
      final pendingReports =
          allReports.where((report) => report['status'] == 'pending').toList();

      // Sort by createdAt date in descending order (most recent first)
      pendingReports.sort((a, b) {
        final aDate = _parseDate(a['createdAt']);
        final bDate = _parseDate(b['createdAt']);
        return bDate.compareTo(aDate); // Descending order
      });

      return pendingReports;
    } catch (e) {
      print('Error getting pending reports: $e');
      return [];
    }
  }

  DateTime _parseDate(dynamic date) {
    if (date is Timestamp) {
      return date.toDate();
    } else if (date is String) {
      return DateTime.tryParse(date) ?? DateTime.now();
    } else {
      return DateTime.now();
    }
  }

  Widget _buildReportCard(
    Map<String, dynamic> report,
    bool isCompleted,
    bool showBoundingBoxes,
  ) {
    final userName = report['userName'] ?? 'Unknown User';
    final createdAt = report['createdAt'];
    final reviewedAt = report['reviewedAt'];
    final images = report['images'] ?? [];
    final diseaseSummary = report['diseaseSummary'] ?? [];
    final expertReview = report['expertReview'];

    String _monthShort(int m) =>
        const [
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
        ][m - 1];

    String _formatMdyWithTime(DateTime dt) {
      final mm = _monthShort(dt.month);
      final hh = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$mm ${dt.day} ${dt.year} $hh:$min';
    }

    String _humanizeDuration(Duration d) {
      int totalMinutes = d.inMinutes.abs();
      final days = totalMinutes ~/ (24 * 60);
      totalMinutes %= (24 * 60);
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      final parts = <String>[];
      if (days > 0) parts.add('$days day${days == 1 ? '' : 's'}');
      if (hours > 0) parts.add('$hours hour${hours == 1 ? '' : 's'}');
      if (minutes > 0 || parts.isEmpty) {
        parts.add('$minutes min${minutes == 1 ? '' : 's'}');
      }
      return parts.join(' ');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        () {
                          final dt = _parseDate(createdAt);
                          return 'Submitted: ${_formatMdyWithTime(dt)}';
                        }(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      if (isCompleted && reviewedAt != null) ...[
                        Text(
                          () {
                            final dt = _parseDate(reviewedAt);
                            return 'Reviewed: ${_formatMdyWithTime(dt)}';
                          }(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          () {
                            final submitted = _parseDate(createdAt);
                            final reviewed = _parseDate(reviewedAt);
                            return 'Turnaround: ${_humanizeDuration(reviewed.difference(submitted))}';
                          }(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCompleted ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isCompleted ? 'Completed' : 'Pending',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Images with bounding boxes
            if (images.isNotEmpty) ...[
              const Text(
                'Images:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  itemBuilder: (context, imageIndex) {
                    final imageData = images[imageIndex];
                    String imageUrl = '';

                    // Debug: Print the image data structure
                    print('Image data at index $imageIndex: $imageData');
                    print('Image data type: ${imageData.runtimeType}');

                    // Handle different image data structures
                    if (imageData is String) {
                      imageUrl = imageData;
                      print('Using string URL: $imageUrl');
                    } else if (imageData is Map<String, dynamic>) {
                      // Try different possible field names for the URL
                      imageUrl =
                          imageData['url'] ??
                          imageData['imageUrl'] ??
                          imageData['image'] ??
                          imageData['src'] ??
                          imageData['link'] ??
                          imageData['downloadURL'] ??
                          imageData['storageURL'] ??
                          imageData.toString();
                      print('Using map URL: $imageUrl');
                    } else {
                      imageUrl = imageData.toString();
                      print('Using toString URL: $imageUrl');
                    }

                    // Clean up the URL - remove line breaks and extra spaces
                    imageUrl =
                        imageUrl
                            .replaceAll('\n', '')
                            .replaceAll('\r', '')
                            .trim();
                    print('Cleaned URL: $imageUrl');

                    return GestureDetector(
                      onTap:
                          () => showImageCarouselModal(
                            context,
                            images,
                            imageIndex,
                            showBoundingBoxes,
                          ),
                      child: Container(
                        width: 200,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              // Image
                              FutureBuilder<String>(
                                future: resolveStorageImageUrl(imageData),
                                builder: (context, snapshot) {
                                  final resolvedUrl = snapshot.data ?? imageUrl;
                                  if (!snapshot.hasData &&
                                      !(resolvedUrl.startsWith('http://') ||
                                          resolvedUrl.startsWith('https://'))) {
                                    return Container(
                                      width: 200,
                                      height: 200,
                                      color: Colors.grey[200],
                                      child: const Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  try {
                                    return Image.network(
                                      resolvedUrl,
                                      width: 200,
                                      height: 200,
                                      fit: BoxFit.contain,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        print(
                                          'Image error for URL: $resolvedUrl',
                                        );
                                        print('Error: $error');
                                        return Container(
                                          width: 200,
                                          height: 200,
                                          color: Colors.grey[300],
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.image_not_supported,
                                                size: 50,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Image Error',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  } catch (e) {
                                    print('Exception loading image: $e');
                                    return Container(
                                      width: 200,
                                      height: 200,
                                      color: Colors.red[100],
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.error,
                                            size: 50,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Image Error',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              ),
                              // Bounding boxes overlay (if available)
                              if (showBoundingBoxes &&
                                  imageData is Map<String, dynamic>) ...[
                                ..._buildBoundingBoxes(imageData),
                              ],
                              // Click indicator overlay
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.fullscreen,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Disease Summary
            if (diseaseSummary.isNotEmpty) ...[
              const Text(
                'Detected Diseases:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children:
                    diseaseSummary.map<Widget>((disease) {
                      final diseaseName = _fixDiseaseName(
                        (disease['name'] ?? 'Unknown').toString(),
                      );
                      final count = disease['count'] ?? 0;
                      final confidence = disease['confidence'];

                      String displayText;
                      if (confidence != null) {
                        displayText =
                            '$diseaseName (${(confidence * 100).toStringAsFixed(1)}%)';
                      } else {
                        displayText =
                            '$diseaseName (${count} detection${count != 1 ? 's' : ''})';
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          displayText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // Expert Review (for completed reports)
            if (isCompleted && expertReview != null) ...[
              const Text(
                'Expert Review:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: _buildExpertReviewWidget(expertReview),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Unknown date';

    try {
      DateTime dateTime;
      if (date is String) {
        dateTime = DateTime.parse(date);
      } else {
        dateTime = date.toDate();
      }
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  void _showImageModal(
    BuildContext context,
    String imageUrl,
    dynamic imageData,
    bool showBoundingBoxes,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // Create local state for the image modal
            bool imageModalShowBoundingBoxes = showBoundingBoxes;
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                height: MediaQuery.of(context).size.height * 0.9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Image View',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              // Bounding Box Toggle for large image
                              Row(
                                children: [
                                  const Text(
                                    'Bounding Boxes',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: imageModalShowBoundingBoxes,
                                    onChanged: (value) {
                                      setModalState(() {
                                        imageModalShowBoundingBoxes = value;
                                      });
                                    },
                                    activeColor: Colors.blue,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Image content
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              // Large image
                              Builder(
                                builder: (context) {
                                  try {
                                    return Image.network(
                                      imageUrl,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.contain,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        return Container(
                                          width: double.infinity,
                                          height: double.infinity,
                                          color: Colors.grey[300],
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.image_not_supported,
                                                size: 100,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'Image Error',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  } catch (e) {
                                    return Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      color: Colors.red[100],
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.error,
                                            size: 100,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Image Error',
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.red[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              ),
                              // Bounding boxes overlay for large image
                              if (imageModalShowBoundingBoxes &&
                                  imageData is Map<String, dynamic>)
                                ..._buildLargeBoundingBoxes(imageData),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void showImageCarouselModal(
    BuildContext context,
    List<dynamic> images,
    int initialIndex,
    bool showBoundingBoxes,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        int currentIndex = initialIndex;
        bool showBoxes = showBoundingBoxes;
        final PageController pageController = PageController(
          initialPage: initialIndex,
        );
        print(
          '[Carousel] open: initialIndex=' +
              initialIndex.toString() +
              ', total=' +
              images.length.toString() +
              ', showBoxes=' +
              showBoundingBoxes.toString(),
        );
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            String _extractImageUrl(dynamic imageData) {
              if (imageData is String) {
                return imageData.trim();
              }
              if (imageData is Map<String, dynamic>) {
                final url =
                    imageData['url'] ??
                    imageData['imageUrl'] ??
                    imageData['image'] ??
                    imageData['src'] ??
                    imageData['link'] ??
                    imageData['downloadURL'] ??
                    imageData['storageURL'] ??
                    '';
                final cleaned =
                    url
                        .toString()
                        .replaceAll('\n', '')
                        .replaceAll('\r', '')
                        .trim();
                print('[Carousel] resolved URL from map: ' + cleaned);
                return cleaned;
              }
              final other = imageData.toString().trim();
              print('[Carousel] resolved URL from other: ' + other);
              return other;
            }

            void goPrev() {
              if (currentIndex > 0) {
                print('[Carousel] goPrev from ' + currentIndex.toString());
                pageController.previousPage(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                );
              }
            }

            void goNext() {
              if (currentIndex < images.length - 1) {
                print('[Carousel] goNext from ' + currentIndex.toString());
                pageController.nextPage(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                );
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                height: MediaQuery.of(context).size.height * 0.9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Previous',
                                onPressed: currentIndex > 0 ? goPrev : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Text(
                                'Image ${currentIndex + 1} of ${images.length}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next',
                                onPressed:
                                    currentIndex < images.length - 1
                                        ? goNext
                                        : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              // Bounding Box Toggle for large image (modal state)
                              Row(
                                children: [
                                  const Text(
                                    'Bounding Boxes',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: showBoxes,
                                    onChanged: (v) {
                                      print(
                                        '[Carousel] toggle boxes -> ' +
                                            v.toString(),
                                      );
                                      setModalState(() {
                                        showBoxes = v;
                                      });
                                    },
                                    activeColor: Colors.blue,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Image content
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              PageView.builder(
                                controller: pageController,
                                itemCount: images.length,
                                onPageChanged: (idx) {
                                  setModalState(() {
                                    currentIndex = idx;
                                  });
                                  print(
                                    '[Carousel] onPageChanged -> ' +
                                        idx.toString(),
                                  );
                                },
                                itemBuilder: (context, idx) {
                                  final dynamic pageImageData = images[idx];
                                  final String pageUrl = _extractImageUrl(
                                    pageImageData,
                                  );
                                  print(
                                    '[Carousel] build page idx=' +
                                        idx.toString(),
                                  );
                                  return Stack(
                                    children: [
                                      FutureBuilder<String>(
                                        future: resolveStorageImageUrl(
                                          pageImageData,
                                        ),
                                        builder: (context, snapshot) {
                                          final url = snapshot.data ?? pageUrl;
                                          if (!snapshot.hasData &&
                                              !(url.startsWith('http://') ||
                                                  url.startsWith('https://'))) {
                                            return Center(
                                              child: SizedBox(
                                                width: 28,
                                                height: 28,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            );
                                          }
                                          try {
                                            return Image.network(
                                              url,
                                              width: double.infinity,
                                              height: double.infinity,
                                              fit: BoxFit.contain,
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) {
                                                return Container(
                                                  width: double.infinity,
                                                  height: double.infinity,
                                                  color: Colors.grey[300],
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .image_not_supported,
                                                        size: 100,
                                                        color: Colors.grey,
                                                      ),
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                      Text(
                                                        'Image Error',
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          color:
                                                              Colors.grey[600],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            );
                                          } catch (e) {
                                            return Container(
                                              width: double.infinity,
                                              height: double.infinity,
                                              color: Colors.red[100],
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.error,
                                                    size: 100,
                                                    color: Colors.red,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    'Image Error',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      color: Colors.red[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                      if (showBoxes &&
                                          pageImageData is Map<String, dynamic>)
                                        ..._buildLargeBoundingBoxes(
                                          pageImageData,
                                        ),
                                      // Left/right overlay tap zones
                                      Positioned.fill(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap:
                                                    currentIndex > 0
                                                        ? () {
                                                          print(
                                                            '[Carousel] left overlay tap',
                                                          );
                                                          goPrev();
                                                        }
                                                        : null,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          8.0,
                                                        ),
                                                    child: Icon(
                                                      Icons.chevron_left,
                                                      size: 36,
                                                      color:
                                                          currentIndex > 0
                                                              ? Colors.black54
                                                              : Colors
                                                                  .transparent,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap:
                                                    currentIndex <
                                                            images.length - 1
                                                        ? () {
                                                          print(
                                                            '[Carousel] right overlay tap',
                                                          );
                                                          goNext();
                                                        }
                                                        : null,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          8.0,
                                                        ),
                                                    child: Icon(
                                                      Icons.chevron_right,
                                                      size: 36,
                                                      color:
                                                          currentIndex <
                                                                  images.length -
                                                                      1
                                                              ? Colors.black54
                                                              : Colors
                                                                  .transparent,
                                                    ),
                                                  ),
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildLargeBoundingBoxes(Map<String, dynamic> imageData) {
    final results = imageData['results'] as List<dynamic>? ?? [];

    // Get actual image dimensions from the data
    final imageWidth =
        (imageData['imageWidth'] as double?) ??
        (imageData['imageWidth'] as int?)?.toDouble() ??
        4064.0;
    final imageHeight =
        (imageData['imageHeight'] as double?) ??
        (imageData['imageHeight'] as int?)?.toDouble() ??
        3048.0;

    return results.map<Widget>((result) {
      final boundingBox = result['boundingBox'] as Map<String, dynamic>?;
      if (boundingBox == null) {
        return const SizedBox.shrink();
      }

      // Get original coordinates
      final originalLeft =
          (boundingBox['left'] as double?) ??
          (boundingBox['left'] as int?)?.toDouble() ??
          0.0;
      final originalTop =
          (boundingBox['top'] as double?) ??
          (boundingBox['top'] as int?)?.toDouble() ??
          0.0;
      final originalRight =
          (boundingBox['right'] as double?) ??
          (boundingBox['right'] as int?)?.toDouble() ??
          0.0;
      final originalBottom =
          (boundingBox['bottom'] as double?) ??
          (boundingBox['bottom'] as int?)?.toDouble() ??
          0.0;

      final disease = _fixDiseaseName(
        result['disease'] as String? ?? 'Unknown',
      );
      final confidence = result['confidence'] as double? ?? 0.0;

      return LayoutBuilder(
        builder: (context, constraints) {
          // For BoxFit.cover, we need to calculate the actual displayed image size
          // and its position within the container
          final containerWidth = constraints.maxWidth;
          final containerHeight = constraints.maxHeight;

          // Calculate the scale to fit the image in the container while maintaining aspect ratio
          final scaleX = containerWidth / imageWidth;
          final scaleY = containerHeight / imageHeight;
          final scale =
              scaleX < scaleY
                  ? scaleX
                  : scaleY; // Use the smaller scale for contain

          // Calculate the actual displayed image dimensions
          final displayedWidth = imageWidth * scale;
          final displayedHeight = imageHeight * scale;

          // Calculate the offset to center the image
          final offsetX = (containerWidth - displayedWidth) / 2;
          final offsetY = (containerHeight - displayedHeight) / 2;

          // Scale coordinates and apply offset
          final left = (originalLeft * scale) + offsetX;
          final top = (originalTop * scale) + offsetY;
          final right = (originalRight * scale) + offsetX;
          final bottom = (originalBottom * scale) + offsetY;

          final width = right - left;
          final height = bottom - top;

          return Stack(
            children: [
              // Large bounding box
              Positioned(
                left: left,
                top: top,
                child: Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _colorForDisease(disease),
                      width: 4,
                    ),
                    color: _colorForDisease(disease).withOpacity(0.1),
                  ),
                ),
              ),
              // Large disease label
              Positioned(
                left: left - 10,
                top: top - 40,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _colorForDisease(disease).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    '${_fixDiseaseName(disease).substring(0, _fixDiseaseName(disease).length > 20 ? 20 : _fixDiseaseName(disease).length)}\n${(confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }).toList();
  }

  List<Widget> _buildBoundingBoxes(Map<String, dynamic> imageData) {
    final results = imageData['results'] as List<dynamic>? ?? [];

    // Get actual image dimensions from the data
    final imageWidth =
        (imageData['imageWidth'] as double?) ??
        (imageData['imageWidth'] as int?)?.toDouble() ??
        4064.0;
    final imageHeight =
        (imageData['imageHeight'] as double?) ??
        (imageData['imageHeight'] as int?)?.toDouble() ??
        3048.0;

    // Debug: Print image dimensions
    print('=== BOUNDING BOX DEBUG ===');
    print('Image data: $imageData');
    print('Image width: $imageWidth, height: $imageHeight');
    print('Results count: ${results.length}');

    // For BoxFit.contain, we need to calculate the actual displayed image size
    // and its position within the 200x200 container
    final containerWidth = 200.0;
    final containerHeight = 200.0;

    // Calculate the scale to fit the image in the container while maintaining aspect ratio
    final scaleX = containerWidth / imageWidth;
    final scaleY = containerHeight / imageHeight;
    final scale =
        scaleX < scaleY ? scaleX : scaleY; // Use the smaller scale for contain

    // Calculate the actual displayed image dimensions
    final displayedWidth = imageWidth * scale;
    final displayedHeight = imageHeight * scale;

    // Calculate the offset to center the image
    final offsetX = (containerWidth - displayedWidth) / 2;
    final offsetY = (containerHeight - displayedHeight) / 2;

    print('Scale factors: scaleX=$scaleX, scaleY=$scaleY, final scale=$scale');
    print('Displayed size: ${displayedWidth}x${displayedHeight}');
    print('Offset: $offsetX, $offsetY');

    return results.map<Widget>((result) {
      final boundingBox = result['boundingBox'] as Map<String, dynamic>?;
      if (boundingBox == null) {
        print('No bounding box found in result: $result');
        return const SizedBox.shrink();
      }

      // Get original coordinates
      final originalLeft =
          (boundingBox['left'] as double?) ??
          (boundingBox['left'] as int?)?.toDouble() ??
          0.0;
      final originalTop =
          (boundingBox['top'] as double?) ??
          (boundingBox['top'] as int?)?.toDouble() ??
          0.0;
      final originalRight =
          (boundingBox['right'] as double?) ??
          (boundingBox['right'] as int?)?.toDouble() ??
          0.0;
      final originalBottom =
          (boundingBox['bottom'] as double?) ??
          (boundingBox['bottom'] as int?)?.toDouble() ??
          0.0;

      // Scale coordinates and apply offset
      final left = (originalLeft * scale) + offsetX;
      final top = (originalTop * scale) + offsetY;
      final right = (originalRight * scale) + offsetX;
      final bottom = (originalBottom * scale) + offsetY;

      final width = right - left;
      final height = bottom - top;

      final disease = _fixDiseaseName(
        result['disease'] as String? ?? 'Unknown',
      );
      final confidence = result['confidence'] as double? ?? 0.0;

      print(
        'Original coords: left=$originalLeft, top=$originalTop, right=$originalRight, bottom=$originalBottom',
      );
      print(
        'Scaled coords: left=$left, top=$top, width=$width, height=$height',
      );
      print('Disease: $disease, Confidence: $confidence');
      print('========================');

      return Stack(
        children: [
          // Accurate bounding box (no labels inside)
          Positioned(
            left: left,
            top: top,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                border: Border.all(color: diseaseColor(disease), width: 3),
                color: diseaseColor(disease).withOpacity(0.1),
              ),
            ),
          ),
          // Single disease label outside the box (top-left)
          Positioned(
            left: left - 5,
            top: top - 25,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: diseaseColor(disease).withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                '${disease.substring(0, disease.length > 15 ? 15 : disease.length)}\n${(confidence * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }).toList();
  }
}

class ReportsModalContent extends StatefulWidget {
  final ValueNotifier<bool>? fullscreenNotifier;
  const ReportsModalContent({Key? key, this.fullscreenNotifier})
    : super(key: key);

  @override
  _ReportsModalContentState createState() => _ReportsModalContentState();
}

class _ReportsModalContentState extends State<ReportsModalContent>
    with SingleTickerProviderStateMixin {
  // Access the shared date range picker from reports
  Future<DateTimeRange?> _pickRange(
    BuildContext context,
    DateTimeRange initial,
  ) {
    return pickDateRangeWithSf(context, initial: initial);
  }

  final ValueNotifier<bool> _showBoundingBoxesNotifier = ValueNotifier(false);
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedDisease = 'All';
  // Expert is filtered via search only
  String _selectedExpert = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  late Future<List<Map<String, dynamic>>> _completedReportsFuture;
  late Future<List<Map<String, dynamic>>> _pendingReportsFuture;
  late TabController _tabController;
  final ScrollController _completedScrollController = ScrollController();
  final ScrollController _pendingScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Cache futures so typing in the search field doesn't re-fetch or refresh the modal
    _completedReportsFuture = _getCompletedReports();
    _pendingReportsFuture = _getPendingReports();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _showBoundingBoxesNotifier.dispose();
    _searchController.dispose();
    _tabController.dispose();
    _completedScrollController.dispose();
    _pendingScrollController.dispose();
    super.dispose();
  }

  String _fixDiseaseName(String disease) {
    // Normalize separators and case for robust comparisons
    final String raw = (disease).toString();
    final String normalized =
        raw.replaceAll(RegExp(r'[_\-]+'), ' ').trim().toLowerCase();

    // Fix common spelling issues
    if (normalized == 'backterial b' ||
        normalized == 'backterial blackspot' ||
        normalized == 'bacterial b') {
      return 'bacterial_blackspot';
    }

    // Map all tip burn variants to Unknown
    if (normalized == 'tip burn' || normalized == 'tipburn') {
      return 'Unknown';
    }

    return raw;
  }

  List<Widget> _buildRecommendationsList(dynamic recommendations) {
    if (recommendations == null) return [];

    if (recommendations is List) {
      return recommendations.map<Widget>((rec) {
        if (rec is Map<String, dynamic>) {
          final treatment = rec['treatment'] ?? '';
          final dosage = rec['dosage'] ?? '';
          final frequency = rec['frequency'] ?? '';
          final duration = rec['duration'] ?? '';

          String displayText = '';
          if (treatment.isNotEmpty) displayText += 'Treatment: $treatment';
          if (dosage.isNotEmpty)
            displayText +=
                '${displayText.isNotEmpty ? ', ' : ''}Dosage: $dosage';
          if (frequency.isNotEmpty)
            displayText +=
                '${displayText.isNotEmpty ? ', ' : ''}Frequency: $frequency';
          if (duration.isNotEmpty)
            displayText +=
                '${displayText.isNotEmpty ? ', ' : ''}Duration: $duration';

          if (displayText.isEmpty) displayText = 'No details available';

          return Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Text(
              '• $displayText',
              style: const TextStyle(fontSize: 11, color: Colors.green),
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Text(
              '• ${rec.toString()}',
              style: const TextStyle(fontSize: 11, color: Colors.green),
            ),
          );
        }
      }).toList();
    } else {
      return [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Text(
            '• ${recommendations.toString()}',
            style: const TextStyle(fontSize: 11, color: Colors.green),
          ),
        ),
      ];
    }
  }

  List<Widget> _buildPreventiveMeasuresList(dynamic preventiveMeasures) {
    if (preventiveMeasures == null) return [];

    if (preventiveMeasures is List) {
      return preventiveMeasures.map<Widget>((measure) {
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Text(
            '• ${measure.toString()}',
            style: const TextStyle(fontSize: 11, color: Colors.green),
          ),
        );
      }).toList();
    } else {
      return [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Text(
            '• ${preventiveMeasures.toString()}',
            style: const TextStyle(fontSize: 11, color: Colors.green),
          ),
        ),
      ];
    }
  }

  List<String> _computeDiseaseOptions(List<Map<String, dynamic>> reports) {
    final Set<String> diseaseSet = {};
    for (final report in reports) {
      final List<dynamic> diseaseSummary =
          (report['diseaseSummary'] as List<dynamic>?) ?? const [];
      for (final dynamic disease in diseaseSummary) {
        if (disease is Map<String, dynamic>) {
          final String name = _fixDiseaseName(
            (disease['name'] ?? '').toString().trim(),
          );
          if (name.isNotEmpty) {
            diseaseSet.add(name);
          }
        }
      }
    }
    final List<String> options = ['All', ...diseaseSet.toList()..sort()];
    // Ensure currently selected option is valid
    if (!options.contains(_selectedDisease)) {
      _selectedDisease = 'All';
    }
    return options;
  }

  // Expert options dropdown removed; filter by expert through search only

  Future<void> _pickFromDate() async {
    final DateTime now = DateTime.now();
    final DateTime initial = _fromDate ?? (_toDate != null ? _toDate! : now);
    DateTime? start = initial;
    DateTime? end = _toDate ?? now;
    // Reuse the unified Syncfusion range picker dialog from reports
    final result = await pickDateRangeWithSf(
      context,
      initial: DateTimeRange(start: start, end: end),
    );
    if (result != null) {
      setState(() {
        _fromDate = DateTime(
          result.start.year,
          result.start.month,
          result.start.day,
        );
        _toDate = DateTime(result.end.year, result.end.month, result.end.day);
      });
    }
  }

  Future<void> _pickToDate() async {
    final DateTime now = DateTime.now();
    final DateTime initial = _toDate ?? (_fromDate != null ? _fromDate! : now);
    DateTime? start = _fromDate ?? now;
    DateTime? end = initial;
    final result = await pickDateRangeWithSf(
      context,
      initial: DateTimeRange(start: start, end: end),
    );
    if (result != null) {
      setState(() {
        _fromDate = DateTime(
          result.start.year,
          result.start.month,
          result.start.day,
        );
        _toDate = DateTime(result.end.year, result.end.month, result.end.day);
      });
    }
  }

  String _formatDateOnly(DateTime? date) {
    if (date == null) return 'Select';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> reports) {
    final String query = _searchQuery.trim().toLowerCase();
    final String selectedDiseaseLower = _selectedDisease.toLowerCase();
    final String selectedExpertLower = _selectedExpert.toLowerCase();

    final List<Map<String, dynamic>> filtered =
        reports.where((report) {
          final String userName =
              (report['userName'] ?? '').toString().toLowerCase();
          final List<dynamic> diseaseSummary =
              (report['diseaseSummary'] as List<dynamic>?) ?? const [];
          final dynamic expertReview = report['expertReview'];
          String expertName = '';
          if (expertReview is Map<String, dynamic>) {
            expertName = (expertReview['expertName'] ?? '').toString();
          } else if (expertReview is String) {
            expertName = expertReview;
          }
          final String expertNameLower = expertName.toLowerCase();
          final DateTime createdDate = _parseDate(report['createdAt']);

          bool matchesSearch = true;
          if (query.isNotEmpty) {
            final bool userMatches = userName.contains(query);
            final bool diseaseMatches = diseaseSummary.any((d) {
              if (d is Map<String, dynamic>) {
                final String name =
                    _fixDiseaseName((d['name'] ?? '').toString()).toLowerCase();
                return name.contains(query) ||
                    (name == 'unknown' && 'unknown'.contains(query));
              }
              return false;
            });
            final bool expertMatches = expertNameLower.contains(query);
            // Build flexible date variants to tolerate padded/unpadded day/month
            // and 2-digit or 4-digit years.
            final String dd = createdDate.day.toString().padLeft(2, '0');
            final String d = createdDate.day.toString();
            final String mm = createdDate.month.toString().padLeft(2, '0');
            final String m = createdDate.month.toString();
            final String y4 = createdDate.year.toString();
            final String y2 = y4.substring(2);
            final List<String> dateVariants =
                [
                  '$dd/$mm/$y4',
                  '$d/$m/$y4',
                  '$dd/$m/$y4',
                  '$d/$mm/$y4',
                  '$dd/$mm/$y2',
                  '$d/$m/$y2',
                  '$dd/$m/$y2',
                  '$d/$mm/$y2',
                ].map((s) => s.toLowerCase()).toList();
            final bool dateTextMatches = dateVariants.any(
              (s) => s.contains(query),
            );

            matchesSearch =
                userMatches ||
                diseaseMatches ||
                expertMatches ||
                dateTextMatches;
          }

          bool matchesDisease = true;
          if (_selectedDisease != 'All') {
            matchesDisease = diseaseSummary.any((d) {
              if (d is Map<String, dynamic>) {
                final String name =
                    _fixDiseaseName((d['name'] ?? '').toString()).toLowerCase();
                return name == selectedDiseaseLower;
              }
              return false;
            });
          }

          bool matchesExpert = true;
          if (_selectedExpert != 'All') {
            matchesExpert = expertNameLower == selectedExpertLower;
          }

          bool matchesDate = true;
          if (_fromDate != null) {
            final DateTime from = DateTime(
              _fromDate!.year,
              _fromDate!.month,
              _fromDate!.day,
            );
            if (createdDate.isBefore(from)) matchesDate = false;
          }
          if (matchesDate && _toDate != null) {
            final DateTime to = DateTime(
              _toDate!.year,
              _toDate!.month,
              _toDate!.day,
              23,
              59,
              59,
              999,
            );
            if (createdDate.isAfter(to)) matchesDate = false;
          }

          return matchesSearch &&
              matchesDisease &&
              matchesExpert &&
              matchesDate;
        }).toList();

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Reports Overview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                // Bounding Box Toggle
                Row(
                  children: [
                    const Text(
                      'Bounding Boxes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<bool>(
                      valueListenable: _showBoundingBoxesNotifier,
                      builder:
                          (context, value, _) => Switch(
                            value: value,
                            onChanged: (val) {
                              _showBoundingBoxesNotifier.value = val;
                            },
                            activeColor: Colors.blue,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                if (widget.fullscreenNotifier != null)
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.fullscreenNotifier!,
                    builder:
                        (context, isFull, _) => IconButton(
                          tooltip: isFull ? 'Exit Fullscreen' : 'Fullscreen',
                          icon: Icon(
                            isFull ? Icons.fullscreen_exit : Icons.fullscreen,
                          ),
                          onPressed:
                              () => widget.fullscreenNotifier!.value = !isFull,
                        ),
                  ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Tab Bar
        Expanded(
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.black87,
                  labelPadding: EdgeInsets.zero,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: EdgeInsets.zero,
                  indicator: const BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  tabs: const [
                    Tab(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        child: Text('Completed Reports'),
                      ),
                    ),
                    Tab(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        child: Text('Pending Reports'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tab Content
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _showBoundingBoxesNotifier,
                  builder:
                      (context, value, _) => TabBarView(
                        controller: _tabController,
                        children: [
                          _buildCompletedReportsTab(value),
                          _buildPendingReportsTab(value),
                        ],
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedReportsTab(bool showBoundingBoxes) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _completedReportsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final reports = snapshot.data ?? [];

        if (reports.isEmpty) {
          return const Center(
            child: Text(
              'No completed reports found',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        final List<String> diseaseOptions = _computeDiseaseOptions(reports);
        final List<Map<String, dynamic>> filteredReports = _applyFilters(
          reports,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText:
                          'Search by user, disease, expert, or date (dd/mm/yyyy)...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _selectedDisease,
                  items:
                      diseaseOptions
                          .map(
                            (d) => DropdownMenuItem<String>(
                              value: d,
                              child: Text(d),
                            ),
                          )
                          .toList(),
                  onChanged:
                      (value) =>
                          setState(() => _selectedDisease = value ?? 'All'),
                ),
                // Expert can be filtered via search; no extra dropdown
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFromDate,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _fromDate != null && _toDate != null
                        ? '${_formatDateOnly(_fromDate)} to ${_formatDateOnly(_toDate)}'
                        : 'Pick date range',
                  ),
                ),
                const SizedBox(width: 8),
                if (_fromDate != null || _toDate != null)
                  TextButton(
                    onPressed:
                        () => setState(() {
                          _fromDate = null;
                          _toDate = null;
                        }),
                    child: const Text('Clear dates'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: _completedScrollController,
                itemCount: filteredReports.length,
                itemBuilder: (context, index) {
                  final report = filteredReports[index];
                  return _buildReportCard(report, true, showBoundingBoxes);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPendingReportsTab(bool showBoundingBoxes) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _pendingReportsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final reports = snapshot.data ?? [];

        if (reports.isEmpty) {
          return const Center(
            child: Text(
              'No pending reports found',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        final List<String> diseaseOptions = _computeDiseaseOptions(reports);
        final List<Map<String, dynamic>> filteredReports = _applyFilters(
          reports,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText:
                          'Search by user, disease, expert, or date (dd/mm/yyyy)...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _selectedDisease,
                  items:
                      diseaseOptions
                          .map(
                            (d) => DropdownMenuItem<String>(
                              value: d,
                              child: Text(d),
                            ),
                          )
                          .toList(),
                  onChanged:
                      (value) =>
                          setState(() => _selectedDisease = value ?? 'All'),
                ),
                // Expert can be filtered via search; no extra dropdown
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFromDate,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _fromDate != null && _toDate != null
                        ? '${_formatDateOnly(_fromDate)} to ${_formatDateOnly(_toDate)}'
                        : 'Pick date range',
                  ),
                ),
                const SizedBox(width: 8),
                if (_fromDate != null || _toDate != null)
                  TextButton(
                    onPressed:
                        () => setState(() {
                          _fromDate = null;
                          _toDate = null;
                        }),
                    child: const Text('Clear dates'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: _pendingScrollController,
                itemCount: filteredReports.length,
                itemBuilder: (context, index) {
                  final report = filteredReports[index];
                  return _buildReportCard(report, false, showBoundingBoxes);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getCompletedReports() async {
    try {
      final allReports = await ScanRequestsService.getScanRequests();
      final completedReports =
          allReports
              .where((report) => report['status'] == 'completed')
              .toList();

      // Sort by createdAt date in descending order (most recent first)
      completedReports.sort((a, b) {
        final aDate = _parseDate(a['createdAt']);
        final bDate = _parseDate(b['createdAt']);
        return bDate.compareTo(aDate); // Descending order
      });

      return completedReports;
    } catch (e) {
      print('Error getting completed reports: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getPendingReports() async {
    try {
      final allReports = await ScanRequestsService.getScanRequests();
      final pendingReports =
          allReports.where((report) => report['status'] == 'pending').toList();

      // Sort by createdAt date in descending order (most recent first)
      pendingReports.sort((a, b) {
        final aDate = _parseDate(a['createdAt']);
        final bDate = _parseDate(b['createdAt']);
        return bDate.compareTo(aDate); // Descending order
      });

      return pendingReports;
    } catch (e) {
      print('Error getting pending reports: $e');
      return [];
    }
  }

  DateTime _parseDate(dynamic date) {
    if (date is Timestamp) {
      return date.toDate();
    } else if (date is String) {
      return DateTime.tryParse(date) ?? DateTime.now();
    } else {
      return DateTime.now();
    }
  }

  Widget _buildReportCard(
    Map<String, dynamic> report,
    bool isCompleted,
    bool showBoundingBoxes,
  ) {
    final userName = report['userName'] ?? 'Unknown User';
    final createdAt = report['createdAt'];
    final reviewedAt = report['reviewedAt'];
    final images = report['images'] ?? [];
    final diseaseSummary = report['diseaseSummary'] ?? [];
    final expertReview = report['expertReview'];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        () {
                          final dt = _parseDate(createdAt);
                          String month(int m) =>
                              const [
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
                              ][m - 1];
                          final hh = dt.hour.toString().padLeft(2, '0');
                          final mm = dt.minute.toString().padLeft(2, '0');
                          return 'Submitted: ${month(dt.month)} ${dt.day} ${dt.year} $hh:$mm';
                        }(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      if (isCompleted && reviewedAt != null) ...[
                        Text(
                          () {
                            final dt = _parseDate(reviewedAt);
                            String month(int m) =>
                                const [
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
                                ][m - 1];
                            final hh = dt.hour.toString().padLeft(2, '0');
                            final mm = dt.minute.toString().padLeft(2, '0');
                            return 'Reviewed: ${month(dt.month)} ${dt.day} ${dt.year} $hh:$mm';
                          }(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          () {
                            final submitted = _parseDate(createdAt);
                            final reviewed = _parseDate(reviewedAt);
                            Duration d = reviewed.difference(submitted);
                            int totalMinutes = d.inMinutes.abs();
                            final days = totalMinutes ~/ (24 * 60);
                            totalMinutes %= (24 * 60);
                            final hours = totalMinutes ~/ 60;
                            final minutes = totalMinutes % 60;
                            final parts = <String>[];
                            if (days > 0)
                              parts.add('$days day${days == 1 ? '' : 's'}');
                            if (hours > 0)
                              parts.add('$hours hour${hours == 1 ? '' : 's'}');
                            if (minutes > 0 || parts.isEmpty)
                              parts.add(
                                '$minutes min${minutes == 1 ? '' : 's'}',
                              );
                            return 'Turnaround: ${parts.join(' ')}';
                          }(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCompleted ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isCompleted ? 'Completed' : 'Pending',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Images with bounding boxes
            if (images.isNotEmpty) ...[
              const Text(
                'Images:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  itemBuilder: (context, imageIndex) {
                    final imageData = images[imageIndex];
                    String imageUrl = '';

                    // Debug: Print the image data structure
                    print('Image data at index $imageIndex: $imageData');
                    print('Image data type: ${imageData.runtimeType}');

                    // Handle different image data structures
                    if (imageData is String) {
                      imageUrl = imageData;
                      print('Using string URL: $imageUrl');
                    } else if (imageData is Map<String, dynamic>) {
                      // Try different possible field names for the URL
                      imageUrl =
                          imageData['url'] ??
                          imageData['imageUrl'] ??
                          imageData['image'] ??
                          imageData['src'] ??
                          imageData['link'] ??
                          imageData['downloadURL'] ??
                          imageData['storageURL'] ??
                          imageData.toString();
                      print('Using map URL: $imageUrl');
                    } else {
                      imageUrl = imageData.toString();
                      print('Using toString URL: $imageUrl');
                    }

                    // Clean up the URL - remove line breaks and extra spaces
                    imageUrl =
                        imageUrl
                            .replaceAll('\n', '')
                            .replaceAll('\r', '')
                            .trim();
                    print('Cleaned URL: $imageUrl');

                    return GestureDetector(
                      onTap:
                          () => showImageCarouselModal(
                            context,
                            images,
                            imageIndex,
                            showBoundingBoxes,
                          ),
                      child: Container(
                        width: 200,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              // Image
                              Builder(
                                builder: (context) {
                                  try {
                                    return Image.network(
                                      imageUrl,
                                      width: 200,
                                      height: 200,
                                      fit: BoxFit.contain,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        print('Image error for URL: $imageUrl');
                                        print('Error: $error');
                                        return Container(
                                          width: 200,
                                          height: 200,
                                          color: Colors.grey[300],
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.image_not_supported,
                                                size: 50,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Image Error',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  } catch (e) {
                                    print('Exception loading image: $e');
                                    return Container(
                                      width: 200,
                                      height: 200,
                                      color: Colors.red[100],
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.error,
                                            size: 50,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Image Error',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              ),
                              // Bounding boxes overlay (if available)
                              if (showBoundingBoxes &&
                                  imageData is Map<String, dynamic>) ...[
                                ..._buildBoundingBoxes(imageData),
                              ],
                              // Click indicator overlay
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.fullscreen,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Disease Summary
            if (diseaseSummary.isNotEmpty) ...[
              const Text(
                'Detected Diseases:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children:
                    diseaseSummary.map<Widget>((disease) {
                      final diseaseName = _fixDiseaseName(
                        (disease['name'] ?? 'Unknown').toString(),
                      );
                      final count = disease['count'] ?? 0;
                      final confidence = disease['confidence'];

                      String displayText;
                      if (confidence != null) {
                        displayText =
                            '$diseaseName (${(confidence * 100).toStringAsFixed(1)}%)';
                      } else {
                        displayText =
                            '$diseaseName (${count} detection${count != 1 ? 's' : ''})';
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          displayText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // Expert Review (for completed reports)
            if (isCompleted && expertReview != null) ...[
              const Text(
                'Expert Review:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: _buildExpertReviewWidget(expertReview),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Unknown date';

    try {
      DateTime dateTime;
      if (date is String) {
        dateTime = DateTime.parse(date);
      } else {
        dateTime = date.toDate();
      }
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  Widget _buildExpertReviewWidget(dynamic expertReview) {
    try {
      if (expertReview == null) {
        return const Text(
          'No expert review available.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        );
      }

      // Debug: Print the actual data structure
      print('Expert review data type: ${expertReview.runtimeType}');
      print('Expert review data: $expertReview');

      // If it's already a Map (most likely case)
      if (expertReview is Map<String, dynamic>) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (expertReview['expertName'] != null) ...[
              Text(
                'Expert: ${expertReview['expertName']}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (expertReview['comment'] != null &&
                expertReview['comment'].toString().isNotEmpty) ...[
              Text(
                'Comment: ${expertReview['comment']}',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
              const SizedBox(height: 4),
            ],
            if (expertReview['severityAssessment'] != null) ...[
              Builder(
                builder: (context) {
                  final severity = expertReview['severityAssessment'];
                  if (severity is Map<String, dynamic> &&
                      severity['level'] != null) {
                    return Text(
                      'Severity: ${severity['level']}',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    );
                  } else if (severity is String) {
                    return Text(
                      'Severity: $severity',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: 4),
            ],
            if (expertReview['treatmentPlan'] != null) ...[
              Builder(
                builder: (context) {
                  final treatmentPlan = expertReview['treatmentPlan'];
                  if (treatmentPlan is Map<String, dynamic>) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (treatmentPlan['recommendations'] != null) ...[
                          Text(
                            'Recommendations:',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ..._buildRecommendationsList(
                            treatmentPlan['recommendations'],
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (treatmentPlan['preventiveMeasures'] != null) ...[
                          Text(
                            'Preventive Measures:',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ..._buildPreventiveMeasuresList(
                            treatmentPlan['preventiveMeasures'],
                          ),
                          const SizedBox(height: 4),
                        ],
                      ],
                    );
                  } else {
                    return Text(
                      'Treatment Plan: $treatmentPlan',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    );
                  }
                },
              ),
              const SizedBox(height: 4),
            ],
          ],
        );
      }

      // Try to parse as JSON string
      if (expertReview is String) {
        try {
          // Remove any extra formatting and parse
          final cleanString = expertReview.replaceAll(RegExp(r'[{}]'), '');
          final parts = cleanString.split(',');

          Map<String, String> reviewData = {};
          for (String part in parts) {
            final keyValue = part.split(':');
            if (keyValue.length >= 2) {
              final key = keyValue[0].trim();
              final value = keyValue.sublist(1).join(':').trim();
              reviewData[key] = value;
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reviewData['expertName'] != null) ...[
                Text(
                  'Expert: ${reviewData['expertName']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (reviewData['comment'] != null &&
                  reviewData['comment']!.isNotEmpty) ...[
                Text(
                  'Comment: ${reviewData['comment']}',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
                const SizedBox(height: 4),
              ],
              if (reviewData['severityAssessment'] != null) ...[
                Text(
                  'Severity: ${reviewData['severityAssessment']}',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
                const SizedBox(height: 4),
              ],
              if (reviewData['treatmentPlan'] != null) ...[
                Text(
                  'Treatment Plan: ${reviewData['treatmentPlan']}',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
                const SizedBox(height: 4),
              ],
            ],
          );
        } catch (e) {
          // If parsing fails, show as plain text
          return Text(
            expertReview,
            style: TextStyle(fontSize: 14, color: Colors.green[700]),
          );
        }
      }

      return Text(
        expertReview.toString(),
        style: TextStyle(fontSize: 14, color: Colors.green[700]),
      );
    } catch (e) {
      return Text(
        'Error parsing expert review: $e',
        style: TextStyle(fontSize: 14, color: Colors.red[600]),
      );
    }
  }

  void _showEnlargedImageModal(
    BuildContext context,
    String imageUrl,
    dynamic imageData,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                height: MediaQuery.of(context).size.height * 0.9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Image View',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              // Bounding Box Toggle for large image
                              Row(
                                children: [
                                  const Text(
                                    'Bounding Boxes',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: _showBoundingBoxesNotifier,
                                    builder:
                                        (context, value, _) => Switch(
                                          value: value,
                                          onChanged: (val) {
                                            _showBoundingBoxesNotifier.value =
                                                val;
                                          },
                                          activeColor: Colors.blue,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Image content
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              // Large image
                              Builder(
                                builder: (context) {
                                  try {
                                    return Image.network(
                                      imageUrl,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.contain,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        return Container(
                                          width: double.infinity,
                                          height: double.infinity,
                                          color: Colors.grey[300],
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.image_not_supported,
                                                size: 100,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'Image Error',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  } catch (e) {
                                    return Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      color: Colors.red[100],
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.error,
                                            size: 100,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Image Error',
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.red[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              ),
                              // Bounding boxes overlay for large image
                              ValueListenableBuilder<bool>(
                                valueListenable: _showBoundingBoxesNotifier,
                                builder: (context, value, _) {
                                  if (value &&
                                      imageData is Map<String, dynamic>) {
                                    return Stack(
                                      children: _buildLargeBoundingBoxes(
                                        imageData,
                                      ),
                                    );
                                  } else {
                                    return const SizedBox.shrink();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void showImageCarouselModal(
    BuildContext context,
    List<dynamic> images,
    int initialIndex,
    bool showBoundingBoxes,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        int currentIndex = initialIndex;

        String _extractImageUrl(dynamic imageData) {
          if (imageData is String) {
            return imageData.trim();
          }
          if (imageData is Map<String, dynamic>) {
            final url =
                imageData['url'] ??
                imageData['imageUrl'] ??
                imageData['image'] ??
                imageData['src'] ??
                imageData['link'] ??
                imageData['downloadURL'] ??
                imageData['storageURL'] ??
                '';
            return url
                .toString()
                .replaceAll('\n', '')
                .replaceAll('\r', '')
                .trim();
          }
          return imageData.toString().trim();
        }

        void goPrev() {
          if (currentIndex > 0) {
            final int target = currentIndex - 1;
            setState(() {
              currentIndex = target;
            });
          }
        }

        void goNext() {
          if (currentIndex < images.length - 1) {
            final int target = currentIndex + 1;
            setState(() {
              currentIndex = target;
            });
          }
        }

        final dynamic currentImageData = images[currentIndex];
        final String imageUrl = _extractImageUrl(currentImageData);

        bool imageModalShowBoundingBoxes = showBoundingBoxes;

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                final dynamic currentImageData = images[currentIndex];
                final String imageUrl = _extractImageUrl(currentImageData);
                return Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Previous',
                                onPressed:
                                    currentIndex > 0
                                        ? () => setModalState(() {
                                          goPrev();
                                        })
                                        : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Text(
                                'Image ${currentIndex + 1} of ${images.length}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next',
                                onPressed:
                                    currentIndex < images.length - 1
                                        ? () => setModalState(() {
                                          goNext();
                                        })
                                        : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              // Bounding Box Toggle for large image
                              Row(
                                children: [
                                  const Text(
                                    'Bounding Boxes',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: imageModalShowBoundingBoxes,
                                    onChanged: (value) {
                                      setModalState(() {
                                        imageModalShowBoundingBoxes = value;
                                      });
                                    },
                                    activeColor: Colors.blue,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Image content
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              // Large image
                              Builder(
                                builder: (context) {
                                  try {
                                    return Image.network(
                                      imageUrl,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.contain,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        return Container(
                                          width: double.infinity,
                                          height: double.infinity,
                                          color: Colors.grey[300],
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.image_not_supported,
                                                size: 100,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'Image Error',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  } catch (e) {
                                    return Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      color: Colors.red[100],
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.error,
                                            size: 100,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Image Error',
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.red[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              ),
                              // Bounding boxes overlay for large image
                              if (imageModalShowBoundingBoxes &&
                                  currentImageData is Map<String, dynamic>)
                                ..._buildLargeBoundingBoxes(currentImageData),
                              // Left/right overlay tap zones
                              Positioned.fill(
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap:
                                            currentIndex > 0
                                                ? () {
                                                  print(
                                                    '[Carousel] left overlay tap',
                                                  );
                                                  setModalState(() {
                                                    goPrev();
                                                  });
                                                }
                                                : null,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Icon(
                                              Icons.chevron_left,
                                              size: 36,
                                              color:
                                                  currentIndex > 0
                                                      ? Colors.black54
                                                      : Colors.transparent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap:
                                            currentIndex < images.length - 1
                                                ? () {
                                                  print(
                                                    '[Carousel] right overlay tap',
                                                  );
                                                  setModalState(() {
                                                    goNext();
                                                  });
                                                }
                                                : null,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Icon(
                                              Icons.chevron_right,
                                              size: 36,
                                              color:
                                                  currentIndex <
                                                          images.length - 1
                                                      ? Colors.black54
                                                      : Colors.transparent,
                                            ),
                                          ),
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
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildLargeBoundingBoxes(Map<String, dynamic> imageData) {
    final results = imageData['results'] as List<dynamic>? ?? [];

    // Get actual image dimensions from the data
    final imageWidth =
        (imageData['imageWidth'] as double?) ??
        (imageData['imageWidth'] as int?)?.toDouble() ??
        4064.0;
    final imageHeight =
        (imageData['imageHeight'] as double?) ??
        (imageData['imageHeight'] as int?)?.toDouble() ??
        3048.0;

    return results.map<Widget>((result) {
      final boundingBox = result['boundingBox'] as Map<String, dynamic>?;
      if (boundingBox == null) {
        return const SizedBox.shrink();
      }

      // Get original coordinates
      final originalLeft =
          (boundingBox['left'] as double?) ??
          (boundingBox['left'] as int?)?.toDouble() ??
          0.0;
      final originalTop =
          (boundingBox['top'] as double?) ??
          (boundingBox['top'] as int?)?.toDouble() ??
          0.0;
      final originalRight =
          (boundingBox['right'] as double?) ??
          (boundingBox['right'] as int?)?.toDouble() ??
          0.0;
      final originalBottom =
          (boundingBox['bottom'] as double?) ??
          (boundingBox['bottom'] as int?)?.toDouble() ??
          0.0;

      final disease = _fixDiseaseName(
        result['disease'] as String? ?? 'Unknown',
      );
      final confidence = result['confidence'] as double? ?? 0.0;

      return LayoutBuilder(
        builder: (context, constraints) {
          // For BoxFit.cover, we need to calculate the actual displayed image size
          // and its position within the container
          final containerWidth = constraints.maxWidth;
          final containerHeight = constraints.maxHeight;

          // Calculate the scale to fit the image in the container while maintaining aspect ratio
          final scaleX = containerWidth / imageWidth;
          final scaleY = containerHeight / imageHeight;
          final scale =
              scaleX < scaleY
                  ? scaleX
                  : scaleY; // Use the smaller scale for contain

          // Calculate the actual displayed image dimensions
          final displayedWidth = imageWidth * scale;
          final displayedHeight = imageHeight * scale;

          // Calculate the offset to center the image
          final offsetX = (containerWidth - displayedWidth) / 2;
          final offsetY = (containerHeight - displayedHeight) / 2;

          // Scale coordinates and apply offset
          final left = (originalLeft * scale) + offsetX;
          final top = (originalTop * scale) + offsetY;
          final right = (originalRight * scale) + offsetX;
          final bottom = (originalBottom * scale) + offsetY;

          final width = right - left;
          final height = bottom - top;

          return Stack(
            children: [
              // Large bounding box
              Positioned(
                left: left,
                top: top,
                child: Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    border: Border.all(color: diseaseColor(disease), width: 4),
                    color: diseaseColor(disease).withOpacity(0.1),
                  ),
                ),
              ),
              // Large disease label
              Positioned(
                left: left - 10,
                top: top - 40,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: diseaseColor(disease).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    '${_fixDiseaseName(disease).substring(0, _fixDiseaseName(disease).length > 20 ? 20 : _fixDiseaseName(disease).length)}\n${(confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }).toList();
  }

  List<Widget> _buildBoundingBoxes(Map<String, dynamic> imageData) {
    final results = imageData['results'] as List<dynamic>? ?? [];

    // Get actual image dimensions from the data
    final imageWidth =
        (imageData['imageWidth'] as double?) ??
        (imageData['imageWidth'] as int?)?.toDouble() ??
        4064.0;
    final imageHeight =
        (imageData['imageHeight'] as double?) ??
        (imageData['imageHeight'] as int?)?.toDouble() ??
        3048.0;

    // Debug: Print image dimensions
    print('=== BOUNDING BOX DEBUG ===');
    print('Image data: $imageData');
    print('Image width: $imageWidth, height: $imageHeight');
    print('Results count: ${results.length}');

    // For BoxFit.contain, we need to calculate the actual displayed image size
    // and its position within the 200x200 container
    final containerWidth = 200.0;
    final containerHeight = 200.0;

    // Calculate the scale to fit the image in the container while maintaining aspect ratio
    final scaleX = containerWidth / imageWidth;
    final scaleY = containerHeight / imageHeight;
    final scale =
        scaleX < scaleY ? scaleX : scaleY; // Use the smaller scale for contain

    // Calculate the actual displayed image dimensions
    final displayedWidth = imageWidth * scale;
    final displayedHeight = imageHeight * scale;

    // Calculate the offset to center the image
    final offsetX = (containerWidth - displayedWidth) / 2;
    final offsetY = (containerHeight - displayedHeight) / 2;

    print('Scale factors: scaleX=$scaleX, scaleY=$scaleY, final scale=$scale');
    print('Displayed size: ${displayedWidth}x${displayedHeight}');
    print('Offset: $offsetX, $offsetY');

    return results.map<Widget>((result) {
      final boundingBox = result['boundingBox'] as Map<String, dynamic>?;
      if (boundingBox == null) {
        print('No bounding box found in result: $result');
        return const SizedBox.shrink();
      }

      // Get original coordinates
      final originalLeft =
          (boundingBox['left'] as double?) ??
          (boundingBox['left'] as int?)?.toDouble() ??
          0.0;
      final originalTop =
          (boundingBox['top'] as double?) ??
          (boundingBox['top'] as int?)?.toDouble() ??
          0.0;
      final originalRight =
          (boundingBox['right'] as double?) ??
          (boundingBox['right'] as int?)?.toDouble() ??
          0.0;
      final originalBottom =
          (boundingBox['bottom'] as double?) ??
          (boundingBox['bottom'] as int?)?.toDouble() ??
          0.0;

      // Scale coordinates and apply offset
      final left = (originalLeft * scale) + offsetX;
      final top = (originalTop * scale) + offsetY;
      final right = (originalRight * scale) + offsetX;
      final bottom = (originalBottom * scale) + offsetY;

      final width = right - left;
      final height = bottom - top;

      final disease = _fixDiseaseName(
        result['disease'] as String? ?? 'Unknown',
      );
      final confidence = result['confidence'] as double? ?? 0.0;

      print(
        'Original coords: left=$originalLeft, top=$originalTop, right=$originalRight, bottom=$originalBottom',
      );
      print(
        'Scaled coords: left=$left, top=$top, width=$width, height=$height',
      );
      print('Disease: $disease, Confidence: $confidence');
      print('========================');

      return Stack(
        children: [
          // Accurate bounding box (no labels inside)
          Positioned(
            left: left,
            top: top,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                border: Border.all(color: diseaseColor(disease), width: 3),
                color: diseaseColor(disease).withOpacity(0.1),
              ),
            ),
          ),
          // Single disease label outside the box (top-left)
          Positioned(
            left: left - 5,
            top: top - 25,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: diseaseColor(disease).withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                '${disease.substring(0, disease.length > 15 ? 15 : disease.length)}\n${(confidence * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }).toList();
  }
}

class _TotalUsersCardState extends State<TotalUsersCard> {
  final ValueNotifier<bool> _isHovered = ValueNotifier(false);

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isClickable = widget.onTap != null;
    final UsersSnapshot? usersProvider = Provider.of<UsersSnapshot?>(context);
    final QuerySnapshot? usersSnapshot = usersProvider?.snapshot;
    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      cursor: isClickable ? SystemMouseCursors.click : MouseCursor.defer,
      child: ValueListenableBuilder<bool>(
        valueListenable: _isHovered,
        builder: (context, isHovered, child) {
          return Card(
            elevation: isHovered && isClickable ? 8 : 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: child, // Use the child below
              ),
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header (no refresh button)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 24), // Spacer to center the content
                const Spacer(),
              ],
            ),
            // Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.people, size: 24, color: Colors.blue),
            ),
            const SizedBox(height: 16),
            // Number (real-time count)
            Builder(
              builder: (context) {
                if (usersSnapshot == null) {
                  return const CircularProgressIndicator();
                }
                final docs = usersSnapshot.docs;
                final totalUsers = docs.length;
                final pendingUsers =
                    docs.where((doc) => doc['status'] == 'pending').length;
                return Column(
                  children: [
                    Text(
                      '$totalUsers',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Total Users',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                          '${totalUsers - pendingUsers} Active',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
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
                          '$pendingUsers Pending',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
