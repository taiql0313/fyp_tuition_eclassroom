import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_tuition_eclassroom/services/attendance_service.dart';
import 'package:fyp_tuition_eclassroom/models/attendance_models.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';
import 'package:intl/intl.dart';

class CreateAttendanceCodePage extends StatefulWidget {
  const CreateAttendanceCodePage({super.key});

  @override
  State<CreateAttendanceCodePage> createState() => _CreateAttendanceCodePageState();
}

class _CreateAttendanceCodePageState extends State<CreateAttendanceCodePage> {
  final AttendanceService _attendanceService = AttendanceService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  Map<String, bool> _isGenerating = {}; // classId -> isGenerating
  
  @override
  void initState() {
    super.initState();
    // Check for expired sessions when page loads
    _checkExpiredSessions();
    // Also check periodically (every 5 minutes)
    _startPeriodicCheck();
  }

  void _startPeriodicCheck() {
    // Check for expired sessions every 5 minutes
    Future.delayed(const Duration(minutes: 5), () {
      if (mounted) {
        _checkExpiredSessions();
        _startPeriodicCheck(); // Schedule next check
      }
    });
  }

  Future<void> _checkExpiredSessions() async {
    // This will auto-close expired sessions and mark absent students
    try {
      await _attendanceService.checkAndCloseExpiredSessions();
    } catch (e) {
      // Silently handle - this is a background check
      print('Error checking expired sessions: $e');
    }
  }
  

  // Get today's day name in Malaysia time
  String _getTodayDayName() {
    return TimezoneHelper.getTodayDayName();
  }

  // Stream to get only today's classes
  Stream<QuerySnapshot> _getTodayClassesStream(String teacherId) {
    final todayDay = _getTodayDayName();
    return _db
        .collection('classrooms')
        .where('teacherId', isEqualTo: teacherId)
        .where('day', isEqualTo: todayDay)
        .snapshots();
  }

  void _handleGenerateCode(String classId, Map<String, dynamic> classData) async {
    // Get the class's scheduled time - teachers cannot choose, must use class time
    final timeStart = classData['timeStart'] as String?;
    final timeEnd = classData['timeEnd'] as String?;
    final classTimeDisplay = classData['classTime'] as String?;
    
    if (timeStart == null || timeEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Class time information is missing. Cannot generate attendance code."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isGenerating[classId] = true;
    });

