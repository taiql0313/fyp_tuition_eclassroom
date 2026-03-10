import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/attendance_service.dart';
import 'teacher_quiz_student_detail_page.dart';

/// Teacher view: All students' quiz performance (submitted + unsubmitted)
///
class TeacherQuizManagementPage extends StatefulWidget {
  final String quizId;
  final Map<String, dynamic> quizData;
  final String classId;

  const TeacherQuizManagementPage({
    super.key,
    required this.quizId,
    required this.quizData,
    required this.classId,
  });

  @override
  State<TeacherQuizManagementPage> createState() => _TeacherQuizManagementPageState();
}

class _TeacherQuizManagementPageState extends State<TeacherQuizManagementPage> {
  final AttendanceService _attendanceService = AttendanceService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _allStudents = [];
  bool _isSearchVisible = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _allStudents;
    return _allStudents.where((s) {
      final name = (s['displayName'] ?? '').toString().toLowerCase();
      final email = (s['email'] ?? '').toString().toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final quizTitle = widget.quizData['title'] ?? 'Untitled Quiz';
    final questions = widget.quizData['questions'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: _isSearchVisible
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search by name or email...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  ),
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text(quizTitle, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1458A3),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_isSearchVisible ? Icons.close : Icons.search, color: Colors.white),
            onPressed: () {
              setState(() {
                _isSearchVisible = !_isSearchVisible;
                if (!_isSearchVisible) {
                  _searchController.clear();
                } else {
                  _searchFocusNode.requestFocus();
                }
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadStudentsWithSubmissions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ],
                ),
              ),
            );
          }

          _allStudents = snapshot.data ?? [];
          final students = _filteredStudents;
          if (students.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _searchController.text.trim().isEmpty ? Icons.people_outline : Icons.search_off,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchController.text.trim().isEmpty
                        ? 'No students in this class'
                        : 'No students match "${_searchController.text.trim()}"',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Quiz info card
              _buildQuizInfoCard(quizTitle, questions.length),
              const SizedBox(height: 20),

              // List header
              Row(
                children: [
                  const Text(
                    'Student Performance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Sorted by score (high → low)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Student list
              ...students.map((s) => _buildStudentCard(s)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuizInfoCard(String title, int questionCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.quiz, color: Colors.purple, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$questionCount questions',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> studentData) {
    final name = studentData['displayName'] ?? 'Student';
    final uid = studentData['uid'] ?? '';
    final email = studentData['email'] ?? '';
    final submission = studentData['submission'] as Map<String, dynamic>?;
    final isSubmitted = submission != null;

    int totalScore = 0;
    int maxScore = 0;
    String statusText = 'Not Submitted';
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.pending_actions;

    if (isSubmitted) {
      totalScore = (submission['totalScore'] as num?)?.toInt() ?? 0;
      maxScore = (submission['maxTotalScore'] as num?)?.toInt() ?? 0;
      final status = submission['status'] as String? ?? 'graded';
      if (status == 'pending_grading') {
        statusText = 'Pending Grading';
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
      } else {
        statusText = 'Graded';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TeacherQuizStudentDetailPage(
                quizId: widget.quizId,
                quizData: widget.quizData,
                classId: widget.classId,
                studentId: uid,
                studentName: name,
                studentEmail: email,
                submission: submission,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor: const Color(0xFF1458A3).withOpacity(0.2),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Color(0xFF1458A3),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Name & email
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Score
              if (isSubmitted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1458A3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$totalScore/$maxScore',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1458A3),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '—',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadStudentsWithSubmissions() async {
    // 1. Get all students in class
    final students = await _attendanceService.getClassStudents(widget.classId);

    // 2. Get all submissions for this quiz
    final submissionsSnapshot = await FirebaseFirestore.instance
        .collection('quiz_submissions')
        .where('quizId', isEqualTo: widget.quizId)
        .get();

    final submissionMap = <String, Map<String, dynamic>>{};
    for (var doc in submissionsSnapshot.docs) {
      final data = doc.data();
      final sid = data['studentId'] as String?;
      if (sid != null) {
        submissionMap[sid] = {...data, 'submissionId': doc.id};
      }
    }

    // 3. Merge and sort: submitted by score (high→low), then unsubmitted
    final List<Map<String, dynamic>> result = [];
    for (var s in students) {
      final uid = s['uid'] as String? ?? '';
      final sub = submissionMap[uid];
      result.add({
        ...s,
        'submission': sub,
        'totalScore': (sub != null) ? ((sub['totalScore'] as num?)?.toInt() ?? 0) : -1,
      });
    }

    result.sort((a, b) {
      final aScore = a['totalScore'] as int;
      final bScore = b['totalScore'] as int;
      if (aScore < 0 && bScore < 0) return 0;
      if (aScore < 0) return 1;  // unsubmitted at end
      if (bScore < 0) return -1;
      return bScore.compareTo(aScore);  // high to low
    });

    return result;
  }
}
