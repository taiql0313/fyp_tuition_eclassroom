import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fyp_tuition_eclassroom/services/announcement_service.dart';
import 'package:intl/intl.dart'; // Add intl package to pubspec.yaml for dates

class AnnouncementsPage extends StatelessWidget {
  const AnnouncementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AnnouncementService();
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Announcements")),
      body: currentUser == null
          ? const Center(child: Text("No announcements yet."))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).snapshots(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!userSnap.hasData || !userSnap.data!.exists) {
                  return const Center(child: Text("No announcements yet."));
                }

                final data = userSnap.data!.data() as Map<String, dynamic>?;
                final classIds = List<String>.from(data?['classIds'] ?? []);

                if (classIds.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        "No announcements. Join a class to see updates from your teachers.",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                // Firestore whereIn limit is 10; for the full page we'll paginate by first 10
                final limitedClassIds = classIds.length > 10 ? classIds.sublist(0, 10) : classIds;

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('announcements')
                      .where('classId', whereIn: limitedClassIds)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(child: Text("Unable to load announcements."));
                    }

                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return const Center(child: Text("No announcements for your classes yet."));
                    }

                    docs.sort((a, b) {
                      final tsA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                      final tsB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                      if (tsA == null && tsB == null) return 0;
                      if (tsA == null) return 1;
                      if (tsB == null) return -1;
                      return tsB.compareTo(tsA);
                    });

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        return _buildCard(data);
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildCard(Map<String, dynamic> data) {
    final type = data['type'] ?? 'class';
    final title = data['title'] ?? 'No Title';
    final content = data['content'] ?? '';
    final author = data['author'] ?? 'Admin';
    final Timestamp? ts = data['timestamp'];
    final dateStr = ts != null ? DateFormat('MMM d, h:mm a').format(ts.toDate()) : 'Just now';

    Color cardColor;
    IconData icon;

    switch (type) {
      case 'exam':
        cardColor = Colors.red.shade50;
        icon = Icons.warning_amber_rounded;
        break;
      case 'event':
        cardColor = Colors.orange.shade50;
        icon = Icons.celebration;
        break;
      default:
        cardColor = Colors.blue.shade50;
        icon = Icons.info_outline;
    }

    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.black54),
                const SizedBox(width: 8),
                Text(type.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54)),
                const Spacer(),
                Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Text(content, style: const TextStyle(fontSize: 15, height: 1.4)),
            const SizedBox(height: 12),
            Text("Posted by: $author", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}