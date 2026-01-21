import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../routes.dart';

class SubjectDetailPage extends StatefulWidget {
  // These are the "Inputs" from the Dashboard
  final Map<String, dynamic> classData;
  final String classId;

  const SubjectDetailPage({
    super.key,
    required this.classData,
    required this.classId
  });

  @override
  State<SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<SubjectDetailPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          // Shows the specific Subject Name automatically
          title: Text(
            widget.classData['className'] ?? 'Classroom',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(text: "Stream"),
              Tab(text: "Classwork"),
              Tab(text: "People"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildStreamTab(),
            _buildClassworkTab(),
            _buildPeopleTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showPostOptions(context),
          backgroundColor: Colors.blue,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  // --- TAB 1: STREAM (Filtered for THIS specific class) ---
  Widget _buildStreamTab() {
    return StreamBuilder<QuerySnapshot>(
      // Only get announcements for THIS classId
      stream: FirebaseFirestore.instance
          .collection('announcements')
          .where('classId', isEqualTo: widget.classId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState("No announcements yet.", Icons.announcement_outlined);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          // Inside _buildStreamTab -> ListView.builder -> itemBuilder
          itemBuilder: (context, index) {
            var post = snapshot.data!.docs[index].data() as Map<String, dynamic>;

            // --- ADD THIS SAFETY CHECK / 添加此安全检查 ---
            String displayDate = "";
            var dateValue = post['date']; // This is the 'date' field in announcements

            if (dateValue is Timestamp) {
              displayDate = DateFormat('MMM d, h:mm a').format(dateValue.toDate());
            } else {
              displayDate = dateValue?.toString() ?? "";
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(post['teacherName'] ?? 'Teacher'),
                subtitle: Text(post['content'] ?? ''),
                trailing: Text(displayDate), // Safe now / 现在安全了
              ),
            );
          },
        );
      },
    );
  }

  // --- TAB 2: CLASSWORK (Filtered for THIS specific class) ---
  // --- TAB 2: CLASSWORK (Updated for Assignments Collection) ---
  // --- TAB 2: CLASSWORK (Styled like the reference image) ---
  Widget _buildClassworkTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('assignments')
          .where('classId', isEqualTo: widget.classId)
      // Note: Ensure you have an index in Firestore if using orderBy
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState("No assignments posted.", Icons.assignment_outlined);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
            // Inside _buildClassworkTab -> ListView.builder
            // Inside _buildClassworkTab -> ListView.builder
            itemBuilder: (context, index) {
              var task = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              String assignmentId = snapshot.data!.docs[index].id; // Unique ID for this assignment

              // Formatting the date for display
              String formattedDate = "No Date";
              if (task['dueDate'] != null && task['dueDate'] is Timestamp) {
                formattedDate = DateFormat('MMM d, y').format((task['dueDate'] as Timestamp).toDate());
              }

              return InkWell(
                onTap: () {
                  // NAVIGATE TO DETAIL
                  Navigator.pushNamed(
                    context,
                    Routes.assignmentDetail,
                    arguments: {
                      'assignmentData': task,
                      'assignmentId': assignmentId,
                    },
                  );
                },
                child: _buildAssignmentCard(
                    task['title'] ?? 'Untitled',
                    formattedDate,
                    task['points']?.toString() ?? '100',
                    task['status'] ?? 'Assigned'
                ),
              );
            }
        );
      },
    );
  }

  Widget _buildAssignmentCard(String title, String dueDate, String points, String status) {
    // Logic to determine status color
    Color statusColor;
    Color statusBg;
    switch (status.toLowerCase()) {
      case 'missing': statusColor = Colors.red; statusBg = Colors.red.shade50; break;
      case 'submitted': statusColor = Colors.green; statusBg = Colors.green.shade50; break;
      case 'due soon': statusColor = Colors.orange; statusBg = Colors.orange.shade50; break;
      default: statusColor = Colors.blue; statusBg = Colors.blue.shade50;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Subject Name & Status Chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const CircleAvatar(radius: 4, backgroundColor: Colors.blue), // Subject dot
                  const SizedBox(width: 8),
                  Text(
                    widget.classData['className'] ?? 'Subject',
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Assignment Title
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          // Footer Row: Due Date and Points
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text("Due: $dueDate", style: const TextStyle(color: Colors.grey)),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.assignment_turned_in_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text("$points pts", style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- TAB 3: PEOPLE ---
  Widget _buildPeopleTab() {
    return const Center(child: Text("Students List will be linked here later"));
  }

  // --- HELPER UI METHODS ---

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: Colors.grey),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _showPostOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Wrap(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Create New Content", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          ListTile(
            leading: const Icon(Icons.assignment, color: Colors.blue),
            title: const Text('New Assignment'),
            onTap: () => Navigator.pushNamed(context, Routes.createAssignment, arguments: widget.classId),
          ),
          ListTile(
            leading: const Icon(Icons.announcement, color: Colors.green),
            title: const Text('New Announcement'),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildContentItem(String type, String title, IconData icon, Color color) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(type),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Logic to view the assignment
        },
      ),
    );
  }
}