import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


import '../../../routes.dart';
import '../classroom/join_classroom_page.dart';

class StudentClassroomDashboard extends StatelessWidget {
  const StudentClassroomDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Classrooms', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF1458A3),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- DYNAMIC HEADER ---
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return _buildHeader("0", "0", "0%");
                }

                final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                final classIds = List<String>.from(userData?['classIds'] ?? []);
                
                // Count only non-archived classes
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('classrooms')
                      .where(FieldPath.documentId, whereIn: classIds.isEmpty ? [''] : classIds.take(30).toList())
                      .snapshots(),
                  builder: (context, classSnapshot) {
                    int activeCount = 0;
                    if (classSnapshot.hasData) {
                      activeCount = classSnapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return data['isArchived'] != true;
                      }).length;
                    }
                    return _buildHeader(activeCount.toString(), "0", "0%");
                  },
                );
              },
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!userSnapshot.hasData) {
                    return const Center(child: Text("No classrooms found."));
                  }

                  final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                  final classIds = List<String>.from(userData?['classIds'] ?? []);

                  if (classIds.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.class_outlined, size: 80, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            "No classrooms yet",
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Tap the + button to join a classroom",
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    );
                  }

                  // Fetch classrooms that student is enrolled in
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('classrooms')
                        .where(FieldPath.documentId, whereIn: classIds)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text("No classrooms found."));
                      }

                      // Filter out archived classes - students cannot see archived classes
                      final classDocs = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return data['isArchived'] != true;
                      }).toList();

                      if (classDocs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.class_outlined, size: 80, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text(
                                "No active classrooms",
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Tap the + button to join a classroom",
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        );
                      }

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 15,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: classDocs.length,
                        itemBuilder: (context, index) {
                          var data = classDocs[index].data() as Map<String, dynamic>;
                          String docId = classDocs[index].id;

                          return _buildClassCard(
                            context,
                            docId,
                            data['className'] ?? 'Unnamed Class',
                            data['teacherName'] ?? 'Teacher',
                            data['subject'] ?? '',
                            Colors.blue.shade300,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const JoinClassroomPage()),
        ),
        backgroundColor: const Color(0xFF1458A3),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // --- HEADER ---
  Widget _buildHeader(String classCount, String tasks, String attendance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 25),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2196F3), Color(0xFF9C27B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStatItem(classCount, "Classes"),
          _buildStatItem(tasks, "Pending Tasks"),
          _buildStatItem(attendance, "Attendance"),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }

  // --- CLASS CARD (WITHOUT CLASS CODE) ---
  Widget _buildClassCard(
    BuildContext context,
    String classId,
    String title,
    String teacher,
    String subject,
    Color bgColor,
  ) {
    return InkWell(
      onTap: () {
        // Navigate to classroom detail (similar to teacher's subject detail)
        // For now, we can navigate to a student view of the classroom
        Navigator.pushNamed(
          context,
          Routes.subjectDetail,
          arguments: {
            'classData': {
              'className': title,
              'teacherName': teacher,
              'subject': subject,
            },
            'classId': classId,
          },
        );
      },
      onLongPress: () {
        // Show unenroll option on long press
        _showUnenrollDialog(context, classId, title);
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 5, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Subject badge instead of class code
                if (subject.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      subject,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                const SizedBox(width: 20),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              teacher,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                const Icon(Icons.people_outline, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('classIds', arrayContains: classId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      );
                    }
                    final count = snapshot.data?.docs.length ?? 0;
                    return Text(
                      count.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- UNENROLL DIALOG ---
  void _showUnenrollDialog(BuildContext context, String classId, String className) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Unenroll from Classroom"),
        content: Text("Are you sure you want to unenroll from \"$className\"?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _unenrollFromClassroom(context, classId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Unenroll"),
          ),
        ],
      ),
    );
  }

  // --- UNENROLL FUNCTION ---
  Future<void> _unenrollFromClassroom(BuildContext context, String classId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();
      final userData = userDoc.data() ?? {};
      final classIds = List<String>.from(userData['classIds'] ?? []);

      if (classIds.contains(classId)) {
        classIds.remove(classId);
        await userDocRef.update({
          'classIds': classIds,
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Successfully unenrolled from classroom"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error unenrolling: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
