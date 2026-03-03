import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../routes.dart';

class ClassroomDashboard extends StatelessWidget {
  const ClassroomDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Classrooms', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Archived'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildActiveClassesTab(uid),
            _buildArchivedClassesTab(uid),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.pushNamed(context, Routes.createSubject),
          backgroundColor: Colors.blue,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildActiveClassesTab(String uid) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // --- DYNAMIC HEADER ---
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('classrooms')
                .where('teacherId', isEqualTo: uid)
                .snapshots(),
            builder: (context, snapshot) {
              // Filter active classes (isArchived != true or null)
              int classCount = 0;
              final classIds = <String>[];

              if (snapshot.hasData) {
                for (final doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['isArchived'] != true) {
                    classCount++;
                    classIds.add(doc.id);
                  }
                }
              }

              return FutureBuilder<int>(
                future: _calculatePendingTasks(uid, classIds),
                builder: (context, taskSnapshot) {
                  final pendingCount = taskSnapshot.data ?? 0;
                  return _buildHeader(classCount.toString(), pendingCount.toString());
                },
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('classrooms')
                  .where('teacherId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text("No classrooms found."),
                    ),
                  );
                }

                // Filter active classes (isArchived != true or null)
                final classDocs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['isArchived'] != true; // true means archived, false or null means active
                }).toList();

                if (classDocs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text("No active classrooms found."),
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

                    return InkWell(
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          Routes.subjectDetail,
                          arguments: {
                            'classData': data,
                            'classId': docId,
                          },
                        );
                      },
                      child: _buildClassCard(
                        docId,
                        data['className'] ?? 'Unnamed Class',
                        data['teacherName'] ?? 'Teacher',
                        data['classCode'] ?? 'N/A',
                        Colors.blue.shade300,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedClassesTab(String uid) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('classrooms')
                  .where('teacherId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.archive_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text("No archived classrooms."),
                        ],
                      ),
                    ),
                  );
                }

                // Filter archived classes (isArchived == true)
                final classDocs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['isArchived'] == true;
                }).toList();

                if (classDocs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.archive_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text("No archived classrooms."),
                        ],
                      ),
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

                    return InkWell(
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          Routes.subjectDetail,
                          arguments: {
                            'classData': data,
                            'classId': docId,
                          },
                        );
                      },
                      child: _buildClassCard(
                        docId,
                        data['className'] ?? 'Unnamed Class',
                        data['teacherName'] ?? 'Teacher',
                        data['classCode'] ?? 'N/A',
                        Colors.grey.shade400,
                        isArchived: true,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- UPDATED HEADER (Removed Name, Added Real Count) ---
  Widget _buildHeader(String classCount, String tasks) {
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

  /// Calculate number of pending assignments for this teacher:
  /// total assignments in their active classes minus those that have at least one submission.
  Future<int> _calculatePendingTasks(String teacherId, List<String> classIds) async {
    try {
      if (classIds.isEmpty) return 0;

      int totalAssignments = 0;
      int assignmentsWithSubmissions = 0;

      // Firestore whereIn limit is 10
      for (var i = 0; i < classIds.length; i += 10) {
        final batch = classIds.skip(i).take(10).toList();

        final assignmentsSnapshot = await FirebaseFirestore.instance
            .collection('assignments')
            .where('classId', whereIn: batch)
            .get();

        for (var assignment in assignmentsSnapshot.docs) {
          totalAssignments++;

          final submissionSnapshot = await FirebaseFirestore.instance
              .collection('assignment_submissions')
              .where('assignmentId', isEqualTo: assignment.id)
              .limit(1)
              .get();

          if (submissionSnapshot.docs.isNotEmpty) {
            assignmentsWithSubmissions++;
          }
        }
      }

      final pending = totalAssignments - assignmentsWithSubmissions;
      return pending < 0 ? 0 : pending;
    } catch (e) {
      print('Error calculating teacher pending tasks: $e');
      return 0;
    }
  }


  Widget _buildClassCard(String classId, String title, String teacher, String code, Color bgColor, {bool isArchived = false}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                child: Text(code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              if (isArchived)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.8), borderRadius: BorderRadius.circular(6)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.archive, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text('Archived', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              else
                const SizedBox(width: 20),
            ],
          ),
          const Spacer(),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(teacher, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
          )
        ],
      ),
    );
  }
}