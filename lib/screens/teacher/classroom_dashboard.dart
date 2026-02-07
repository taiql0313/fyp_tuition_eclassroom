import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../routes.dart';

class ClassroomDashboard extends StatelessWidget {
  const ClassroomDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Classrooms', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- DYNAMIC HEADER ---
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('classrooms')
                  .where('teacherId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                int classCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

                // For now, we set tasks and attendance to 0 or real queries if you have the collections
                return _buildHeader(classCount.toString(), "0", "0%");
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
                    return const Center(child: Text("No classrooms found."));
                  }

                  final classDocs = snapshot.data!.docs;
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
                          // NAVIGATE WITH ARGUMENTS
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
                          data['className'] ?? 'Unnamed Class',
                          data['teacherName'] ?? 'Teacher',
                          data['classCode'] ?? 'N/A',
                          "0", "0", Colors.blue.shade300,
                        ),
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
        onPressed: () => Navigator.pushNamed(context, Routes.createSubject),
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // --- UPDATED HEADER (Removed Name, Added Real Count) ---
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


  Widget _buildClassCard(String title, String teacher, String code, String students, String tasks, Color bgColor) {
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
              const Icon(Icons.bookmark, color: Colors.white38),
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
              Text(students, style: const TextStyle(color: Colors.white, fontSize: 12)),
              const Spacer(),
              const Icon(Icons.assignment_outlined, color: Colors.white70, size: 16),
              const SizedBox(width: 4),
              Text(tasks, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          )
        ],
      ),
    );
  }
}