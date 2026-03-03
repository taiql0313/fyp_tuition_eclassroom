import 'package:cloud_firestore/cloud_firestore.dart';

/// Creates in-app notifications for students (payment, announcements, new quiz, etc.)
class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Create a single notification for one user
  Future<void> createForUser({
    required String userId,
    required String type,
    required String title,
    required String message,
  }) async {
    print('NotificationService: Creating notification for userId=$userId, type=$type, title=$title');
    try {
      final docRef = await _db.collection('notifications').add({
        'userId': userId,
        'type': type,
        'title': title,
        'message': message,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      print('NotificationService: Notification created with id=${docRef.id}');
    } catch (e) {
      print('NotificationService: Error creating notification: $e');
    }
  }

  /// Get student IDs enrolled in a class
  Future<List<String>> _getStudentIdsInClass(String classId) async {
    final snapshot = await _db
        .collection('users')
        .where('classIds', arrayContains: classId)
        .where('role', isEqualTo: 'student')
        .get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  /// Get all student IDs (for announcements to everyone)
  Future<List<String>> _getAllStudentIds() async {
    final snapshot = await _db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  /// Create notifications for all students in a class
  Future<void> createForStudentsInClass({
    required String classId,
    required String type,
    required String title,
    required String message,
  }) async {
    try {
      final studentIds = await _getStudentIdsInClass(classId);
      for (final userId in studentIds) {
        await createForUser(userId: userId, type: type, title: title, message: message);
      }
    } catch (e) {
      print('NotificationService: Error creating class notifications: $e');
    }
  }

  /// Create notifications for all students (e.g. general announcements)
  Future<void> createForAllStudents({
    required String type,
    required String title,
    required String message,
  }) async {
    try {
      final studentIds = await _getAllStudentIds();
      for (final userId in studentIds) {
        await createForUser(userId: userId, type: type, title: title, message: message);
      }
    } catch (e) {
      print('NotificationService: Error creating notifications for all students: $e');
    }
  }
}
