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
  Map<String, String?> _selectedTimeSlot = {}; // classId -> selected time slot
  
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
  
  // Predefined time slots
  final List<Map<String, String>> _timeSlots = [
    {'label': '8:00 AM - 10:00 AM', 'start': '08:00', 'end': '10:00'},
    {'label': '10:00 AM - 12:00 PM', 'start': '10:00', 'end': '12:00'},
    {'label': '12:00 PM - 2:00 PM', 'start': '12:00', 'end': '14:00'},
    {'label': '2:00 PM - 4:00 PM', 'start': '14:00', 'end': '16:00'},
    {'label': '4:00 PM - 6:00 PM', 'start': '16:00', 'end': '18:00'},
    {'label': '6:00 PM - 8:00 PM', 'start': '18:00', 'end': '20:00'},
    {'label': '8:00 PM - 10:00 PM', 'start': '20:00', 'end': '22:00'},
    {'label': '10:00 PM - 12:00 AM', 'start': '22:00', 'end': '00:00'},
  ];

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
    // Use selected time or default to class's original time
    final selectedTime = _selectedTimeSlot[classId] ?? classData['classTime'];
    if (selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a time slot for the session"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isGenerating[classId] = true;
    });

    try {

      // Parse the selected time slot
      final timeSlot = _timeSlots.firstWhere(
        (slot) => slot['label'] == selectedTime,
      );
      
      // Use Malaysia time
      final now = TimezoneHelper.getMalaysiaTime();
      final startParts = timeSlot['start']!.split(':');
      final endParts = timeSlot['end']!.split(':');
      
      // Create DateTime objects for today in Malaysia time with the selected times
      DateTime allowedStart = TimezoneHelper.createMalaysiaDateTime(
        now.year,
        now.month,
        now.day,
        int.parse(startParts[0]),
        int.parse(startParts[1]),
      );
      
      // Handle end time - if it's 00:00, it means next day
      int endHour = int.parse(endParts[0]);
      DateTime allowedEnd;
      if (endHour == 0) {
        // Next day at midnight in Malaysia time
        allowedEnd = TimezoneHelper.createMalaysiaDateTime(
          now.year,
          now.month,
          now.day + 1,
          0,
          int.parse(endParts[1]),
        );
      } else {
        allowedEnd = TimezoneHelper.createMalaysiaDateTime(
          now.year,
          now.month,
          now.day,
          endHour,
          int.parse(endParts[1]),
        );
      }

      final session = await _attendanceService.createSession(
        classId: classId,
        className: classData['className'] ?? 'Class',
        subject: classData['subject'] ?? 'Subject',
        sessionTime: timeSlot['label'],
        allowedStartTime: allowedStart,
        allowedEndTime: allowedEnd,
      );

      if (!mounted) return;

      // Clear the selected time slot after successful creation
      setState(() {
        _selectedTimeSlot[classId] = null;
        _isGenerating[classId] = false;
      });

      // Wait a moment for Firestore stream to update before showing success
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Session started for ${classData['subject']}!"),
          backgroundColor: Colors.green,
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
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Class Attendance"),
        backgroundColor: primaryColor,
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
                                          // Time Slot Dropdown - Pre-filled with class's original time
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.grey.shade300),
                                            ),
                                            child: DropdownButtonFormField<String>(
                                              value: _selectedTimeSlot[classId] ?? classData['classTime'],
                                              decoration: const InputDecoration(
                                                labelText: "Session Time",
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                              ),
                                              hint: const Text("Choose time slot (Required)"),
                                              items: _timeSlots.map((slot) {
                                                return DropdownMenuItem<String>(
                                                  value: slot['label'],
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                                      const SizedBox(width: 8),
                                                      Text(slot['label']!),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (value) {
                                                setState(() {
                                                  _selectedTimeSlot[classId] = value;
                                                });
                                              },
                                            ),
                                          ),
                                          if (classData['classTime'] != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              "Default: ${classData['classTime']}",
                                              style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                                            ),
                                          ],
                                          const SizedBox(height: 12),
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
                                              onPressed: (isGenerating || _selectedTimeSlot[classId] == null)
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
                                                isGenerating ? "Creating..." : "Create Session Code",
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
class AttendanceRecordsPage extends StatelessWidget {
  final String sessionId;
  final String className;
  final String subject;
  final AttendanceService _attendanceService = AttendanceService();

  AttendanceRecordsPage({
    super.key,
    required this.sessionId,
    required this.className,
    required this.subject,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Attendance Records"),
        backgroundColor: const Color(0xff1458a3),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<AttendanceRecord>>(
        stream: _attendanceService.streamSessionRecords(sessionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
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
                    "Students can check in using the code",
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final records = snapshot.data!;
          final presentCount = records.where((r) => r.status == 'present').length;
          final absentCount = records.where((r) => r.status == 'absent').length;
          final excusedCount = records.where((r) => r.status == 'excused').length;

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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem("Present", presentCount, Colors.green),
                    _buildStatItem("Absent", absentCount, Colors.red),
                    _buildStatItem("Excused", excusedCount, Colors.orange),
                  ],
                ),
              ),

              // Records List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    final isPresent = record.status == 'present';
                    final isExcused = record.status == 'excused';

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
                        title: Text(
                          record.studentName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
          style: TextStyle(
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
}