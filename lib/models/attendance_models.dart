import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

/// Represents an active attendance session created by a teacher
class AttendanceSession {
  final String id;
  final String classId;
  final String className;
  final String subject;
  final String code; // 6-digit code
  final String teacherId;
  final String teacherName;
  final DateTime startTime; // When session was created
  final DateTime? endTime; // When session was ended
  final bool isActive;
  final String? sessionTime; // Display string e.g., "10:00 AM - 12:00 PM"
  final DateTime? allowedStartTime; // When students can start checking in
  final DateTime? allowedEndTime; // When students can no longer check in

  AttendanceSession({
    required this.id,
    required this.classId,
    required this.className,
    required this.subject,
    required this.code,
    required this.teacherId,
    required this.teacherName,
    required this.startTime,
    this.endTime,
    required this.isActive,
    this.sessionTime,
    this.allowedStartTime,
    this.allowedEndTime,
  });

  factory AttendanceSession.fromMap(String id, Map<String, dynamic> map) {
    return AttendanceSession(
      id: id,
      classId: map['classId'] ?? '',
      className: map['className'] ?? '',
      subject: map['subject'] ?? '',
      code: map['code'] ?? '',
      teacherId: map['teacherId'] ?? '',
      teacherName: map['teacherName'] ?? '',
      startTime: (map['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (map['endTime'] as Timestamp?)?.toDate(),
      isActive: map['isActive'] ?? false,
      sessionTime: map['sessionTime'],
      allowedStartTime: (map['allowedStartTime'] as Timestamp?)?.toDate(),
      allowedEndTime: (map['allowedEndTime'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'classId': classId,
      'className': className,
      'subject': subject,
      'code': code,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'isActive': isActive,
      'sessionTime': sessionTime,
      'allowedStartTime': allowedStartTime != null ? Timestamp.fromDate(allowedStartTime!) : null,
      'allowedEndTime': allowedEndTime != null ? Timestamp.fromDate(allowedEndTime!) : null,
    };
  }

  /// Check if current time is within the allowed attendance window (using Malaysia time)
  bool isWithinTimeWindow() {
    final now = TimezoneHelper.getMalaysiaTime();
    
    if (allowedStartTime != null && allowedEndTime != null) {
      // Both times are stored as UTC, convert to Malaysia time for comparison
      final startTimeMalaysia = TimezoneHelper.toMalaysiaTime(allowedStartTime!);
      final endTimeMalaysia = TimezoneHelper.toMalaysiaTime(allowedEndTime!);
      
      // Compare Malaysia time with Malaysia time
      if (now.isBefore(startTimeMalaysia)) {
        return false; // Too early
      }
      if (now.isAfter(endTimeMalaysia)) {
        return false; // Too late
      }
      return true; // Within window
    }
    
    return true; // No time restrictions
  }
}

/// Represents a student's attendance record for a session
class AttendanceRecord {
  final String id;
  final String studentId;
  final String studentName;
  final String sessionId;
  final String classId;
  final String className;
  final String subject;
  final DateTime timestamp;
  final String status; // 'present', 'absent', 'excused'
  final String? absenceDocumentId; // Link to absence document if excused
  final String takenBy; // 'student' or 'teacher' - who marked this attendance
  final String? takenByUserId; // ID of the user who marked attendance
  final String? takenByUserName; // Name of the user who marked attendance

  AttendanceRecord({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.sessionId,
    required this.classId,
    required this.className,
    required this.subject,
    required this.timestamp,
    required this.status,
    this.absenceDocumentId,
    this.takenBy = 'student',
    this.takenByUserId,
    this.takenByUserName,
  });

  factory AttendanceRecord.fromMap(String id, Map<String, dynamic> map) {
    return AttendanceRecord(
      id: id,
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      sessionId: map['sessionId'] ?? '',
      classId: map['classId'] ?? '',
      className: map['className'] ?? '',
      subject: map['subject'] ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: map['status'] ?? 'absent',
      absenceDocumentId: map['absenceDocumentId'],
      takenBy: map['takenBy'] ?? 'student',
      takenByUserId: map['takenByUserId'],
      takenByUserName: map['takenByUserName'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'studentName': studentName,
      'sessionId': sessionId,
      'classId': classId,
      'className': className,
      'subject': subject,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
      'absenceDocumentId': absenceDocumentId,
      'takenBy': takenBy,
      'takenByUserId': takenByUserId,
      'takenByUserName': takenByUserName,
    };
  }
}

/// Represents an absence document (MC, excuse letter, etc.)
class AbsenceDocument {
  final String id;
  final String studentId;
  final String studentName;
  final String classId;
  final String className;
  final String subject;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String fileUrl; // Firebase Storage URL
  final String fileName;
  final DateTime submittedAt;
  final String status; // 'pending', 'approved', 'rejected'
  final String? reviewedBy; // Admin who reviewed
  final DateTime? reviewedAt;
  final String? reviewNotes; // Admin's review notes/comments

  AbsenceDocument({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.classId,
    required this.className,
    required this.subject,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.fileUrl,
    required this.fileName,
    required this.submittedAt,
    this.status = 'pending',
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNotes,
  });

  factory AbsenceDocument.fromMap(String id, Map<String, dynamic> map) {
    return AbsenceDocument(
      id: id,
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      classId: map['classId'] ?? '',
      className: map['className'] ?? '',
      subject: map['subject'] ?? '',
      startDate: (map['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (map['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reason: map['reason'] ?? '',
      fileUrl: map['fileUrl'] ?? '',
      fileName: map['fileName'] ?? '',
      submittedAt: (map['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: map['status'] ?? 'pending',
      reviewedBy: map['reviewedBy'],
      reviewedAt: (map['reviewedAt'] as Timestamp?)?.toDate(),
      reviewNotes: map['reviewNotes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'studentName': studentName,
      'classId': classId,
      'className': className,
      'subject': subject,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'reason': reason,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'submittedAt': Timestamp.fromDate(submittedAt),
      'status': status,
      'reviewedBy': reviewedBy,
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewNotes': reviewNotes,
    };
  }
}
