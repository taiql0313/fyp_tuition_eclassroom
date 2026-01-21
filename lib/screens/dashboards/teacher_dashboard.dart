import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../routes.dart';

// --- PAGE IMPORTS ---
import '../teacher/create_announcement_page.dart';
import '../teacher/teacher_chat_list.dart';
import '../teacher/create_attendance_code_page.dart'; // 👈 NEW IMPORT

class TeacherDashboard extends StatelessWidget {
  const TeacherDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Row(
          children: [
            CircleAvatar(
                backgroundColor: Color(0xFFFFB74D),
                child: Icon(Icons.school, color: Colors.white, size: 20)
            ),
            SizedBox(width: 10),
            Text('Teacher Hub', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.black54),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TeacherChatListPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black54),
            onPressed: () {},
          ),
          IconButton(
              onPressed: () async {
                await auth.signOut();
                if (context.mounted) Navigator.pushReplacementNamed(context, Routes.login);
              },
              icon: const Icon(Icons.logout, color: Colors.redAccent))
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            // "Create" Row
            Row(
              children: [
                // 1. New Assignment Button
                Expanded(
                    child: _quickActionBtn(
                        context,
                        "New\nAssignment",
                        Icons.add_task,
                        const Color(0xFF66BB6A)
                    )
                ),

                const SizedBox(width: 15),

                // 2. Post Update Button
                Expanded(
                    child: _quickActionBtn(
                      context,
                      "Post\nUpdate",
                      Icons.campaign,
                      const Color(0xFFFFA726),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CreateAnnouncementPage()),
                        );
                      },
                    )
                ),
              ],
            ),

            const SizedBox(height: 30),
            const Text("Class Management", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            // Grid Menu
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
                    Routes.login,
                    onTap: () => Navigator.pushNamed(context, Routes.classroomDashboard),
                ),

                // 👇 ATTENDANCE TILE - LINKED TO CODE GENERATOR
                _teacherTile(
                  context,
                  'Attendance',
                  Icons.how_to_reg_outlined,
                  Routes.login,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateAttendanceCodePage()),
                  ),
                ),

                _teacherTile(
                    context,
                    'Quizzes',
                    Icons.quiz_outlined,
                    Routes.login,
                    onTap: () => Navigator.pushNamed(context, Routes.createQuiz)
                ),

                _teacherTile(context, 'Student Analytics', Icons.analytics_outlined, Routes.login),

                // MESSAGES TILE
                _teacherTile(
                  context,
                  'Messages',
                  Icons.chat_bubble_outline,
                  Routes.login,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TeacherChatListPage()),
                  ),
                ),

                _teacherTile(context, 'Grading', Icons.grade_outlined, Routes.login),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _quickActionBtn(BuildContext c, String label, IconData icon, Color color, {VoidCallback? onTap}) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap ?? () => Navigator.pushNamed(c, Routes.login),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _teacherTile(BuildContext c, String title, IconData icon, String route, {VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // 👇 USE CUSTOM onTap IF PROVIDED
        onTap: onTap ?? () => Navigator.pushNamed(c, route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.black87),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}