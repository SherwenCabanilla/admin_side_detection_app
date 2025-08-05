import 'package:cloud_firestore/cloud_firestore.dart';

class UserStore {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Fetch all users from Firestore
  static Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      print('Fetching users from Firestore...');
      final QuerySnapshot snapshot = await _firestore.collection('users').get();
      print('Found ${snapshot.docs.length} users');

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'name': data['fullName'] ?? '',
          'email': data['email'] ?? '',
          'phone': data['phoneNumber'] ?? '',
          'address': data['address'] ?? '',
          'status': data['status'] ?? 'pending',
          'role': data['role'] ?? 'user',
          'registeredAt': _formatDate(data['createdAt']),
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
      await _firestore.collection('users').doc(userId).update({
        'status': status,
      });
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
      await _firestore.collection('users').doc(userId).update({
        'fullName': userData['name'],
        'email': userData['email'],
        'phoneNumber': userData['phone'],
        'address': userData['address'],
        'status': userData['status'],
        'role': userData['role'],
      });
      print('Successfully updated user');
      return true;
    } catch (e) {
      print('Error updating user: $e');
      return false;
    }
  }

  // Delete user
  static Future<bool> deleteUser(String userId) async {
    try {
      print('Deleting user $userId...');
      await _firestore.collection('users').doc(userId).delete();
      print('Successfully deleted user');
      return true;
    } catch (e) {
      print('Error deleting user: $e');
      return false;
    }
  }

  // Helper method to format date
  static String _formatDate(dynamic date) {
    if (date == null) return '';
    if (date is Timestamp) {
      return '${date.toDate().day}/${date.toDate().month}/${date.toDate().year}';
    }
    if (date is String) {
      // Handle string date format
      return date;
    }
    return '';
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
