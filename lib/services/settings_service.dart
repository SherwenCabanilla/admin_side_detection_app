import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'app_settings';
  static const String _docId = 'pdf';

  static Future<String> getUtilityName() async {
    try {
      final doc = await _db.collection(_collection).doc(_docId).get();
      if (!doc.exists) {
        return 'Utility';
      }
      final data = doc.data();
      if (data == null) return 'Utility';
      final dynamic value = data['utilityName'];
      if (value == null) return 'Utility';
      final String name = value.toString().trim();
      return name.isEmpty ? 'Utility' : name;
    } catch (_) {
      return 'Utility';
    }
  }

  static Stream<String> utilityNameStream() {
    return _db.collection(_collection).doc(_docId).snapshots().map((snap) {
      final data = snap.data();
      final dynamic value = data == null ? null : data['utilityName'];
      final String name = (value == null ? 'Utility' : value.toString()).trim();
      return name.isEmpty ? 'Utility' : name;
    });
  }

  static Future<void> setUtilityName(String name) async {
    final normalized = name.trim();
    await _db.collection(_collection).doc(_docId).set({
      'utilityName': normalized.isEmpty ? 'Utility' : normalized,
    }, SetOptions(merge: true));
  }
}
