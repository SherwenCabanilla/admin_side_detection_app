import 'package:flutter/material.dart';
import 'report_detail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/scan_requests_service.dart';

class ReportsListScreen extends StatelessWidget {
  ReportsListScreen({Key? key}) : super(key: key);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Reports'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: ScanRequestsService.getScanRequests(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return SizedBox(
                  height: 240,
                  child: Center(
                    child: Text('Failed to load reports: ${snapshot.error}'),
                  ),
                );
              }
              final reports = snapshot.data ?? [];

              return SingleChildScrollView(
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
                      reports.map((report) {
                        // Extract a display disease name from possible structures
                        String disease = '';
                        final ds = report['diseaseSummary'];
                        if (ds is List && ds.isNotEmpty) {
                          final first = ds.first;
                          if (first is Map<String, dynamic>) {
                            disease =
                                (first['name'] ??
                                        first['label'] ??
                                        first['disease'] ??
                                        '')
                                    .toString();
                          } else {
                            disease = first.toString();
                          }
                        }

                        return DataRow(
                          cells: [
                            DataCell(Text(report['id'].toString())),
                            DataCell(
                              Text(
                                (report['userName'] ?? report['userId'] ?? '')
                                    .toString(),
                              ),
                            ),
                            DataCell(Text(_formatDate(report['createdAt']))),
                            DataCell(Text(disease.isEmpty ? '-' : disease)),
                            DataCell(Text((report['status'] ?? '').toString())),
                            DataCell(
                              ElevatedButton(
                                child: const Text('View'),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => ReportDetailScreen(
                                            report: report,
                                          ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