    try {
      // Use Malaysia time
      final now = TimezoneHelper.getMalaysiaTime();
      
      // Parse the class's scheduled time (24-hour format: "10:00", "12:00")
      final startParts = timeStart.split(':');
      final endParts = timeEnd.split(':');
      
      if (startParts.length != 2 || endParts.length != 2) {
        throw Exception('Invalid time format in class schedule');
      }
      
      final startHour = int.parse(startParts[0]);
      final startMinute = int.parse(startParts[1]);
      final endHour = int.parse(endParts[0]);
      final endMinute = int.parse(endParts[1]);
      
      // Create DateTime objects for today in Malaysia time with the class's scheduled times
      DateTime allowedStart = TimezoneHelper.createMalaysiaDateTime(
        now.year,
        now.month,
        now.day,
        startHour,
        startMinute,
      );
      
      // Handle end time - if it's 00:00, it means next day
      DateTime allowedEnd;
      if (endHour == 0 && endMinute == 0) {
        // Next day at midnight in Malaysia time
        allowedEnd = TimezoneHelper.createMalaysiaDateTime(
          now.year,
          now.month,
          now.day + 1,
          0,
          0,
        );
      } else {
        allowedEnd = TimezoneHelper.createMalaysiaDateTime(
          now.year,
          now.month,
          now.day,
          endHour,
          endMinute,
        );
      }

      // Use the display time if available, otherwise format from timeStart/timeEnd
      final sessionTimeDisplay = classTimeDisplay ?? 
          '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')} - ${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';

      final session = await _attendanceService.createSession(
        classId: classId,
        className: classData['className'] ?? 'Class',
        subject: classData['subject'] ?? 'Subject',
        sessionTime: sessionTimeDisplay,
        allowedStartTime: allowedStart,
        allowedEndTime: allowedEnd,
      );

      if (!mounted) return;

      setState(() {
        _isGenerating[classId] = false;
      });

      // Wait a moment for Firestore stream to update before showing success
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Attendance code generated! Valid during class time: ${sessionTimeDisplay}"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating[classId] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error creating session: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleEndSession(String sessionId, String classId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("End Session"),
        content: const Text(
          "Are you sure you want to end this attendance session?\n\n"
          "Students who didn't check in will be automatically marked as absent.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("End Session", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Ending session and marking absent students..."),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _attendanceService.endSession(sessionId);
      if (!mounted) return;
      
      Navigator.pop(context); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Session ended. Absent students have been marked."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error ending session: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Code copied to clipboard")),
    );
  }


  Future<void> _viewAttendanceRecords(String sessionId, String className, String subject) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceRecordsPage(
          sessionId: sessionId,
          className: className,
          subject: subject,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xff1458a3);
    final user = _auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Class Attendance")),
        body: const Center(child: Text("Please log in")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Class Attendance"),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getTodayClassesStream(user.uid),
        builder: (context, classesSnapshot) {
          if (classesSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!classesSnapshot.hasData || classesSnapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    "No classes scheduled for ${_getTodayDayName()}",
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Only classes scheduled for today are shown here",
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final classes = classesSnapshot.data!.docs;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(
              children: [
                const Text(
                  "My Classes",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Color(0xff1458a3)),
                      const SizedBox(width: 4),
                      Text(
                        _getTodayDayName(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff1458a3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Classes scheduled for today. Select a class to generate an attendance code.",
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
                const SizedBox(height: 20),

                // Class List with Active Sessions
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: classes.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final classDoc = classes[index];
                    final classData = classDoc.data() as Map<String, dynamic>;
                    final classId = classDoc.id;

                    return StreamBuilder<List<AttendanceSession>>(
                      stream: _attendanceService.streamClassSessions(classId),
                      builder: (context, sessionsSnapshot) {
                        final isGenerating = _isGenerating[classId] ?? false;
                        
                        // Show loading state while generating OR while waiting for stream to update
                        if (isGenerating || 
                            (sessionsSnapshot.connectionState == ConnectionState.waiting && 
                             sessionsSnapshot.data == null)) {
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Center(
                                child: Column(
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 16),
                                    Text(
                                      isGenerating 
                                          ? "Creating session for ${classData['subject']}..."
                                          : "Loading...",
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        
                        final activeSessions = sessionsSnapshot.data ?? [];
                        final activeSession = activeSessions.isNotEmpty ? activeSessions.first : null;
                        final hasCode = activeSession != null;

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                            border: hasCode
                                ? Border.all(color: Colors.green.withOpacity(0.5), width: 1.5)
                                : Border.all(color: Colors.transparent),
                          ),
                          child: Column(
                            children: [
                              // Header Section
                              ListTile(
                                contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                                title: Text(
                                  classData['subject'] ?? 'Subject',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      classData['className'] ?? 'Class',
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                    if (classData['section'] != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        "Section: ${classData['section']}",
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          classData['day'] ?? 'Day not set',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(width: 12),
                                        const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          classData['classTime'] ?? 'Time not set',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    if (activeSession?.sessionTime != null) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.qr_code, size: 12, color: Colors.blue),
                                            const SizedBox(width: 4),
                                            Text(
                                              "Active: ${activeSession!.sessionTime}",
                                              style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (hasCode) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        "Started: ${DateFormat('MMM d, h:mm a').format(activeSession!.startTime)}",
                                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: hasCode ? Colors.green.shade50 : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    hasCode ? "ACTIVE" : "INACTIVE",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: hasCode ? Colors.green : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),

                              const Divider(height: 30),

                              // Action Section
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                child: hasCode
                                    ? _buildActiveCodeView(
                                        activeSession!,
                                        classData,
                                        classId,
                                      )
                                    : Column(
                                        children: [
                                          // Info card showing class time (read-only)
                                          if (classData['classTime'] != null) ...[
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.blue.shade200),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text(
                                                          "Session Time",
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.blue,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          classData['classTime'],
                                                          style: const TextStyle(
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.black87,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          "Code will be valid only during this time",
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.grey[700],
                                                            fontStyle: FontStyle.italic,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                          SizedBox(
                                            width: double.infinity,
                                            height: 45,
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: primaryColor,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                              onPressed: isGenerating
                                                  ? null
                                                  : () => _handleGenerateCode(classId, classData),
                                              icon: isGenerating
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child: CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : const Icon(Icons.qr_code_2, size: 18),
                                              label: Text(
                                                isGenerating ? "Creating..." : "Generate Attendance Code",
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Widget to display when a code is active
  Widget _buildActiveCodeView(
    AttendanceSession session,
    Map<String, dynamic> classData,
    String classId,
  ) {
    return Column(
      children: [
        const Text(
          "STUDENT CODE",
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              session.code,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: Color(0xff1458a3),
              ),
            ),
            const SizedBox(width: 15),
            IconButton(
              onPressed: () => _copyToClipboard(session.code),
              icon: const Icon(Icons.copy, color: Colors.grey),
              tooltip: "Copy Code",
            )
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          "Share this code with your students to check in.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _viewAttendanceRecords(
                  session.id,
                  classData['className'] ?? 'Class',
                  classData['subject'] ?? 'Subject',
                ),
                icon: const Icon(Icons.people, size: 16),
                label: const Text("View Records"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _handleEndSession(session.id, classId),
                icon: const Icon(Icons.stop, size: 16),
                label: const Text("End Session"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Page to view attendance records for a session
class AttendanceRecordsPage extends StatefulWidget {
  final String sessionId;
  final String className;
  final String subject;

  const AttendanceRecordsPage({
    super.key,
    required this.sessionId,
    required this.className,
    required this.subject,
  });

  @override
  State<AttendanceRecordsPage> createState() => _AttendanceRecordsPageState();
}

class _AttendanceRecordsPageState extends State<AttendanceRecordsPage> {
  final AttendanceService _attendanceService = AttendanceService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  String? _classId;
  List<Map<String, dynamic>> _allStudents = [];
  bool _loadingStudents = true;

  @override
  void initState() {
    super.initState();
    _loadSessionAndStudents();
  }

  Future<void> _loadSessionAndStudents() async {
    try {
      // Get session to find classId
      final sessionDoc = await _db.collection('attendance_sessions').doc(widget.sessionId).get();
      if (sessionDoc.exists) {
        final classId = sessionDoc.data()?['classId'] as String?;
        if (classId != null) {
          _classId = classId;
          // Load all students in this class
          final students = await _attendanceService.getClassStudents(classId);
          setState(() {
            _allStudents = students;
            _loadingStudents = false;
          });
        }
      }
    } catch (e) {
      print('Error loading students: $e');
      setState(() => _loadingStudents = false);
    }
  }

  void _showManualAttendanceDialog() {
    if (_classId == null || _allStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load students'), backgroundColor: Colors.red),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ManualAttendanceSheet(
        sessionId: widget.sessionId,
        classId: _classId!,
        className: widget.className,
        subject: widget.subject,
        allStudents: _allStudents,
        attendanceService: _attendanceService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Attendance Records"),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Manual Attendance',
            onPressed: _loadingStudents ? null : _showManualAttendanceDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadingStudents ? null : _showManualAttendanceDialog,
        backgroundColor: const Color(0xff1458a3),
        icon: const Icon(Icons.edit_note),
        label: const Text('Mark Attendance'),
      ),
      body: StreamBuilder<List<AttendanceRecord>>(
        stream: _attendanceService.streamSessionRecords(widget.sessionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data ?? [];
          final presentCount = records.where((r) => r.status == 'present').length;
          final absentCount = records.where((r) => r.status == 'absent').length;
          final excusedCount = records.where((r) => r.status == 'excused').length;
          final studentTaken = records.where((r) => r.takenBy == 'student').length;
          final teacherTaken = records.where((r) => r.takenBy == 'teacher').length;

          return Column(
            children: [
              // Summary Card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff1458a3), Color(0xff4a90e2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem("Present", presentCount, Colors.green),
                        _buildStatItem("Absent", absentCount, Colors.red),
                        _buildStatItem("Excused", excusedCount, Colors.orange),
                      ],
                    ),
                    if (records.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSmallTag('Student Check-in: $studentTaken', Colors.blue),
                          const SizedBox(width: 12),
                          _buildSmallTag('Teacher Entry: $teacherTaken', Colors.orange),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Records List
              if (records.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people_outline, size: 80, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          "No attendance records yet",
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Students can check in or tap 'Mark Attendance' to manually mark",
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final isPresent = record.status == 'present';
                      final isExcused = record.status == 'excused';
                      final isByTeacher = record.takenBy == 'teacher';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isPresent
                                  ? Colors.green.shade50
                                  : isExcused
                                      ? Colors.orange.shade50
                                      : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isPresent
                                  ? Icons.check
                                  : isExcused
                                      ? Icons.info
                                      : Icons.close,
                              color: isPresent
                                  ? Colors.green
                                  : isExcused
                                      ? Colors.orange
                                      : Colors.red,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                record.studentName,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (isByTeacher) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'MANUAL',
                                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.orange),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            DateFormat('MMM d, yyyy • h:mm a').format(
                              TimezoneHelper.toMalaysiaTime(record.timestamp),
                            ),
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isPresent
                                  ? Colors.green.shade50
                                  : isExcused
                                      ? Colors.orange.shade50
                                      : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              record.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isPresent
                                    ? Colors.green
                                    : isExcused
                                        ? Colors.orange
                                        : Colors.red,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    );
  }
}

// Bottom sheet for manual attendance marking
class ManualAttendanceSheet extends StatefulWidget {
  final String sessionId;
  final String classId;
  final String className;
  final String subject;
  final List<Map<String, dynamic>> allStudents;
  final AttendanceService attendanceService;

  const ManualAttendanceSheet({
    super.key,
    required this.sessionId,
    required this.classId,
    required this.className,
    required this.subject,
    required this.allStudents,
    required this.attendanceService,
  });

  @override
  State<ManualAttendanceSheet> createState() => _ManualAttendanceSheetState();
}

class _ManualAttendanceSheetState extends State<ManualAttendanceSheet> {
  final Map<String, String> _studentStatuses = {}; // studentId -> status
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Initialize all students as 'present' by default
    for (var student in widget.allStudents) {
      _studentStatuses[student['uid']] = 'present';
    }
  }

  Future<void> _saveAttendance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      final studentNames = <String, String>{};
      for (var student in widget.allStudents) {
        final id = student['uid'] as String;
        final name = (student['displayName'] as String?) ?? 'Student';
        studentNames[id] = name;
      }

      await widget.attendanceService.markBulkAttendanceByTeacher(
        sessionId: widget.sessionId,
        classId: widget.classId,
        className: widget.className,
        subject: widget.subject,
        studentStatuses: _studentStatuses,
        teacherId: user.uid,
        teacherName: user.displayName ?? 'Teacher',
        studentNames: studentNames,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xff1458a3).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.edit_note, color: Color(0xff1458a3)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Manual Attendance',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          Text(
                            '${widget.allStudents.length} students in this class',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _saving ? null : _saveAttendance,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff1458a3),
                        foregroundColor: Colors.white,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Quick actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            for (var student in widget.allStudents) {
                              _studentStatuses[student['uid']] = 'present';
                            }
                          });
                        },
                        icon: const Icon(Icons.check_circle, size: 16),
                        label: const Text('All Present'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            for (var student in widget.allStudents) {
                              _studentStatuses[student['uid']] = 'absent';
                            }
                          });
                        },
                        icon: const Icon(Icons.cancel, size: 16),
                        label: const Text('All Absent'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Student list
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: widget.allStudents.length,
              itemBuilder: (context, index) {
                final student = widget.allStudents[index];
                final studentId = student['uid'] as String;
                final studentName = student['displayName'] as String;
                final currentStatus = _studentStatuses[studentId] ?? 'present';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xff1458a3).withOpacity(0.1),
                          child: Text(
                            studentName.isNotEmpty ? studentName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Color(0xff1458a3),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            studentName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        // Status buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatusButton(studentId, 'present', Icons.check, Colors.green, currentStatus),
                            const SizedBox(width: 4),
                            _buildStatusButton(studentId, 'absent', Icons.close, Colors.red, currentStatus),
                            const SizedBox(width: 4),
                            _buildStatusButton(studentId, 'excused', Icons.info_outline, Colors.orange, currentStatus),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusButton(String studentId, String status, IconData icon, Color color, String currentStatus) {
    final isSelected = currentStatus == status;
    return InkWell(
      onTap: () {
        setState(() {
          _studentStatuses[studentId] = status;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? Colors.white : Colors.grey,
        ),
      ),
    );
  }
}