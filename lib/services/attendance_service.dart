import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:fyp_tuition_eclassroom/models/attendance_models.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

class AttendanceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
    bucket: 'fyp-tuition-e-classroom.firebasestorage.app',
  );
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
    DateTime? allowedStartTime,
    DateTime? allowedEndTime,
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
      allowedStartTime: allowedStartTime,
      allowedEndTime: allowedEndTime,
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

  /// Get all students enrolled in a class
  Future<List<Map<String, dynamic>>> getClassStudents(String classId) async {
    final students = await _db
        .collection('users')
        .where('classIds', arrayContains: classId)
        .where('role', isEqualTo: 'student')
        .get();

    return students.docs.map((doc) {
      final data = doc.data();
      return {
        'uid': doc.id,
        'displayName': data['displayName'] ?? 'Student',
        'email': data['email'] ?? '',
      };
    }).toList();
  }

  /// Check if a class has scheduled sessions in the timetable for a date range
  /// Returns true if the class has classes scheduled on any day within the date range
  Future<bool> hasClassSessionsInDateRange(String classId, DateTime startDate, DateTime endDate) async {
    // Get the timetable for this class
    final timetableSnapshot = await _db
        .collection('timetables')
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: 'approved')
        .limit(1)
        .get();
    
    if (timetableSnapshot.docs.isEmpty) {
      return false; // No approved timetable for this class
    }
    
    final timetable = timetableSnapshot.docs.first.data();
    final baseSchedule = timetable['baseSchedule'] as Map<String, dynamic>?;
    final cancelledDates = timetable['cancelledDates'] as List<dynamic>? ?? [];
    final additionalSessions = timetable['additionalSessions'] as List<dynamic>? ?? [];
    
    // Get the day of week from baseSchedule (0=Sunday, 1=Monday, ..., 6=Saturday)
    final scheduleDayOfWeek = baseSchedule?['dayOfWeek'] as int?;
    
    if (scheduleDayOfWeek == null) {
      return false; // No schedule defined
    }
    
    // Check each date in the range
    DateTime currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
    
    while (currentDate.isBefore(endDateOnly) || currentDate.isAtSameMomentAs(endDateOnly)) {
      // Convert date to day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
      final dayOfWeek = currentDate.weekday == 7 ? 0 : currentDate.weekday;
      
      // Format date as string for checking cancelled dates
      final dateStr = DateFormat('yyyy-MM-dd').format(currentDate);
      
      // Check if this date matches the scheduled day of week
      if (dayOfWeek == scheduleDayOfWeek) {
        // Check if this date is cancelled
        final isCancelled = cancelledDates.any(
          (cancelled) => cancelled is Map && cancelled['date'] == dateStr,
        );
        
        if (!isCancelled) {
          return true; // Found a scheduled class day that's not cancelled
        }
      }
      
      // Also check additional sessions for this date
      final hasAdditionalSession = additionalSessions.any((session) {
        if (session is Map) {
          final sessionDate = session['date'] as String?;
          return sessionDate == dateStr;
        }
        return false;
      });
      
      if (hasAdditionalSession) {
        return true; // Found an additional session on this date
      }
      
      // Move to next day
      currentDate = currentDate.add(const Duration(days: 1));
    }
    
    return false; // No scheduled classes found in the date range
  }

  /// End an attendance session and mark absent students
  Future<void> endSession(String sessionId) async {
    // Get session details first
    final sessionDoc = await _db.collection(_sessionsCol).doc(sessionId).get();
    if (!sessionDoc.exists) {
      throw Exception('Session not found');
    }

    final sessionData = sessionDoc.data()!;
    final classId = sessionData['classId'] as String;
    final className = sessionData['className'] as String;
    final subject = sessionData['subject'] as String;

    // Get all students who checked in for this session
    final presentStudents = await _db
        .collection(_recordsCol)
        .where('sessionId', isEqualTo: sessionId)
        .get();

    final presentStudentIds = presentStudents.docs
        .map((doc) => doc.data()['studentId'] as String)
        .toSet();

    // Get all enrolled students in the class
    final allStudents = await getClassStudents(classId);

    // Get session object to access allowedEndTime
    final session = AttendanceSession.fromMap(sessionId, sessionData);
    final sessionEndTime = DateTime.now();
    
    // Use session's allowedEndTime if available, otherwise use current time
    final recordTimestamp = session.allowedEndTime ?? sessionEndTime;

    // Mark session as ended
    await _db.collection(_sessionsCol).doc(sessionId).update({
      'isActive': false,
      'endTime': Timestamp.fromDate(sessionEndTime),
    });

    // Create absent records for students who didn't check in
    final batch = _db.batch();
    int absentCount = 0;

    for (var student in allStudents) {
      if (!presentStudentIds.contains(student['uid'])) {
        // Student didn't check in - mark as absent
        final absentRecord = AttendanceRecord(
          id: '',
          studentId: student['uid'],
          studentName: student['displayName'],
          sessionId: sessionId,
          classId: classId,
          className: className,
          subject: subject,
          timestamp: recordTimestamp,
          status: 'absent',
        );

        final recordRef = _db.collection(_recordsCol).doc();
        batch.set(recordRef, absentRecord.toMap());
        absentCount++;
      }
    }

    if (absentCount > 0) {
      await batch.commit();
    }
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
        .snapshots()
        .map((snapshot) {
          final sessions = snapshot.docs
              .map((doc) => AttendanceSession.fromMap(doc.id, doc.data()))
              .toList();
          // Sort by startTime descending (most recent first)
          sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
          return sessions;
        });
  }

  /// Check and auto-close expired sessions (call this periodically or when needed)
  Future<void> checkAndCloseExpiredSessions() async {
    final now = TimezoneHelper.getMalaysiaTime();
    
    // Get all active sessions
    final activeSessions = await _db
        .collection(_sessionsCol)
        .where('isActive', isEqualTo: true)
        .get();

    for (var doc in activeSessions.docs) {
      final session = AttendanceSession.fromMap(doc.id, doc.data());
      
      // Check if time window has expired
      if (session.allowedEndTime != null) {
        final endTimeMalaysia = TimezoneHelper.toMalaysiaTime(session.allowedEndTime!);
        if (now.isAfter(endTimeMalaysia)) {
          // Time window expired - auto-close and mark absent students
          await endSession(session.id);
        }
      }
    }
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
    // Get the session to validate it's active and within time window
    final sessionDoc = await _db.collection(_sessionsCol).doc(sessionId).get();
    if (!sessionDoc.exists) {
      throw Exception('Session not found');
    }

    final session = AttendanceSession.fromMap(sessionId, sessionDoc.data()!);
    
    // Check if session is active
    if (!session.isActive) {
      throw Exception('Session is no longer active');
    }

    // Check if within time window (using Malaysia time)
    if (!session.isWithinTimeWindow()) {
      throw Exception('Attendance cannot be marked outside the allowed time window');
    }

    // Verify student is enrolled in the class
    final studentDoc = await _db.collection('users').doc(studentId).get();
    if (!studentDoc.exists) {
      throw Exception('Student not found');
    }
    final studentData = studentDoc.data()!;
    final classIds = (studentData['classIds'] as List<dynamic>?) ?? [];
    if (!classIds.contains(classId)) {
      throw Exception('You are not enrolled in this class');
    }

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
      takenBy: 'student',
      takenByUserId: studentId,
      takenByUserName: studentName,
    );

    final docRef = await _db.collection(_recordsCol).add(record.toMap());
    return AttendanceRecord.fromMap(docRef.id, record.toMap());
  }

  /// Mark attendance for a student by teacher (manual)
  Future<AttendanceRecord> markAttendanceByTeacher({
    required String sessionId,
    required String studentId,
    required String studentName,
    required String classId,
    required String className,
    required String subject,
    required String status, // 'present', 'absent', 'excused'
    required String teacherId,
    required String teacherName,
  }) async {
    // Check if already marked
    final existing = await _db
        .collection(_recordsCol)
        .where('sessionId', isEqualTo: sessionId)
        .where('studentId', isEqualTo: studentId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      // Update existing record
      final existingDoc = existing.docs.first;
      await _db.collection(_recordsCol).doc(existingDoc.id).update({
        'status': status,
        'takenBy': 'teacher',
        'takenByUserId': teacherId,
        'takenByUserName': teacherName,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      final updatedDoc = await _db.collection(_recordsCol).doc(existingDoc.id).get();
      return AttendanceRecord.fromMap(existingDoc.id, updatedDoc.data()!);
    }

    // Create new record
    final record = AttendanceRecord(
      id: '',
      studentId: studentId,
      studentName: studentName,
      sessionId: sessionId,
      classId: classId,
      className: className,
      subject: subject,
      timestamp: DateTime.now(),
      status: status,
      takenBy: 'teacher',
      takenByUserId: teacherId,
      takenByUserName: teacherName,
    );

    final docRef = await _db.collection(_recordsCol).add(record.toMap());
    return AttendanceRecord.fromMap(docRef.id, record.toMap());
  }

  /// Mark attendance for multiple students at once (teacher bulk action)
  Future<void> markBulkAttendanceByTeacher({
    required String sessionId,
    required String classId,
    required String className,
    required String subject,
    required Map<String, String> studentStatuses, // studentId -> status
    required String teacherId,
    required String teacherName,
    Map<String, String>? studentNames, // studentId -> name (avoid users get)
  }) async {
    final batch = _db.batch();
    
    for (var entry in studentStatuses.entries) {
      final studentId = entry.key;
      final status = entry.value;
      final studentName = studentNames?[studentId] ?? 'Unknown';
      
      // Check if record exists
      final existing = await _db
          .collection(_recordsCol)
          .where('sessionId', isEqualTo: sessionId)
          .where('studentId', isEqualTo: studentId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        // Update existing
        batch.update(_db.collection(_recordsCol).doc(existing.docs.first.id), {
          'status': status,
          'takenBy': 'teacher',
          'takenByUserId': teacherId,
          'takenByUserName': teacherName,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new
        final record = AttendanceRecord(
          id: '',
          studentId: studentId,
          studentName: studentName,
          sessionId: sessionId,
          classId: classId,
          className: className,
          subject: subject,
          timestamp: DateTime.now(),
          status: status,
          takenBy: 'teacher',
          takenByUserId: teacherId,
          takenByUserName: teacherName,
        );
        batch.set(_db.collection(_recordsCol).doc(), record.toMap());
      }
    }
    
    await batch.commit();
  }

  /// Get attendance records for a student
  Stream<List<AttendanceRecord>> streamStudentRecords(String studentId) {
    return _db
        .collection(_recordsCol)
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
          final records = snapshot.docs
              .map((doc) => AttendanceRecord.fromMap(doc.id, doc.data()))
              .toList();
          // Sort by timestamp descending (most recent first) in memory
          records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return records;
        });
  }

  /// Get attendance records for a session
  Stream<List<AttendanceRecord>> streamSessionRecords(String sessionId) {
    return _db
        .collection(_recordsCol)
        .where('sessionId', isEqualTo: sessionId)
        .snapshots()
        .map((snapshot) {
          final records = snapshot.docs
              .map((doc) => AttendanceRecord.fromMap(doc.id, doc.data()))
              .toList();
          // Sort by timestamp ascending (oldest first) in memory
          records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          return records;
        });
  }

  /// Get absence document by ID
  Future<AbsenceDocument?> getAbsenceDocument(String documentId) async {
    try {
      final doc = await _db.collection(_documentsCol).doc(documentId).get();
      if (doc.exists) {
        return AbsenceDocument.fromMap(doc.id, doc.data()!);
      }
      return null;
    } catch (e) {
      print('Error fetching absence document: $e');
      return null;
    }
  }

  /// Get attendance statistics for a student
  Future<Map<String, dynamic>> getStudentStats(String studentId, String classId) async {
    // First, check for any expired sessions that need to be closed
    await checkAndCloseExpiredSessions();

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
    // Attendance rate: (present + excused) / total * 100
    // Excused absences count as present for attendance percentage
    final rate = total > 0 ? (((present + excused) / total) * 100).round() : 0;

    return {
      'present': present,
      'absent': absent,
      'excused': excused,
      'total': total,
      'rate': rate,
    };
  }

  // --- ABSENCE DOCUMENTS ---

  /// Store file in Firestore as base64 (instead of Firebase Storage)
  /// Note: Firestore has 1MB limit per document, so this works for smaller files
  Future<String> uploadAbsenceDocumentFile(File file, String studentId) async {
    try {
      // Check if file exists
      if (!await file.exists()) {
        throw Exception('File does not exist at path: ${file.path}');
      }

      // Check file size (Firestore limit is 1MB per document)
      final fileSize = await file.length();
      const maxSize = 1024 * 1024; // 1MB
      if (fileSize > maxSize) {
        throw Exception('File is too large (${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB). Maximum size is 1MB. Please compress or resize the file.');
      }

      // Read file as bytes and convert to base64
      final fileBytes = await file.readAsBytes();
      final base64String = base64Encode(fileBytes);
      
      // Get file name - handle both Windows and Unix paths
      final pathParts = file.path.split(Platform.pathSeparator);
      final originalFileName = pathParts.last;
      
      // Create unique file name
      final sanitizedFileName = originalFileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final fileName = '${studentId}_${DateTime.now().millisecondsSinceEpoch}_$sanitizedFileName';
      
      // Store in Firestore under absence_document_files collection
      final docRef = await _db.collection('absence_document_files').add({
        'fileName': fileName,
        'originalFileName': originalFileName,
        'fileData': base64String,
        'fileSize': fileSize,
        'studentId': studentId,
        'uploadedAt': FieldValue.serverTimestamp(),
      });
      
      // Return a reference ID that we can use to retrieve the file later
      // Format: "firestore:docId" to distinguish from Storage URLs
      return 'firestore:${docRef.id}';
    } catch (e) {
      throw Exception('Error processing file: $e');
    }
  }
  
  /// Get file data from Firestore by reference ID
  Future<Map<String, dynamic>> getFileFromFirestore(String fileRef) async {
    if (!fileRef.startsWith('firestore:')) {
      throw Exception('Invalid file reference format');
    }
    
    final docId = fileRef.replaceFirst('firestore:', '');
    final doc = await _db.collection('absence_document_files').doc(docId).get();
    
    if (!doc.exists) {
      throw Exception('File not found in Firestore');
    }
    
    final data = doc.data()!;
    return {
      'fileName': data['fileName'] ?? '',
      'originalFileName': data['originalFileName'] ?? '',
      'fileData': data['fileData'] ?? '',
      'fileSize': data['fileSize'] ?? 0,
    };
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

  /// Get all pending absence documents (for admin)
  Stream<List<AbsenceDocument>> streamPendingDocuments() {
    return _db
        .collection(_documentsCol)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final documents = snapshot.docs
              .map((doc) => AbsenceDocument.fromMap(doc.id, doc.data()))
              .toList();
          // Sort by submittedAt descending (most recent first) in memory
          documents.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
          return documents;
        });
  }

  /// Get all absence documents (for admin - all statuses)
  Stream<List<AbsenceDocument>> streamAllDocuments() {
    return _db
        .collection(_documentsCol)
        .snapshots()
        .map((snapshot) {
          final documents = snapshot.docs
              .map((doc) => AbsenceDocument.fromMap(doc.id, doc.data()))
              .toList();
          // Sort by submittedAt descending (most recent first) in memory
          documents.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
          return documents;
        });
  }

  /// Update absence document status (admin only)
  Future<void> updateDocumentStatus({
    required String documentId,
    required String status, // 'approved' or 'rejected'
    required String reviewedBy,
    String? reviewNotes,
  }) async {
    await _db.collection(_documentsCol).doc(documentId).update({
      'status': status,
      'reviewedBy': reviewedBy,
      'reviewedAt': FieldValue.serverTimestamp(),
      if (reviewNotes != null) 'reviewNotes': reviewNotes,
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

        // Normalize dates to compare only the date part (ignore time)
        final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
        final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
        
        // Find all absent attendance records for this student and class
        final records = await _db
            .collection(_recordsCol)
            .where('studentId', isEqualTo: studentId)
            .where('classId', isEqualTo: classId)
            .where('status', isEqualTo: 'absent')
            .get();

        final batch = _db.batch();
        int updatedCount = 0;
        
        for (var recordDoc in records.docs) {
          final recordData = recordDoc.data();
          final recordTime = (recordData['timestamp'] as Timestamp).toDate();
          
          // Compare only the date part (ignore time)
          final recordDateOnly = DateTime(recordTime.year, recordTime.month, recordTime.day);
          
          // Check if record date falls within the absence document date range (inclusive)
          // Convert to comparable format for easier comparison
          final recordDateInt = recordDateOnly.year * 10000 + recordDateOnly.month * 100 + recordDateOnly.day;
          final startDateInt = startDateOnly.year * 10000 + startDateOnly.month * 100 + startDateOnly.day;
          final endDateInt = endDateOnly.year * 10000 + endDateOnly.month * 100 + endDateOnly.day;
          
          if (recordDateInt >= startDateInt && recordDateInt <= endDateInt) {
            // Update the record to excused
            batch.update(recordDoc.reference, {
              'status': 'excused',
              'absenceDocumentId': documentId,
            });
            updatedCount++;
          }
        }
        
        if (updatedCount > 0) {
          await batch.commit();
        }
      }
    }
  }

  // Helper method
  String _generateRandomCode() {
    final rng = Random();
    return (rng.nextInt(900000) + 100000).toString(); // 6 digits
  }
}
