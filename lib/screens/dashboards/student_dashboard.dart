import 'package:flutter/material.dart';
import 'package:fyp_tuition_eclassroom/screens/dashboards/student_dashboard.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Service & Route Imports
import '../../routes.dart';
import '../../services/auth_service.dart';
import '../../services/announcement_service.dart';

// Page Imports
import '../helpnsupport_page.dart';
import '../announcement_page.dart';
import '../student/student_chat_list.dart';
import '../student/attendance/attendance_page.dart';
import '../student/payment/payment_page.dart';
import '../student/notifications/notification_center_page.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  _StudentDashboardState createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final AnnouncementService _announcementService = AnnouncementService();

  @override
  Widget build(BuildContext context) {
    // Real logic from Old Version
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    final theme = Theme.of(context);
    final appBarColor = theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 1. App Bar with Real User Info & New UI Styling
          SliverAppBar(
            actions: [
              if (user != null) _buildNotificationButton(user.uid),
              IconButton(
                icon: Icon(Icons.chat_bubble_outline, color: theme.appBarTheme.foregroundColor ?? Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StudentChatListPage()),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: theme.appBarTheme.foregroundColor ?? Colors.white),
                onSelected: (value) async {
                  if (value == 'settings') {
                    Navigator.pushNamed(context, Routes.settings);
                  } else if (value == 'logout') {
                    await auth.signOut();
                    if (mounted) Navigator.pushReplacementNamed(context, Routes.login);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'profile', child: Text('Profile')),
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
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                user?.displayName?.substring(0, 1).toUpperCase() ?? "S",
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
                                  user?.displayName ?? "Student",
                                  style: TextStyle(color: theme.appBarTheme.foregroundColor ?? Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  user?.email ?? "ID: Loading...",
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
                  // Quick Stats Section (With Progress Bars)
                  _buildQuickStatsSection(),
                  const SizedBox(height: 25),

                  // Announcements Section (With Firebase Stream)
                  _buildAnnouncementsSection(),
                  const SizedBox(height: 25),

                  // Learning Tools Section (The 3-column grid)
                  _buildMyLearningSection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
              icon: Icon(Icons.notifications_none, color: Theme.of(context).appBarTheme.foregroundColor ?? Colors.white),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationCenterPage()),
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

  // --- STAT CARDS DESIGN ---
  Widget _buildQuickStatsSection() {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text("Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface)),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: [
            _buildStatCard('Attendance', '92%', Icons.calendar_today_outlined, const Color(0xFF2E7D32), 0.92),
            _buildStatCard('Assignments', '3 to-do', Icons.assignment_outlined, const Color(0xFF1565C0), 0.6),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, double progress) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 20, color: color),
              ),
              const Spacer(),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ),
    );
  }

  // --- ANNOUNCEMENTS DESIGN (STREAM) ---
  Widget _buildAnnouncementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text("Recent Announcements", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementsPage())),
              child: Text("See All", style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: _announcementService.streamRecentAnnouncements(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const Text("No announcements.");

            return SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  return _buildAnnouncementCard(data);
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    return Container(
      width: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: Text(data['type']?.toString().toUpperCase() ?? 'NOTICE',
                style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          Text(data['title'] ?? '',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const Spacer(),
          Text(data['course'] ?? 'General', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  // --- LEARNING TOOLS GRID ---
  Widget _buildMyLearningSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Learning Tools", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.9,
          children: [
            _buildLearningTool('Attendance', Icons.calendar_today_outlined, const Color(0xFF2E7D32),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendancePage()))),
            _buildLearningTool('Payment', Icons.payment_outlined, const Color(0xFFC2185B),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentPage()))),
            _buildLearningTool('Classroom', Icons.class_outlined, const Color(0xFFE65100),
                    () => Navigator.pushNamed(context, Routes.studentClassroomDashboard)),
            _buildLearningTool('Timetable', Icons.schedule_outlined, const Color(0xFF1976D2),
                    () => Navigator.pushNamed(context, Routes.studentTimetable)),
          ],
        ),
        const SizedBox(height: 20),
        // The Blue Quick Action Card
        _buildHelpCard(),
      ],
    );
  }

  Widget _buildLearningTool(String title, IconData icon, Color color, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpCard() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 32, color: onPrimary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Need Help?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: onPrimary)),
                Text("Ask our AI Tutor", style: TextStyle(fontSize: 13, color: onPrimary.withOpacity(0.8))),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FaqPage())),
            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.surface, foregroundColor: primary),
            child: const Text("Ask Now"),
          ),
        ],
      ),
    );
  }
}