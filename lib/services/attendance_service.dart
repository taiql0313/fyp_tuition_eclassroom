import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fyp_tuition_eclassroom/models/attendance_models.dart';

class AttendanceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collections
  final String _sessionsCol = 'attendance_sessions';
  final String _recordsCol = 'attendance_records';
  final String _documentsCol = 'absence_documents';

  // --- ATTENDANCE SESSIONS (Teacher creates) ---

  /// Create a new attendance session with a 6-digit code
  Future<AttendanceSession> createSession({
    required String classId,
    required String className,
    required String subject,
    String? sessionTime,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // Generate unique 6-digit code
    String code;
    bool codeExists;
    do {
      code = _generateRandomCode();
      final existing = await _db
          .collection(_sessionsCol)
          .where('code', isEqualTo: code)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      codeExists = existing.docs.isNotEmpty;
    } while (codeExists);

    final session = AttendanceSession(
      id: '', // Will be set after creation
      classId: classId,
      className: className,
      subject: subject,
      code: code,
      teacherId: user.uid,
      teacherName: user.displayName ?? 'Teacher',
      startTime: DateTime.now(),
      isActive: true,
      sessionTime: sessionTime,
    );

    final docRef = await _db.collection(_sessionsCol).add(session.toMap());
    return AttendanceSession.fromMap(docRef.id, session.toMap());
  }

  /// Get active session by code
  Future<AttendanceSession?> getSessionByCode(String code) async {
    final snapshot = await _db
        .collection(_sessionsCol)
        .where('code', isEqualTo: code)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return AttendanceSession.fromMap(doc.id, doc.data());
  }

  /// End an attendance session
  Future<void> endSession(String sessionId) async {
    await _db.collection(_sessionsCol).doc(sessionId).update({
      'isActive': false,
      'endTime': FieldValue.serverTimestamp(),
    });
  }

  /// Get active sessions for a teacher
  Stream<List<AttendanceSession>> streamTeacherSessions(String teacherId) {
    return _db
        .collection(_sessionsCol)
        .where('teacherId', isEqualTo: teacherId)
        .where('isActive', isEqualTo: true)
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AttendanceSession.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Get active sessions for a class
  Stream<List<AttendanceSession>> streamClassSessions(String classId) {
    return _db
        .collection(_sessionsCol)
        .where('classId', isEqualTo: classId)
        .where('isActive', isEqualTo: true)
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AttendanceSession.fromMap(doc.id, doc.data()))
            .toList());
  }

  // --- ATTENDANCE RECORDS (Student checks in) ---

  /// Mark attendance for a student
  Future<AttendanceRecord> markAttendance({
    required String sessionId,
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String subject,
  }) async {
    // Check if already marked
    final existing = await _db
        .collection(_recordsCol)
        .where('sessionId', isEqualTo: sessionId)
        .where('studentId', isEqualTo: studentId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('Attendance already marked for this session');
    }

    final record = AttendanceRecord(
      id: '',
      studentId: studentId,
      studentName: studentName,
      sessionId: sessionId,
      classId: classId,
      className: className,
      subject: subject,
      timestamp: DateTime.now(),
      status: 'present',
    );

    final docRef = await _db.collection(_recordsCol).add(record.toMap());
    return AttendanceRecord.fromMap(docRef.id, record.toMap());
  }

  /// Get attendance records for a student
  Stream<List<AttendanceRecord>> streamStudentRecords(String studentId) {
    return _db
        .collection(_recordsCol)
        .where('studentId', isEqualTo: studentId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AttendanceRecord.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Get attendance records for a session
  Stream<List<AttendanceRecord>> streamSessionRecords(String sessionId) {
    return _db
        .collection(_recordsCol)
        .where('sessionId', isEqualTo: sessionId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AttendanceRecord.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Get attendance statistics for a student
  Future<Map<String, dynamic>> getStudentStats(String studentId, String classId) async {
    final records = await _db
        .collection(_recordsCol)
        .where('studentId', isEqualTo: studentId)
        .where('classId', isEqualTo: classId)
        .get();

    int present = 0;
    int absent = 0;
    int excused = 0;

    for (var doc in records.docs) {
      final data = doc.data();
      final status = data['status'] ?? 'absent';
      if (status == 'present') {
        present++;
      } else if (status == 'excused') {
        excused++;
      } else {
        absent++;
      }
    }

    final total = present + absent + excused;
    final rate = total > 0 ? ((present + excused) / total * 100).round() : 0;

    return {
      'present': present,
      'absent': absent,
      'excused': excused,
      'total': total,
      'rate': rate,
    };
  }

  // --- ABSENCE DOCUMENTS ---

  /// Upload file to Firebase Storage and return the download URL
  Future<String> uploadAbsenceDocumentFile(File file, String studentId) async {
    final fileName = '${studentId}_${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final fileRef = _storage.ref().child('absence_documents').child(fileName);
    
    final uploadTask = fileRef.putFile(file);
    final snapshot = await uploadTask.whenComplete(() => null);
    return await snapshot.ref.getDownloadURL();
  }

  /// Submit absence document with file URL (after upload)
  Future<AbsenceDocument> submitAbsenceDocumentWithUrl({
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String subject,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    required String fileUrl,
    required String fileName,
  }) async {
    final document = AbsenceDocument(
      id: '',
      studentId: studentId,
      studentName: studentName,
      classId: classId,
      className: className,
      subject: subject,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      fileUrl: fileUrl,
      fileName: fileName,
      submittedAt: DateTime.now(),
      status: 'pending',
    );

    final docRef = await _db.collection(_documentsCol).add(document.toMap());
    return AbsenceDocument.fromMap(docRef.id, document.toMap());
  }

  /// Get absence documents for a student
  Stream<List<AbsenceDocument>> streamStudentDocuments(String studentId) {
    return _db
        .collection(_documentsCol)
        .where('studentId', isEqualTo: studentId)
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AbsenceDocument.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Update absence document status (teacher/admin)
  Future<void> updateDocumentStatus({
    required String documentId,
    required String status, // 'approved' or 'rejected'
    required String reviewedBy,
  }) async {
    await _db.collection(_documentsCol).doc(documentId).update({
      'status': status,
      'reviewedBy': reviewedBy,
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    // If approved, update related attendance records to 'excused'
    if (status == 'approved') {
      final doc = await _db.collection(_documentsCol).doc(documentId).get();
      if (doc.exists) {
        final data = doc.data()!;
        final classId = data['classId'] as String;
        final studentId = data['studentId'] as String;
        final startDate = (data['startDate'] as Timestamp).toDate();
        final endDate = (data['endDate'] as Timestamp).toDate();

        // Find attendance records in the date range and update them
        final records = await _db
            .collection(_recordsCol)
            .where('studentId', isEqualTo: studentId)
            .where('classId', isEqualTo: classId)
            .get();

        final batch = _db.batch();
        for (var recordDoc in records.docs) {
          final recordData = recordDoc.data();
          final recordTime = (recordData['timestamp'] as Timestamp).toDate();
          if (recordTime.isAfter(startDate.subtract(const Duration(days: 1))) &&
              recordTime.isBefore(endDate.add(const Duration(days: 1)))) {
            if (recordData['status'] == 'absent') {
              batch.update(recordDoc.reference, {
                'status': 'excused',
                'absenceDocumentId': documentId,
              });
            }
          }
        }
        await batch.commit();
      }
    }
  }

  // Helper method
  String _generateRandomCode() {
    final rng = Random();
    return (rng.nextInt(900000) + 100000).toString(); // 6 digits
  }
}
