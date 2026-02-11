import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../routes.dart';
import 'create_announcement_page.dart';
import 'create_quiz.dart';

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
  String? _userRole;
  bool _isLoadingRole = true;
  final TextEditingController _memberSearchController = TextEditingController();
  bool _isMemberSearchVisible = false;

  @override
  void dispose() {
    _memberSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          setState(() {
            _userRole = userData?['role'] ?? 'student';
            _isLoadingRole = false;
          });
        } else {
          setState(() {
            _userRole = 'student';
            _isLoadingRole = false;
          });
        }
      } catch (e) {
        setState(() {
          _userRole = 'student';
          _isLoadingRole = false;
        });
      }
    } else {
      setState(() {
        _userRole = 'student';
        _isLoadingRole = false;
      });
    }
  }

  bool get _isTeacher => _userRole == 'teacher';

  // Delete classroom and unenroll all students
  Future<void> _deleteClassroom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Classroom'),
        content: const Text(
          'Are you sure you want to delete this classroom?\n\n'
          'This will:\n'
          '• Unenroll all students\n'
          '• Delete all assignments and submissions\n'
          '• Delete all announcements\n'
          '• Delete all quizzes\n'
          '• Delete the timetable\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final classId = widget.classId;
      print('DEBUG deleteClassroom: Starting deletion for classId=$classId');
      
      // 1. Unenroll all students - remove classId from their classIds array
      print('DEBUG deleteClassroom: Step 1 - Unenrolling students...');
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('classIds', arrayContains: classId)
          .get();

      print('DEBUG deleteClassroom: Found ${studentsSnapshot.docs.length} students to unenroll');
      
      if (studentsSnapshot.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (var studentDoc in studentsSnapshot.docs) {
          batch.update(studentDoc.reference, {
            'classIds': FieldValue.arrayRemove([classId]),
          });
        }
        await batch.commit();
        print('DEBUG deleteClassroom: Students unenrolled successfully');
      }

      // 2. Delete all assignments for this class
      print('DEBUG deleteClassroom: Step 2 - Deleting assignments...');
      final assignmentsSnapshot = await FirebaseFirestore.instance
          .collection('assignments')
          .where('classId', isEqualTo: classId)
          .get();

      print('DEBUG deleteClassroom: Found ${assignmentsSnapshot.docs.length} assignments');
      
      for (var doc in assignmentsSnapshot.docs) {
        // Delete submissions for each assignment
        final submissionsSnapshot = await FirebaseFirestore.instance
            .collection('assignment_submissions')
            .where('assignmentId', isEqualTo: doc.id)
            .get();
        
        print('DEBUG deleteClassroom: Found ${submissionsSnapshot.docs.length} submissions for assignment ${doc.id}');
        
        for (var subDoc in submissionsSnapshot.docs) {
          await subDoc.reference.delete();
        }
        
        await doc.reference.delete();
        print('DEBUG deleteClassroom: Deleted assignment ${doc.id}');
      }

      // 3. Delete all announcements for this class
      print('DEBUG deleteClassroom: Step 3 - Deleting announcements...');
      final announcementsSnapshot = await FirebaseFirestore.instance
          .collection('announcements')
          .where('classId', isEqualTo: classId)
          .get();

      print('DEBUG deleteClassroom: Found ${announcementsSnapshot.docs.length} announcements');
      
      for (var doc in announcementsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 4. Delete all quizzes for this class
      print('DEBUG deleteClassroom: Step 4 - Deleting quizzes...');
      final quizzesSnapshot = await FirebaseFirestore.instance
          .collection('quizzes')
          .where('classId', isEqualTo: classId)
          .get();

      print('DEBUG deleteClassroom: Found ${quizzesSnapshot.docs.length} quizzes with classId=$classId');
      
      for (var doc in quizzesSnapshot.docs) {
        print('DEBUG deleteClassroom: Deleting quiz ${doc.id}');
        await doc.reference.delete();
      }
      
      // Also try subjectId in case some quizzes use that field
      final quizzesBySubjectId = await FirebaseFirestore.instance
          .collection('quizzes')
          .where('subjectId', isEqualTo: classId)
          .get();

      print('DEBUG deleteClassroom: Found ${quizzesBySubjectId.docs.length} quizzes with subjectId=$classId');
      
      for (var doc in quizzesBySubjectId.docs) {
        print('DEBUG deleteClassroom: Deleting quiz ${doc.id}');
        await doc.reference.delete();
      }

      // 5. Delete timetable for this class
      print('DEBUG deleteClassroom: Step 5 - Deleting timetables...');
      final timetableSnapshot = await FirebaseFirestore.instance
          .collection('timetables')
          .where('classId', isEqualTo: classId)
          .get();

      print('DEBUG deleteClassroom: Found ${timetableSnapshot.docs.length} timetables');
      
      for (var doc in timetableSnapshot.docs) {
        await doc.reference.delete();
      }

      // 6. Finally, delete the classroom document
      print('DEBUG deleteClassroom: Step 6 - Deleting classroom document...');
      await FirebaseFirestore.instance
          .collection('classrooms')
          .doc(classId)
          .delete();
      
      print('DEBUG deleteClassroom: SUCCESS - Classroom deleted!');

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading
        Navigator.of(context).pop(); // Go back to dashboard
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Classroom deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      print('DEBUG deleteClassroom: ERROR - $e');
      print('DEBUG deleteClassroom: Stack trace - $stackTrace');
      
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting classroom: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          // Shows the specific Subject Name automatically
          title: Text(
            widget.classData['className'] ?? 'Classroom',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          actions: [
            if (_isTeacher)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.black),
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteClassroom();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete Classroom', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
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
        // Only show + button for teachers / 只为教师显示 + 按钮
        floatingActionButton: _isTeacher
            ? FloatingActionButton(
                onPressed: () => _showPostOptions(context),
                backgroundColor: Colors.blue,
                child: const Icon(Icons.add, color: Colors.white),
              )
            : null,
      ),
    );
  }

  // --- TAB 1: STREAM (Filtered for THIS specific class) ---
  Widget _buildStreamTab() {
    // Query announcements for this class - try createdAt first, fallback to timestamp
    return StreamBuilder<QuerySnapshot>(
      // Only get announcements for THIS classId
      stream: FirebaseFirestore.instance
          .collection('announcements')
          .where('classId', isEqualTo: widget.classId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState("No announcements yet.", Icons.announcement_outlined);
        }

        // Sort documents by date (newest first)
        final sortedDocs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            
            Timestamp? aTime;
            Timestamp? bTime;
            
            // Try to get timestamp from multiple fields
            if (aData['createdAt'] is Timestamp) {
              aTime = aData['createdAt'] as Timestamp;
            } else if (aData['timestamp'] is Timestamp) {
              aTime = aData['timestamp'] as Timestamp;
            } else if (aData['date'] is Timestamp) {
              aTime = aData['date'] as Timestamp;
            }
            
            if (bData['createdAt'] is Timestamp) {
              bTime = bData['createdAt'] as Timestamp;
            } else if (bData['timestamp'] is Timestamp) {
              bTime = bData['timestamp'] as Timestamp;
            } else if (bData['date'] is Timestamp) {
              bTime = bData['date'] as Timestamp;
            }
            
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            
            return bTime.compareTo(aTime); // Descending order
          });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            var post = sortedDocs[index].data() as Map<String, dynamic>;

            // Format date - try multiple field names for backward compatibility
            String displayDate = "";
            Timestamp? dateValue;
            
            // Try 'createdAt' first, then 'timestamp', then 'date'
            if (post['createdAt'] is Timestamp) {
              dateValue = post['createdAt'] as Timestamp;
            } else if (post['timestamp'] is Timestamp) {
              dateValue = post['timestamp'] as Timestamp;
            } else if (post['date'] is Timestamp) {
              dateValue = post['date'] as Timestamp;
            }

            if (dateValue != null) {
              displayDate = DateFormat('MMM d, h:mm a').format(dateValue.toDate());
            } else {
              displayDate = "Just now";
            }

            // Get announcement type for styling
            final type = post['type'] ?? 'class';
            Color typeColor;
            IconData typeIcon;
            
            switch (type) {
              case 'exam':
                typeColor = Colors.red;
                typeIcon = Icons.assignment_outlined;
                break;
              case 'event':
                typeColor = Colors.purple;
                typeIcon = Icons.event_outlined;
                break;
              default:
                typeColor = Colors.blue;
                typeIcon = Icons.info_outline;
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: typeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(typeIcon, color: typeColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post['title'] ?? 'No Title',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                post['teacherName'] ?? post['author'] ?? 'Teacher',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          displayDate,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    if (post['content'] != null && post['content'].toString().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        post['content'] ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
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
    // Stream both assignments and quizzes for this class
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('assignments')
          .where('classId', isEqualTo: widget.classId)
          .snapshots(),
      builder: (context, assignmentsSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('quizzes')
              .where('classId', isEqualTo: widget.classId)
              .snapshots(),
          builder: (context, quizzesSnapshot) {
            if (assignmentsSnapshot.connectionState == ConnectionState.waiting ||
                quizzesSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Combine assignments and quizzes
            final List<Map<String, dynamic>> allItems = [];
            
            // Add assignments
            if (assignmentsSnapshot.hasData) {
              for (var doc in assignmentsSnapshot.data!.docs) {
                allItems.add({
                  'type': 'assignment',
                  'id': doc.id,
                  'data': doc.data() as Map<String, dynamic>,
                });
              }
            }
            
            // Add quizzes
            if (quizzesSnapshot.hasData) {
              for (var doc in quizzesSnapshot.data!.docs) {
                allItems.add({
                  'type': 'quiz',
                  'id': doc.id,
                  'data': doc.data() as Map<String, dynamic>,
                });
              }
            }

            // Sort by createdAt (newest first)
            allItems.sort((a, b) {
              final aData = a['data'] as Map<String, dynamic>;
              final bData = b['data'] as Map<String, dynamic>;
              
              Timestamp? aTime = aData['createdAt'] as Timestamp?;
              Timestamp? bTime = bData['createdAt'] as Timestamp?;
              
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              
              return bTime.compareTo(aTime); // Descending order
            });

            if (allItems.isEmpty) {
              return _buildEmptyState("No assignments or quizzes posted.", Icons.assignment_outlined);
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                final item = allItems[index];
                final type = item['type'] as String;
                final itemId = item['id'] as String;
                final itemData = item['data'] as Map<String, dynamic>;

                if (type == 'assignment') {
                  // Formatting the date for display
                  String formattedDate = "No Date";
                  if (itemData['dueDate'] != null && itemData['dueDate'] is Timestamp) {
                    formattedDate = DateFormat('MMM d, y').format((itemData['dueDate'] as Timestamp).toDate());
                  }

                  return InkWell(
                    onTap: () {
                      // NAVIGATE TO ASSIGNMENT DETAIL
                      Navigator.pushNamed(
                        context,
                        Routes.assignmentDetail,
                        arguments: {
                          'assignmentData': itemData,
                          'assignmentId': itemId,
                        },
                      );
                    },
                    child: _buildAssignmentCard(
                      itemData['title'] ?? 'Untitled',
                      formattedDate,
                      itemData['points']?.toString() ?? '100',
                      itemData['status'] ?? 'Assigned',
                    ),
                  );
                } else {
                  // Quiz card
                  String formattedDate = "No Date";
                  if (itemData['createdAt'] != null && itemData['createdAt'] is Timestamp) {
                    formattedDate = DateFormat('MMM d, y').format((itemData['createdAt'] as Timestamp).toDate());
                  }

                  final questions = itemData['questions'] as List<dynamic>? ?? [];
                  final questionCount = questions.length;

                  return InkWell(
                    onTap: () {
                      // Navigate to quiz answer page for students, or quiz management for teachers
                      if (_isTeacher) {
                        Navigator.pushNamed(
                          context,
                          Routes.teacherQuizManagement,
                          arguments: {
                            'quizId': itemId,
                            'quizData': itemData,
                            'classId': widget.classId,
                          },
                        );
                      } else {
                        // Navigate to answer quiz page for students
                        Navigator.pushNamed(
                          context,
                          Routes.studentAnswerQuiz,
                          arguments: {
                            'quizId': itemId,
                            'quizData': itemData,
                          },
                        );
                      }
                    },
                    child: _buildQuizCard(
                      itemData['title'] ?? 'Untitled Quiz',
                      formattedDate,
                      questionCount.toString(),
                    ),
                  );
                }
              },
            );
          },
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
          Row(
            children: [
              const Icon(Icons.assignment_outlined, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ),
            ],
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

  Widget _buildQuizCard(String title, String createdDate, String questionCount) {
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
          // Header Row: Subject Name & Quiz Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const CircleAvatar(radius: 4, backgroundColor: Colors.purple), // Subject dot
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
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Quiz',
                  style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Quiz Title
          Row(
            children: [
              const Icon(Icons.quiz_outlined, size: 20, color: Colors.purple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Footer Row: Created Date and Question Count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text("Created: $createdDate", style: const TextStyle(color: Colors.grey)),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.help_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text("$questionCount questions", style: const TextStyle(color: Colors.grey)),
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
    return StreamBuilder<DocumentSnapshot>(
      // First, get the classroom to find the teacher
      stream: FirebaseFirestore.instance.collection('classrooms').doc(widget.classId).snapshots(),
      builder: (context, classroomSnapshot) {
        if (classroomSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!classroomSnapshot.hasData || !classroomSnapshot.data!.exists) {
          return _buildEmptyState("Classroom not found", Icons.error_outline);
        }

        final classroomData = classroomSnapshot.data!.data() as Map<String, dynamic>;
        final teacherId = classroomData['teacherId'] as String? ?? '';
        final teacherName = classroomData['teacherName'] as String? ?? 'Teacher';

        // Now get all users enrolled in this class
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('classIds', arrayContains: widget.classId)
              .snapshots(),
          builder: (context, usersSnapshot) {
            if (usersSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final users = usersSnapshot.data?.docs ?? [];
            
            // Separate teacher and students
            List<Map<String, dynamic>> teacherList = [];
            List<Map<String, dynamic>> studentList = [];

            // Find teacher from users collection to get email
            String teacherEmail = '';
            for (var userDoc in users) {
              final userId = userDoc.id;
              if (userId == teacherId) {
                final userData = userDoc.data() as Map<String, dynamic>;
                teacherEmail = userData['email'] ?? '';
                break;
              }
            }

            // If teacher not found in enrolled users, fetch from users collection
            if (teacherEmail.isEmpty && teacherId.isNotEmpty) {
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(teacherId).get(),
                builder: (context, teacherSnapshot) {
                  if (teacherSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  String finalTeacherEmail = '';
                  if (teacherSnapshot.hasData && teacherSnapshot.data!.exists) {
                    final teacherData = teacherSnapshot.data!.data() as Map<String, dynamic>?;
                    finalTeacherEmail = teacherData?['email'] ?? '';
                  }

                  // Add teacher first
                  teacherList.add({
                    'uid': teacherId,
                    'displayName': teacherName,
                    'email': finalTeacherEmail.isNotEmpty ? finalTeacherEmail : 'teacher@example.com',
                    'role': 'teacher',
                  });

                  // Add students
                  for (var userDoc in users) {
                    final userData = userDoc.data() as Map<String, dynamic>;
                    final userId = userDoc.id;
                    final role = userData['role'] as String? ?? 'student';

                    // Skip if this is the teacher (already added)
                    if (userId == teacherId) continue;

                    // Only add students
                    if (role == 'student') {
                      studentList.add({
                        'uid': userId,
                        'displayName': userData['displayName'] ?? 'Student',
                        'email': userData['email'] ?? '',
                        'role': 'student',
                      });
                    }
                  }


                  return _buildMembersList(teacherList, studentList);
                },
              );
            }

            // Add teacher first
            teacherList.add({
              'uid': teacherId,
              'displayName': teacherName,
              'email': teacherEmail.isNotEmpty ? teacherEmail : 'teacher@example.com',
              'role': 'teacher',
            });

            // Add students
            for (var userDoc in users) {
              final userData = userDoc.data() as Map<String, dynamic>;
              final userId = userDoc.id;
              final role = userData['role'] as String? ?? 'student';

              // Skip if this is the teacher (already added)
              if (userId == teacherId) continue;

              // Only add students
              if (role == 'student') {
                studentList.add({
                  'uid': userId,
                  'displayName': userData['displayName'] ?? 'Student',
                  'email': userData['email'] ?? '',
                  'role': 'student',
                });
              }
            }

            // Add hardcoded student "Bryant" for testing
            studentList.add({
              'uid': 'hardcoded_bryant',
              'displayName': 'Bryant',
              'email': 'bryant@student.edu',
              'role': 'student',
            });

            return _buildMembersList(teacherList, studentList);

          },
        );
      },
    );
  }

  Widget _buildMembersList(List<Map<String, dynamic>> teacherList, List<Map<String, dynamic>> studentList) {
    final query = _memberSearchController.text.trim().toLowerCase();
    final allMembers = [...teacherList, ...studentList];
    final filteredMembers = query.isEmpty
        ? allMembers
        : allMembers.where((member) {
            final name = (member['displayName'] ?? '').toString().toLowerCase();
            final email = (member['email'] ?? '').toString().toLowerCase();
            return name.contains(query) || email.contains(query);
          }).toList();

    if (allMembers.isEmpty) {
      return _buildEmptyState("No members found", Icons.people_outline);
    }

    return Column(
      children: [
        // Header with search (optional)
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "Class Members (${filteredMembers.length}/${allMembers.length})",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: Icon(_isMemberSearchVisible ? Icons.close : Icons.search),
                onPressed: () {
                  setState(() {
                    _isMemberSearchVisible = !_isMemberSearchVisible;
                    if (!_isMemberSearchVisible) {
                      _memberSearchController.clear();
                    }
                  });
                },
              ),
            ],
          ),
        ),
        if (_isMemberSearchVisible || query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _memberSearchController,
              decoration: InputDecoration(
                hintText: 'Search members by name or email...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _memberSearchController.clear();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        // Members List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filteredMembers.length,
            itemBuilder: (context, index) {
              final member = filteredMembers[index];
              final isTeacher = member['role'] == 'teacher';
              
              return _buildMemberCard(
                member['displayName'] ?? 'Unknown',
                member['email'] ?? '',
                isTeacher,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMemberCard(String name, String email, bool isTeacher) {
    // Generate avatar color based on name
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.orange,
      Colors.red,
      Colors.teal,
      Colors.pink,
    ];
    final colorIndex = name.hashCode.abs() % colors.length;
    final avatarColor = colors[colorIndex];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar with initial
          Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: avatarColor,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Status dot (optional - can be removed if not needed)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Name and Email
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          // Role Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isTeacher ? Colors.blue.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isTeacher ? 'Teacher' : 'Student',
              style: TextStyle(
                color: isTeacher ? Colors.blue : Colors.green,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
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
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, Routes.createAssignment, arguments: widget.classId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.announcement, color: Colors.green),
            title: const Text('New Announcement'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateAnnouncementPage(classId: widget.classId),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.quiz, color: Colors.purple),
            title: const Text('New Quiz'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateQuizPage(classId: widget.classId),
                ),
              );
            },
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