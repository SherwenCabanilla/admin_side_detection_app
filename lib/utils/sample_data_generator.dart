import 'package:cloud_firestore/cloud_firestore.dart';

class SampleDataGenerator {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> generateSampleScanRequests() async {
    try {
      print('Generating sample scan requests...');

      final List<Map<String, dynamic>> sampleRequests = [
        {
          'userId': 'USER_001',
          'userName': 'Maria Santos',
          'status': 'completed',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 2)),
          ),
          'reviewedAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 1)),
          ),
          'diseaseSummary': [
            {'name': 'Anthracnose', 'count': 2},
            {'name': 'Healthy', 'count': 1},
          ],
        },
        {
          'userId': 'USER_002',
          'userName': 'Juan Dela Cruz',
          'status': 'completed',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 3)),
          ),
          'reviewedAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 2)),
          ),
          'diseaseSummary': [
            {'name': 'Powdery Mildew', 'count': 1},
            {'name': 'Bacterial Blackspot', 'count': 1},
          ],
        },
        {
          'userId': 'USER_003',
          'userName': 'Ana Garcia',
          'status': 'completed',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 5)),
          ),
          'reviewedAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 4)),
          ),
          'diseaseSummary': [
            {'name': 'Anthracnose', 'count': 1},
            {'name': 'Dieback', 'count': 1},
            {'name': 'Healthy', 'count': 2},
          ],
        },
        {
          'userId': 'USER_004',
          'userName': 'Pedro Martinez',
          'status': 'pending',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(hours: 6)),
          ),
          'diseaseSummary': [
            {'name': 'Powdery Mildew', 'count': 2},
          ],
        },
        {
          'userId': 'USER_005',
          'userName': 'Carmen Lopez',
          'status': 'completed',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 1)),
          ),
          'reviewedAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(hours: 12)),
          ),
          'diseaseSummary': [
            {'name': 'Healthy', 'count': 3},
          ],
        },
        {
          'userId': 'USER_006',
          'userName': 'Roberto Silva',
          'status': 'completed',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 10)),
          ),
          'reviewedAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 9)),
          ),
          'diseaseSummary': [
            {'name': 'Anthracnose', 'count': 1},
            {'name': 'Bacterial Blackspot', 'count': 2},
            {'name': 'Healthy', 'count': 1},
          ],
        },
        {
          'userId': 'USER_007',
          'userName': 'Isabella Torres',
          'status': 'completed',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 15)),
          ),
          'reviewedAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 14)),
          ),
          'diseaseSummary': [
            {'name': 'Powdery Mildew', 'count': 1},
            {'name': 'Dieback', 'count': 1},
          ],
        },
        {
          'userId': 'USER_008',
          'userName': 'Miguel Rodriguez',
          'status': 'pending',
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(hours: 2)),
          ),
          'diseaseSummary': [
            {'name': 'Anthracnose', 'count': 1},
            {'name': 'Healthy', 'count': 1},
          ],
        },
      ];

      // Add sample data to Firestore
      for (int i = 0; i < sampleRequests.length; i++) {
        final request = sampleRequests[i];
        await _firestore.collection('scan_requests').add(request);
        print('Added sample request ${i + 1}');
      }

      print(
        'Successfully generated ${sampleRequests.length} sample scan requests',
      );
    } catch (e) {
      print('Error generating sample data: $e');
    }
  }

  static Future<void> clearSampleData() async {
    try {
      print('Clearing sample scan requests...');
      final QuerySnapshot snapshot =
          await _firestore.collection('scan_requests').get();

      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }

      print('Successfully cleared ${snapshot.docs.length} scan requests');
    } catch (e) {
      print('Error clearing sample data: $e');
    }
  }
}
