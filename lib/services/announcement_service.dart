import 'package:cloud_firestore/cloud_firestore.dart';

class AnnouncementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _col = 'announcements';

  // --- 1. POST AN ANNOUNCEMENT (Teachers & Admins) ---
  Future<void> postAnnouncement({
    required String title,
    required String content,
    required String type, // 'class', 'exam', 'event'
    required String authorName,
    String? classId,
    String? teacherName,
  }) async {
    final data = {
      'title': title,
      'content': content,
      'type': type,
      'author': authorName,
      'teacherName': teacherName ?? authorName,
      'classId': classId,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'date': FieldValue.serverTimestamp(),
    };

    // Use a transaction to force server-side confirmation.
    // Without this, Firestore offline cache can silently accept writes
    // that the server later rejects due to security rules.
    await _db.runTransaction((transaction) async {
      final docRef = _db.collection(_col).doc();
      transaction.set(docRef, data);
    });
  }

  // --- 2. STREAM ALL ANNOUNCEMENTS (For List Page) ---
  Stream<QuerySnapshot> streamAnnouncements() {
    return _db
        .collection(_col)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // --- 3. GET RECENT SUMMARY (For Dashboard) ---
  // Fetches only the latest 3 for the dashboard widget
  Stream<QuerySnapshot> streamRecentAnnouncements() {
    return _db
        .collection(_col)
        .orderBy('timestamp', descending: true)
        .limit(3)
        .snapshots();
  }
}