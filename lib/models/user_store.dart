import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class UserStore {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  // Fetch all users from Firestore
  static Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      print('Fetching users from Firestore...');
      final QuerySnapshot snapshot = await _firestore.collection('users').get();
      print('Found ${snapshot.docs.length} users');

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final String status = (data['status'] ?? 'pending').toString();
        final String registered = _formatDate(data['createdAt']);
        // Accepted display logic:
        // - pending -> dash
        // - active with acceptedAt -> formatted acceptedAt
        // - active with no acceptedAt (legacy) -> show registered
        String acceptedDisplay = '—';
        if (status.toLowerCase() == 'active') {
          if (data['acceptedAt'] != null) {
            acceptedDisplay = _formatDate(data['acceptedAt']);
          } else {
            acceptedDisplay = registered;
          }
        }

        return {
          'id': doc.id,
          'name': _titleCase(data['fullName'] ?? ''),
          'email': data['email'] ?? '',
          'phone': data['phoneNumber'] ?? '',
          'address': data['address'] ?? '',
          'status': status,
          'role': data['role'] ?? 'user',
          'registeredAt': registered,
          'acceptedAt': acceptedDisplay,
          'profileImage': data['imageProfile'] ?? '',
        };
      }).toList();
    } catch (e) {
      print('Error fetching users: $e');
      return [];
    }
  }

  // Update user status
  static Future<bool> updateUserStatus(String userId, String status) async {
    try {
      print('Updating user $userId status to $status...');
      final docRef = _firestore.collection('users').doc(userId);
      final snap = await docRef.get();
      final data = snap.data() as Map<String, dynamic>?;
      final bool hasAccepted = (data?['acceptedAt']) != null;
      final Map<String, dynamic> payload = {'status': status};
      if (status.toLowerCase() == 'active' && !hasAccepted) {
        payload['acceptedAt'] = FieldValue.serverTimestamp();
      }
      await docRef.update(payload);
      print('Successfully updated user status');
      return true;
    } catch (e) {
      print('Error updating user status: $e');
      return false;
    }
  }

  // Update user data
  static Future<bool> updateUser(
    String userId,
    Map<String, dynamic> userData,
  ) async {
    try {
      print('Updating user $userId...');
      final Map<String, dynamic> payload = {
        'fullName': userData['name'],
        'email': userData['email'],
        'phoneNumber': userData['phone'],
        'address': userData['address'],
        'status': userData['status'],
        'role': userData['role'],
      };
      if (userData.containsKey('imageProfile')) {
        payload['imageProfile'] = userData['imageProfile'];
      }
      // acceptedAt guard: set when new status is active and field is missing
      try {
        final docRef = _firestore.collection('users').doc(userId);
        final current = await docRef.get();
        final currentData = current.data() as Map<String, dynamic>?;
        final bool hasAccepted = (currentData?['acceptedAt']) != null;
        final String newStatus = (userData['status'] ?? '').toString();
        if (!hasAccepted && newStatus.toLowerCase() == 'active') {
          payload['acceptedAt'] = FieldValue.serverTimestamp();
        }
      } catch (e) {
        // Skip setting acceptedAt if we can't read current; proceed with update
        print('acceptedAt guard read skipped: $e');
      }

      await _firestore.collection('users').doc(userId).update(payload);
      print('Successfully updated user');
      return true;
    } catch (e) {
      print('Error updating user: $e');
      return false;
    }
  }

  // Delete user (calls Cloud Function to delete both Auth and Firestore)
  static Future<bool> deleteUser(String userId) async {
    try {
      print('Deleting user $userId (Auth + Firestore)...');

      // Call the Cloud Function to delete user from both Auth and Firestore
      final callable = _functions.httpsCallable('deleteUserAccount');
      final result = await callable.call({'userId': userId});

      final data = result.data as Map<String, dynamic>;
      print('Successfully deleted user: ${data['message']}');
      print(
        'Deleted ${data['deletedPendingScanRequests']} pending scan requests',
      );
      print(
        'Note: Completed/reviewed scans are preserved for historical records',
      );

      return data['success'] == true;
    } catch (e) {
      print('Error deleting user: $e');

      // Fallback: if Cloud Function fails, try direct Firestore delete
      // (This won't delete Auth account but at least removes from Firestore)
      try {
        print('Attempting fallback Firestore-only deletion...');
        await _firestore.collection('users').doc(userId).delete();
        print('Fallback: Successfully deleted user from Firestore only');
        print('WARNING: Firebase Auth account may still exist');
        return true;
      } catch (fallbackError) {
        print('Fallback deletion also failed: $fallbackError');
        return false;
      }
    }
  }

  // Helper method to format date
  static String _formatDate(dynamic date) {
    if (date == null) return '';
    if (date is Timestamp) {
      final dt = date.toDate();
      return _formatMonDyyyy(dt);
    }
    if (date is String) {
      // Normalize any ISO-like string to dd/mm/yyyy
      final parsed = DateTime.tryParse(date);
      if (parsed != null) {
        return _formatMonDyyyy(parsed);
      }
      // Unknown string format; return as-is
      return date;
    }
    return '';
  }

  static const List<String> _monthShort = [
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

  static String _formatMonDyyyy(DateTime dt) {
    final month = _monthShort[dt.month - 1];
    final day = dt.day.toString();
    final year = dt.year.toString();
    return '$month $day $year';
  }

  static String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return word;
          final lower = word.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
  }

  // Get pending users count
  static Future<int> getPendingUsersCount() async {
    try {
      final QuerySnapshot snapshot =
          await _firestore
              .collection('users')
              .where('status', isEqualTo: 'pending')
              .get();
      return snapshot.docs.length;
    } catch (e) {
      print('Error getting pending users count: $e');
      return 0;
    }
  }

  // Get total users count
  static Future<int> getTotalUsersCount() async {
    try {
      final QuerySnapshot snapshot = await _firestore.collection('users').get();
      return snapshot.docs.length;
    } catch (e) {
      print('Error getting total users count: $e');
      return 0;
    }
  }
}
