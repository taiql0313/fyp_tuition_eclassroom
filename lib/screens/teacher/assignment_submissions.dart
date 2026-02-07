import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

class AssignmentSubmissionsPage extends StatelessWidget {
  final String assignmentId;
  final String classId;
  final String assignmentTitle;

  const AssignmentSubmissionsPage({
    super.key,
    required this.assignmentId,
    required this.classId,
    required this.assignmentTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submissions'),
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('classIds', arrayContains: classId)
            .where('role', isEqualTo: 'student')
            .snapshots(),
        builder: (context, studentsSnapshot) {
          if (studentsSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!studentsSnapshot.hasData || studentsSnapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('No students enrolled in this class'),
            );
          }

          final students = studentsSnapshot.data!.docs;

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('assignment_submissions')
                .where('assignmentId', isEqualTo: assignmentId)
                .snapshots(),
            builder: (context, submissionsSnapshot) {
              if (submissionsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final submissions = submissionsSnapshot.data?.docs ?? [];
              final submittedStudentIds = submissions
                  .map((doc) {
                    final data = doc.data() as Map<String, dynamic>?;
                    return data?['studentId'] as String?;
                  })
                  .whereType<String>()
                  .toSet();


              final List<Map<String, dynamic>> submittedStudents = [];
              final List<Map<String, dynamic>> notSubmittedStudents = [];

              for (var studentDoc in students) {
                final studentData = studentDoc.data() as Map<String, dynamic>;
                final studentId = studentDoc.id;
                final studentName = studentData['displayName'] ?? 'Unknown';

                if (submittedStudentIds.contains(studentId)) {
                  // Find submission data
                  final submissionDoc = submissions.firstWhere(
                    (doc) {
                      final data = doc.data() as Map<String, dynamic>?;
                      return data?['studentId'] == studentId;
                    },
                  );
                  final submissionData = submissionDoc.data() as Map<String, dynamic>? ?? {};
                  submittedStudents.add({
                    'id': studentId,
                    'name': studentName,
                    'submissionId': submissionDoc.id,
                    'submittedAt': submissionData['submittedAt'],
                    'fileAttachments': submissionData['fileAttachments'],
                  });
                } else {
                  notSubmittedStudents.add({
                    'id': studentId,
                    'name': studentName,
                  });
                }
              }

              // Sort submitted students by submission time (newest first)
              submittedStudents.sort((a, b) {
                final aTime = a['submittedAt'] as Timestamp?;
                final bTime = b['submittedAt'] as Timestamp?;
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            'Total',
                            students.length.toString(),
                            Colors.blue,
                          ),
                          _buildStatItem(
                            'Submitted',
                            submittedStudents.length.toString(),
                            Colors.green,
                          ),
                          _buildStatItem(
                            'Pending',
                            notSubmittedStudents.length.toString(),
                            Colors.orange,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submitted Section
                    if (submittedStudents.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Submitted (${submittedStudents.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...submittedStudents.map((student) => _buildSubmittedCard(context, student)),
                      const SizedBox(height: 24),
                    ],

                    // Not Submitted Section
                    if (notSubmittedStudents.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.pending, color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Not Submitted (${notSubmittedStudents.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...notSubmittedStudents.map((student) => _buildNotSubmittedCard(student)),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildSubmittedCard(BuildContext context, Map<String, dynamic> student) {
    final submittedAt = student['submittedAt'] as Timestamp?;
    String dateText = 'Unknown';
    if (submittedAt != null) {
      dateText = DateFormat('MMM d, y • h:mm a').format(submittedAt.toDate());
    }

    final fileAttachments = student['fileAttachments'] as List<dynamic>? ?? [];
    final fileCount = fileAttachments.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: Icon(Icons.check_circle, color: Colors.green),
        ),
        title: Text(
          student['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submitted: $dateText'),
            if (fileCount > 0)
              Text(
                '$fileCount ${fileCount == 1 ? 'file' : 'files'} attached',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => _showSubmissionFiles(context, student),
      ),
    );
  }

  Widget _buildNotSubmittedCard(Map<String, dynamic> student) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.shade100,
          child: Icon(Icons.pending, color: Colors.orange),
        ),
        title: Text(
          student['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Not submitted yet',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }

  void _showSubmissionFiles(BuildContext context, Map<String, dynamic> student) {
    final files = student['fileAttachments'] as List<dynamic>? ?? [];
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${student['name']}\'s Submission',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (files.isEmpty)
                const Text('No files uploaded.'),
              if (files.isNotEmpty)
                ...files.map((file) {
                  if (file is! Map<String, dynamic>) {
                    return const SizedBox.shrink();
                  }
                  final fileName = file['fileName'] as String? ?? 'File';
                  final fileSize = file['fileSize'] as int? ?? 0;
                  final String base64Data = file['base64Data'] as String? ?? '';
                  return ListTile(
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text(fileName, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_formatFileSize(fileSize)),
                    trailing: const Icon(Icons.download),
                    onTap: () async {
                      if (base64Data.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('File data missing')),
                        );
                        return;
                      }
                      await _downloadFileFromBase64(context, fileName, base64Data);
                    },
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadFileFromBase64(BuildContext context, String fileName, String base64Data) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final bytes = base64Decode(base64Data);
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      Navigator.of(context, rootNavigator: true).pop();

      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File saved to: $filePath')),
        );
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}
