import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/student_teacher_chat_service.dart';
import '../../routes.dart';

// --- PAGE IMPORTS ---
import '../teacher/create_announcement_page.dart';
import '../teacher/teacher_chat_list.dart';
import '../teacher/create_attendance_code_page.dart';
import '../teacher/notifications/teacher_notification_center_page.dart';
import '../../services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  final _chatService = StudentTeacherChatService();
  final _notificationService = NotificationService();
  bool _hasCheckedAttendanceThisWeek = false;

  @override
  void initState() {
    super.initState();
    _checkWeeklyLowAttendance();
  }

  Future<void> _checkWeeklyLowAttendance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckKey = 'last_attendance_check_${user.uid}';
      final lastCheck = prefs.getString(lastCheckKey);
      
      final now = DateTime.now();
      final currentMonday = now.subtract(Duration(days: now.weekday - 1));
      final mondayStr = '${currentMonday.year}-${currentMonday.month}-${currentMonday.day}';

      if (lastCheck == mondayStr) {
        _hasCheckedAttendanceThisWeek = true;
        return;
      }

      // Get teacher's classes
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classrooms')
          .where('teacherId', isEqualTo: user.uid)
          .get();

      if (classesSnapshot.docs.isEmpty) return;

      final lowAttendanceStudents = <Map<String, dynamic>>[];

      for (var classDoc in classesSnapshot.docs) {
        final classId = classDoc.id;
        final classData = classDoc.data();
        final className = classData['className'] ?? 'Unknown Class';

        // Get students in this class
        final studentsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('classIds', arrayContains: classId)
            .where('role', isEqualTo: 'student')
            .get();

        for (var studentDoc in studentsSnapshot.docs) {
          final studentId = studentDoc.id;
          final studentData = studentDoc.data();
          final studentName = studentData['displayName'] ?? 'Unknown';

          // Get attendance sessions for this class
          final sessionsSnapshot = await FirebaseFirestore.instance
              .collection('attendance_sessions')
              .where('classId', isEqualTo: classId)
              .get();

          if (sessionsSnapshot.docs.isEmpty) continue;

          int totalSessions = sessionsSnapshot.docs.length;
          int attendedSessions = 0;

          for (var session in sessionsSnapshot.docs) {
            final recordSnapshot = await FirebaseFirestore.instance
                .collection('attendance_records')
                .where('sessionId', isEqualTo: session.id)
                .where('studentId', isEqualTo: studentId)
                .get();

            if (recordSnapshot.docs.isNotEmpty) {
              attendedSessions++;
            }
          }

          final percentage = totalSessions > 0 ? (attendedSessions / totalSessions) * 100 : 0.0;

          if (percentage < 50 && totalSessions >= 3) {
            lowAttendanceStudents.add({
              'studentName': studentName,
              'className': className,
              'percentage': percentage,
            });
          }
        }
      }

      // Create notification if there are low attendance students
      if (lowAttendanceStudents.isNotEmpty) {
        final count = lowAttendanceStudents.length;
        final message = count == 1
            ? '${lowAttendanceStudents[0]['studentName']} has ${lowAttendanceStudents[0]['percentage'].toStringAsFixed(0)}% attendance in ${lowAttendanceStudents[0]['className']}'
            : '$count students have attendance below 50%';

        await _notificationService.createForUser(
          userId: user.uid,
          type: 'attendance',
          title: 'Low Attendance Alert',
          message: message,
        );
      }

      // Save that we checked this week
      await prefs.setString(lastCheckKey, mondayStr);
      _hasCheckedAttendanceThisWeek = true;
    } catch (e) {
      print('Error checking weekly attendance: $e');
    }
  }

  Widget _buildNotificationButton(String userId) {
    final stream = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        var unreadCount = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['read'] != true) unreadCount++;
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(
                Icons.notifications_none,
                color: Theme.of(context).appBarTheme.foregroundColor ?? Colors.white,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TeacherNotificationCenterPage()),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final String uid = user?.uid ?? "";

    final theme = Theme.of(context);
    final appBarColor = theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            actions: [
              IconButton(
                icon: Icon(Icons.chat_bubble_outline, color: theme.appBarTheme.foregroundColor ?? Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TeacherChatListPage()),
                ),
              ),
              _buildNotificationButton(uid),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: theme.appBarTheme.foregroundColor ?? Colors.white),
                onSelected: (value) async {
                  if (value == 'settings') {
                    Navigator.pushNamed(context, Routes.settings);
                  } else if (value == 'logout') {
                    await auth.signOut();
                    if (context.mounted) Navigator.pushReplacementNamed(context, Routes.login);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'settings', child: Text('Settings')),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Text('Logout', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
            expandedHeight: 180.0,
            floating: false,
            pinned: true,
            backgroundColor: appBarColor,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                color: appBarColor,
                padding: const EdgeInsets.all(20),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(color: theme.colorScheme.surface, shape: BoxShape.circle),
                            child: Center(
                              child: Text(
                                user?.displayName?.substring(0, 1).toUpperCase() ?? "T",
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Welcome back,", style: TextStyle(color: (theme.appBarTheme.foregroundColor ?? Colors.white).withOpacity(0.9), fontSize: 14)),
                                const SizedBox(height: 4),
                                Text(
                                  user?.displayName ?? "Teacher",
                                  style: TextStyle(color: theme.appBarTheme.foregroundColor ?? Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user?.email ?? "Email: Loading...",
                                  style: TextStyle(color: (theme.appBarTheme.foregroundColor ?? Colors.white).withOpacity(0.8), fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Body Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overview Section - Latest Quiz Marks
                  const Text("Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  _buildLatestQuizMarksTable(uid),

                  const SizedBox(height: 30),
                  const Text("Class Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),

                  // Grid Menu with Colored Circular Icons
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    children: <Widget>[
                      _teacherTile(
                        context,
                        'My Classes',
                        Icons.class_outlined,
                        const Color(0xFFE3F2FD), // Light blue
                        const Color(0xFF1976D2), // Dark blue
                        Routes.login,
                        onTap: () => Navigator.pushNamed(context, Routes.classroomDashboard),
                      ),

                      // 👇 ATTENDANCE TILE - LINKED TO CODE GENERATOR
                      _teacherTile(
                        context,
                        'Attendance',
                        Icons.how_to_reg_outlined,
                        const Color(0xFFE8F5E9), // Light green
                        const Color(0xFF388E3C), // Dark green
                        Routes.login,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CreateAttendanceCodePage()),
                        ),
                      ),

                      // MESSAGES TILE
                      _teacherTile(
                        context,
                        'Messages',
                        Icons.chat_bubble_outline,
                        const Color(0xFFE8F5E9), // Light green
                        const Color(0xFF388E3C), // Dark green
                        Routes.login,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TeacherChatListPage()),
                        ),
                      ),

                      // REPLACEMENT CLASS TILE
                      _teacherTile(
                        context,
                        'Replacement\nClass',
                        Icons.event_repeat,
                        const Color(0xFFE1F5FE), // Light blue
                        const Color(0xFF0277BD), // Dark blue
                        Routes.login,
                        onTap: () => Navigator.pushNamed(context, Routes.teacherTimetableChange),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),
                  // Recent Activities Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Recent Activities", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      InkWell(
                        onTap: () {

                        },
                        child: const Text(
                          "View All",
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF2196F3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildRecentActivities(uid),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- OVERVIEW CARD WIDGET ---
  Widget _buildOverviewCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Widget mainText,
    required String subtitle,
    required VoidCallback onViewTap,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(13.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                InkWell(
                  onTap: onViewTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "View",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            mainText,
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- DATA BUILDERS FOR OVERVIEW CARDS ---

  Widget _buildPendingAssignmentsCount(String teacherId) {
    // First get teacher's classes, then count assignments
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('classrooms')
          .where('teacherId', isEqualTo: teacherId)
          .snapshots(),
      builder: (context, classesSnapshot) {
        if (!classesSnapshot.hasData || classesSnapshot.data!.docs.isEmpty) {
          return Text("0 assignments", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface));
        }

        final classIds = classesSnapshot.data!.docs.map((doc) => doc.id).toList();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('assignments')
              .where('classId', whereIn: classIds.length > 10 ? classIds.take(10).toList() : classIds)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Text("0 assignments", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface));
            }

            final now = DateTime.now();
            int pendingCount = 0;

            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final dueDate = data['dueDate'] as Timestamp?;
              
              // Count assignments that haven't passed their due date
              if (dueDate != null && dueDate.toDate().isAfter(now)) {
                pendingCount++;
              } else if (dueDate == null) {
                // If no due date, count as pending
                pendingCount++;
              }
            }

            return Text(
              "$pendingCount assignments",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
            );
          },
        );
      },
    );
  }

  Widget _buildTodayAttendance(String teacherId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('classrooms')
          .where('teacherId', isEqualTo: teacherId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Text("Today: 0%", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface));
        }

        // For now, return a placeholder. You can implement actual attendance calculation
        // by querying attendance records for today
        return FutureBuilder<double>(
          future: _calculateTodayAttendance(teacherId, snapshot.data!.docs),
          builder: (context, attendanceSnapshot) {
            final percentage = attendanceSnapshot.data ?? 0.0;
            return Text(
              "Today: ${percentage.toStringAsFixed(0)}%",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
            );
          },
        );
      },
    );
  }

  Future<double> _calculateTodayAttendance(String teacherId, List<QueryDocumentSnapshot> classes) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      int totalStudents = 0;
      int presentStudents = 0;

      for (var classDoc in classes) {
        final classId = classDoc.id;
        final classData = classDoc.data() as Map<String, dynamic>;
        final studentIds = (classData['studentIds'] as List<dynamic>?) ?? [];

        // Get today's attendance sessions for this class
        final sessions = await FirebaseFirestore.instance
            .collection('attendance_sessions')
            .where('classId', isEqualTo: classId)
            .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('startTime', isLessThan: Timestamp.fromDate(endOfDay))
            .get();

        for (var session in sessions.docs) {
          final records = await FirebaseFirestore.instance
              .collection('attendance_records')
              .where('sessionId', isEqualTo: session.id)
              .get();

          totalStudents += studentIds.length;
          presentStudents += records.docs.length;
        }
      }

      if (totalStudents == 0) return 0.0;
      return (presentStudents / totalStudents) * 100;
    } catch (e) {
      print('Error calculating attendance: $e');
      return 0.0;
    }
  }

  Widget _buildUnreadMessagesCount(String teacherId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _chatService.getUserChats(teacherId, 'teacher'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Text("0 unread", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface));
        }

        int totalUnread = 0;
        for (var chat in snapshot.data!) {
          totalUnread += (chat['unreadCount'] as int? ?? 0);
        }

        return Text(
          "$totalUnread unread",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
        );
      },
    );
  }

  Widget _buildTotalClassesCount(String teacherId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('classrooms')
          .where('teacherId', isEqualTo: teacherId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Text("0 classes", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface));
        }

        final count = snapshot.data!.docs.length;

        return Text(
          "$count classes",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
        );
      },
    );
  }

  Widget _teacherTile(
    BuildContext c,
    String title,
    IconData icon,
    Color circleColor,
    Color iconColor,
    String route, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(c);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ?? () => Navigator.pushNamed(c, route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // --- RECENT ACTIVITIES WIDGET ---
  Widget _buildRecentActivities(String teacherId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('classrooms')
          .where('teacherId', isEqualTo: teacherId)
          .snapshots(),
      builder: (context, classesSnapshot) {
        if (!classesSnapshot.hasData || classesSnapshot.data!.docs.isEmpty) {
          return _buildEmptyActivities();
        }

        final classIds = classesSnapshot.data!.docs.map((doc) => doc.id).toList();

        // Combine streams for quizzes, announcements, and assignments
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getRecentActivitiesStream(classIds),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyActivities();
            }

            final activities = snapshot.data!;
            // Sort by timestamp descending and take first 4
            activities.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));
            final recentActivities = activities.take(4).toList();

            final theme = Theme.of(context);
            return Container(
              decoration: BoxDecoration(
                color: theme.cardTheme.color ?? theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: recentActivities.asMap().entries.map((entry) {
                    final index = entry.key;
                    final activity = entry.value;
                    return _buildActivityItem(activity, isLast: index == recentActivities.length - 1);
                  }).toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Stream<List<Map<String, dynamic>>> _getRecentActivitiesStream(List<String> classIds) {
    // Use a single stream that combines data from multiple sources
    // We'll listen to one primary stream and fetch others as needed
    final teacherId = FirebaseAuth.instance.currentUser?.uid ?? "";
    
    return FirebaseFirestore.instance
        .collection('quizzes')
        .where('teacherId', isEqualTo: teacherId)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .asyncMap((quizzesSnapshot) async {
      final allActivities = <Map<String, dynamic>>[];

      // Add quizzes
      for (var doc in quizzesSnapshot.docs) {
        final data = doc.data();
        allActivities.add({
          'type': 'quiz',
          'title': data['title'] ?? 'Untitled Quiz',
          'timestamp': (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          'icon': Icons.quiz_outlined,
          'iconColor': const Color(0xFF7B1FA2),
          'iconBgColor': const Color(0xFFF3E5F5),
        });
      }

      // Fetch announcements
      try {
        final announcementsQuery = classIds.length > 10 
            ? classIds.take(10).toList() 
            : classIds;
        final announcementsSnapshot = await FirebaseFirestore.instance
            .collection('announcements')
            .where('classId', whereIn: announcementsQuery)
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        for (var doc in announcementsSnapshot.docs) {
          final data = doc.data();
          allActivities.add({
            'type': 'announcement',
            'title': data['title'] ?? 'Untitled Announcement',
            'timestamp': (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            'icon': Icons.campaign,
            'iconColor': const Color(0xFFF57C00),
            'iconBgColor': const Color(0xFFFFF3E0),
          });
        }
      } catch (e) {
        print('Error fetching announcements: $e');
      }

      // Fetch assignments
      try {
        final assignmentsQuery = classIds.length > 10 
            ? classIds.take(10).toList() 
            : classIds;
        final assignmentsSnapshot = await FirebaseFirestore.instance
            .collection('assignments')
            .where('classId', whereIn: assignmentsQuery)
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        for (var doc in assignmentsSnapshot.docs) {
          final data = doc.data();
          allActivities.add({
            'type': 'assignment',
            'title': data['title'] ?? 'Untitled Assignment',
            'timestamp': (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            'icon': Icons.assignment_outlined,
            'iconColor': const Color(0xFF1976D2),
            'iconBgColor': const Color(0xFFE3F2FD),
          });
        }
      } catch (e) {
        print('Error fetching assignments: $e');
      }

      return allActivities;
    });
  }

  Widget _buildLatestQuizMarksTable(String teacherId) {
    // Try with orderBy first, fallback to without orderBy if index missing
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('quizzes')
          .where('teacherId', isEqualTo: teacherId)
          .snapshots(),
      builder: (context, quizSnapshot) {
        if (quizSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
        }

        if (quizSnapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Column(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 32),
                const SizedBox(height: 8),
                Text(
                  'Error loading quiz: ${quizSnapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (!quizSnapshot.hasData || quizSnapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(
              child: Text('No quizzes created yet', style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        // Find newest quiz by sorting in memory (fallback if orderBy index missing)
        final allQuizzes = quizSnapshot.data!.docs.toList();
        allQuizzes.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['createdAt'] as Timestamp?;
          final bTime = bData['createdAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime); // Descending
        });

        final newestQuiz = allQuizzes.first;
        final quizData = newestQuiz.data() as Map<String, dynamic>;
        final quizId = newestQuiz.id;
        final classId = quizData['classId'] as String?;
        final quizTitle = quizData['title'] as String? ?? 'Untitled Quiz';

        print('DEBUG: Found newest quiz: $quizTitle, classId=$classId, quizId=$quizId');

        if (classId == null || classId.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Center(
              child: Text('Latest quiz has no class assigned', style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        // Get class name
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('classrooms').doc(classId).snapshots(),
          builder: (context, classSnapshot) {
            final classData = classSnapshot.data?.data() as Map<String, dynamic>?;
            final className = classData?['className'] as String? ?? 'Unknown Class';

            // Get all students in this class
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('classIds', arrayContains: classId)
                  .where('role', isEqualTo: 'student')
                  .snapshots(),
              builder: (context, studentsSnapshot) {
                if (studentsSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                }

                if (studentsSnapshot.hasError) {
                  print('DEBUG: Error loading students: ${studentsSnapshot.error}');
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Text('Error loading students: ${studentsSnapshot.error}', style: const TextStyle(color: Colors.red)),
                  );
                }

                final students = studentsSnapshot.data?.docs ?? [];
                print('DEBUG: Found ${students.length} students in class $classId');

                  // Get quiz submissions
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('quiz_submissions')
                        .where('quizId', isEqualTo: quizId)
                        .snapshots(),
                    builder: (context, submissionsSnapshot) {
                      if (submissionsSnapshot.hasError) {
                        print('DEBUG: Error loading submissions: ${submissionsSnapshot.error}');
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Text('Error loading submissions: ${submissionsSnapshot.error}', style: const TextStyle(color: Colors.red)),
                        );
                      }

                      final submissions = submissionsSnapshot.data?.docs ?? [];
                      print('DEBUG: Found ${submissions.length} submissions for quiz $quizId');
                      final submissionMap = <String, Map<String, dynamic>>{};
                      for (var sub in submissions) {
                        final data = sub.data() as Map<String, dynamic>;
                        final studentId = data['studentId'] as String?;
                        if (studentId != null) {
                          submissionMap[studentId] = data;
                          print('DEBUG: Submission for student $studentId: score=${data['totalScore']}/${data['maxTotalScore']}');
                        }
                      }

                    // Combine students with their submissions
                    final List<Map<String, dynamic>> studentMarks = [];
                    for (var studentDoc in students) {
                      final studentData = studentDoc.data() as Map<String, dynamic>;
                      final studentId = studentDoc.id;
                      final studentName = studentData['displayName'] as String? ?? 'Unknown Student';
                      final submission = submissionMap[studentId];

                      studentMarks.add({
                        'studentId': studentId,
                        'studentName': studentName,
                        'submission': submission,
                        'totalScore': submission?['totalScore'] as int? ?? 0,
                        'maxTotalScore': submission?['maxTotalScore'] as int? ?? 0,
                        'hasSubmitted': submission != null,
                      });
                    }

                    // Sort by score (highest first), then not submitted at end
                    studentMarks.sort((a, b) {
                      if (!a['hasSubmitted'] && !b['hasSubmitted']) return 0;
                      if (!a['hasSubmitted']) return 1;
                      if (!b['hasSubmitted']) return -1;
                      final scoreA = a['totalScore'] as int;
                      final scoreB = b['totalScore'] as int;
                      return scoreB.compareTo(scoreA);
                    });

                    // Debug info
                    print('DEBUG Quiz Marks: Quiz=$quizTitle, Class=$className, Students=${students.length}, Submissions=${submissions.length}, Marks=${studentMarks.length}');

                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.quiz, color: Colors.purple, size: 24),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        quizTitle,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        className,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          SizedBox(
                            height: 300,
                            child: students.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(20),
                                      child: Text('No students enrolled in this class', style: TextStyle(color: Colors.grey)),
                                    ),
                                  )
                                : studentMarks.isEmpty
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(20),
                                          child: Text('No student marks to display', style: TextStyle(color: Colors.grey)),
                                        ),
                                      )
                                : SingleChildScrollView(
                                    child: Table(
                                      columnWidths: const {
                                        0: FlexColumnWidth(2),
                                        1: FlexColumnWidth(1),
                                      },
                                      children: [
                                        // Header
                                        TableRow(
                                          decoration: BoxDecoration(color: Colors.grey.shade100),
                                          children: const [
                                            Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Text('Student Name', style: TextStyle(fontWeight: FontWeight.bold)),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Center(
                                                child: Text('Score', style: const TextStyle(fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Rows
                                        ...studentMarks.map((mark) {
                                          final hasSubmitted = mark['hasSubmitted'] as bool;
                                          final totalScore = mark['totalScore'] as int;
                                          final maxScore = mark['maxTotalScore'] as int;
                                          final scoreText = hasSubmitted
                                              ? '$totalScore / $maxScore'
                                              : 'Not submitted';
                                          final scoreColor = hasSubmitted
                                              ? (totalScore >= maxScore * 0.8
                                                  ? Colors.green
                                                  : totalScore >= maxScore * 0.5
                                                      ? Colors.orange
                                                      : Colors.red)
                                              : Colors.grey;

                                          return TableRow(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.all(12),
                                                child: Text(mark['studentName'] as String),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(12),
                                                child: Center(
                                                  child: Text(
                                                    scoreText,
                                                    style: TextStyle(color: scoreColor, fontWeight: FontWeight.w500),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity, {bool isLast = false}) {
    final theme = Theme.of(context);
    final timestamp = activity['timestamp'] as DateTime;
    final timeAgo = _getTimeAgo(timestamp);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0.0 : 16.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: activity['iconBgColor'] as Color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              activity['icon'] as IconData,
              color: activity['iconColor'] as Color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getActivityDescription(activity),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeAgo,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getActivityDescription(Map<String, dynamic> activity) {
    final type = activity['type'] as String;
    final title = activity['title'] as String;

    switch (type) {
      case 'quiz':
        return 'Created Quiz: $title';
      case 'announcement':
        return 'Posted Announcement: $title';
      case 'assignment':
        return 'Created Assignment: $title';
      default:
        return title;
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildEmptyActivities() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Text(
          'No recent activities',
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}