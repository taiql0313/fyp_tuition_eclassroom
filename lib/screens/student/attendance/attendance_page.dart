import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_tuition_eclassroom/services/attendance_service.dart';
import 'package:fyp_tuition_eclassroom/services/user_service.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';
import 'package:fyp_tuition_eclassroom/models/attendance_models.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

// Import sub-pages
import 'take_attendance_page.dart';
import 'absence_document_page.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final AttendanceService _attendanceService = AttendanceService();
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  AppUser? _currentUser;
  String? _selectedClassId;
  Map<String, Map<String, dynamic>> _classes = {};
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    // Check for expired sessions when page loads
    _checkExpiredSessions();
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


  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final appUser = await _userService.getUser(user.uid);
    if (appUser == null) return;

    setState(() {
      _currentUser = appUser;
    });

    // Load class information
    if (appUser.classIds.isNotEmpty) {
      for (var classId in appUser.classIds) {
        final classDoc = await _db.collection('classrooms').doc(classId).get();
        if (classDoc.exists) {
          setState(() {
            _classes[classId] = classDoc.data()!;
            if (_selectedClassId == null) {
              _selectedClassId = classId;
            }
          });
        }
      }
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    if (_selectedClassId == null || _currentUser == null) return;
    
    final stats = await _attendanceService.getStudentStats(
      _currentUser!.uid,
      _selectedClassId!,
    );
    
    setState(() {
      _stats = stats;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Attendance Hub"),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Class Selection (if multiple classes)
            if (_classes.length > 1) ...[
              DropdownButtonFormField<String>(
                value: _selectedClassId,
                decoration: InputDecoration(
                  labelText: "Select Class",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                items: _classes.entries.map((entry) {
                  final classData = entry.value;
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text("${classData['subject'] ?? ''} - ${classData['className'] ?? ''}"),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedClassId = value;
                  });
                  _loadStats();
                },
              ),
              const SizedBox(height: 20),
            ],

            // --- 1. Summary Card ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xff1458a3), Color(0xff4a90e2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xff1458a3).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Attendance Rate",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _stats != null ? "${_stats!['rate']}%" : "0%",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "Present: ${_stats?['present'] ?? 0}",
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Excused: ${_stats?['excused'] ?? 0}",
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Absent: ${_stats?['absent'] ?? 0}",
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 30),
            const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            // --- 2. Action Cards ---
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    context,
                    title: "Check-In",
                    subtitle: "Enter Session Code", // Updated text
                    icon: Icons.keyboard_alt_outlined, // Updated icon to represent typing/code
                    color: Colors.blue,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TakeAttendancePage()),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildActionCard(
                    context,
                    title: "Submit MC",
                    subtitle: "Upload Documents",
                    icon: Icons.upload_file,
                    color: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AbsenceDocumentPage()),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),
            const Text("Recent History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            // --- 3. Real History List from Firebase ---
            _currentUser != null
                ? StreamBuilder<List<AttendanceRecord>>(
                    stream: _attendanceService.streamStudentRecords(_currentUser!.uid),
                    builder: (context, snapshot) {
                      // Get records - use existing data if available, even if stream is updating
                      final records = snapshot.hasData 
                          ? snapshot.data! 
                          : <AttendanceRecord>[];
                      
                      // Filter by selected class if applicable
                      final filteredRecords = _selectedClassId != null
                          ? records.where((r) => r.classId == _selectedClassId).toList()
                          : records;

                      // Show loading only on initial load (no data yet)
                      if (snapshot.connectionState == ConnectionState.waiting && 
                          records.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      // Show empty state only if we've fully loaded and there's no data
                      if (snapshot.connectionState == ConnectionState.active && 
                          filteredRecords.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [
                                Icon(Icons.history, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  _selectedClassId != null
                                      ? "No attendance records for this class"
                                      : "No attendance records yet",
                                  style: TextStyle(color: Colors.grey[600]),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // If we have records, show them (even if stream is updating)
                      if (filteredRecords.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredRecords.length > 10 ? 10 : filteredRecords.length,
                        itemBuilder: (context, index) {
                          final record = filteredRecords[index];
                          final isAbsent = record.status == 'absent';
                          final isExcused = record.status == 'excused';

                          return FutureBuilder<AbsenceDocument?>(
                            future: isExcused && record.absenceDocumentId != null
                                ? _attendanceService.getAbsenceDocument(record.absenceDocumentId!)
                                : Future.value(null),
                            builder: (context, docSnapshot) {
                              final doc = docSnapshot.data;
                              final reason = doc?.reason;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isAbsent
                                          ? Colors.red.shade50
                                          : isExcused
                                              ? Colors.orange.shade50
                                              : Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isAbsent
                                          ? Icons.close
                                          : isExcused
                                              ? Icons.info_outline
                                              : Icons.check_circle,
                                      color: isAbsent
                                          ? Colors.red
                                          : isExcused
                                              ? Colors.orange
                                              : Colors.green,
                                    ),
                                  ),
                                  title: Text(
                                    isAbsent
                                        ? "Absent"
                                        : isExcused
                                            ? "Absent (With Reason)"
                                            : "Present",
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "${record.subject} - ${record.className}",
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        DateFormat('MMM d, yyyy • h:mm a').format(
                                          TimezoneHelper.toMalaysiaTime(record.timestamp),
                                        ),
                                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                      ),
                                      if (isExcused && reason != null) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.description, size: 12, color: Colors.orange[700]),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  reason,
                                                  style: TextStyle(
                                                    color: Colors.orange[700],
                                                    fontSize: 11,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: isAbsent
                                      ? TextButton(
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const AbsenceDocumentPage(),
                                            ),
                                          ),
                                          child: const Text("Upload MC"),
                                        )
                                      : null,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  )
                : const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
      ),
    );
  }
}