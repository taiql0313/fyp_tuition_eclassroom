import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert'; // For Base64 decoding
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

class TeacherAssignmentDetailPage extends StatefulWidget {
  final Map<String, dynamic> assignmentData;
  final String assignmentId;

  const TeacherAssignmentDetailPage({
    super.key,
    required this.assignmentData,
    required this.assignmentId,
  });

  @override
  State<TeacherAssignmentDetailPage> createState() => _TeacherAssignmentDetailPageState();
}

class _TeacherAssignmentDetailPageState extends State<TeacherAssignmentDetailPage> {
  String? _userRole;
  bool _isLoadingRole = true;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Soft light blue background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Assignment Details", style: TextStyle(color: Colors.black)),
        actions: _isTeacher
            ? [
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.black),
                  onPressed: () {
                    // Menu for Edit or Delete (Teacher only)
                  },
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER CARD (Title & Points) ---
            _buildMainCard(),

            const SizedBox(height: 20),

            // --- INFO CARD (Dates & Teacher) ---
            _buildInfoCard(),

            const SizedBox(height: 20),

            // --- ATTACHMENTS SECTION ---
            _buildAttachmentsCard(),

            const SizedBox(height: 100), // Space for bottom buttons
          ],
        ),
      ),
      // --- BOTTOM ACTION BUTTONS ---
      bottomSheet: _buildBottomActions(context),
    );
  }

  Widget _buildMainCard() {
    // Get assignment data
    final title = widget.assignmentData['title'] ?? 'Untitled Assignment';
    final instructions = widget.assignmentData['instructions'] ?? 'No instructions provided.';
    final points = widget.assignmentData['points']?.toString() ?? '100';
    final classId = widget.assignmentData['classId'] ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Subject/Class badge - will fetch class name if needed
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('classrooms').doc(classId).get(),
                builder: (context, snapshot) {
                  String subjectName = 'Class';
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final classData = snapshot.data!.data() as Map<String, dynamic>;
                    subjectName = classData['className'] ?? classData['subject'] ?? 'Class';
                  }
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      subjectName,
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "$points points",
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            instructions,
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    // Format due date
    String dueDateText = "No due date";
    if (widget.assignmentData['dueDate'] != null && widget.assignmentData['dueDate'] is Timestamp) {
      final dueDate = (widget.assignmentData['dueDate'] as Timestamp).toDate();
      dueDateText = DateFormat('EEE, MMM d, y').format(dueDate);
    }

    // Format created date
    String createdDateText = "Unknown";
    if (widget.assignmentData['createdAt'] != null && widget.assignmentData['createdAt'] is Timestamp) {
      final createdDate = (widget.assignmentData['createdAt'] as Timestamp).toDate();
      createdDateText = DateFormat('MMM d, y').format(createdDate);
    }

    // Get classId from assignment
    final classId = widget.assignmentData['classId'] ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            Icons.calendar_today,
            "Due Date",
            dueDateText,
            Colors.red.shade100,
            Colors.red,
          ),
          const Divider(height: 30),
          // Fetch teacher name from classroom / 从课堂获取教师姓名
          FutureBuilder<DocumentSnapshot>(
            future: classId.isNotEmpty
                ? FirebaseFirestore.instance.collection('classrooms').doc(classId).get()
                : Future.value(null),
            builder: (context, snapshot) {
              String teacherName = 'Teacher';
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasData &&
                  snapshot.data != null &&
                  snapshot.data!.exists) {
                final classData = snapshot.data!.data() as Map<String, dynamic>?;
                teacherName = classData?['teacherName'] ?? 'Teacher';
              }
              return _buildInfoRow(
                Icons.person_outline,
                "Teacher",
                teacherName,
                Colors.blue.shade100,
                Colors.blue,
              );
            },
          ),
          const Divider(height: 30),
          _buildInfoRow(
            Icons.access_time,
            "Assigned",
            createdDateText,
            Colors.green.shade100,
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color bg, Color iconCol) {
    return Row(
      children: [
        CircleAvatar(backgroundColor: bg, child: Icon(icon, color: iconCol, size: 20)),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        )
      ],
    );
  }

  Widget _buildAttachmentsCard() {
    // Get file attachments
    final fileAttachments = widget.assignmentData['fileAttachments'] as List<dynamic>? ?? [];
    final fileCount = fileAttachments.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Attachments", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(
                fileCount == 0 ? "No files" : "$fileCount ${fileCount == 1 ? 'file' : 'files'}",
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (fileCount == 0)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  "No attachments",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ),
            )
          else
            ...fileAttachments.asMap().entries.map((entry) {
              final index = entry.key;
              final fileData = entry.value;
              
              // Check if it's new format (Map with Base64) or old format (URL string)
              if (fileData is Map<String, dynamic>) {
                // New format: Base64 stored in Firestore
                final fileName = fileData['fileName'] as String? ?? 'Attachment';
                final fileSize = fileData['fileSize'] as int? ?? 0;
                final base64Data = fileData['base64Data'] as String? ?? '';
                return Padding(
                  padding: EdgeInsets.only(bottom: index < fileCount - 1 ? 12 : 0),
                  child: _buildFileItemNewFormat(fileName, fileSize, base64Data),
                );
              } else {
                // Old format: URL string (for backward compatibility)
                final fileUrl = fileData.toString();
                final fileName = _extractFileNameFromUrl(fileUrl);
                return Padding(
                  padding: EdgeInsets.only(bottom: index < fileCount - 1 ? 12 : 0),
                  child: _buildFileItem(fileName, fileUrl),
                );
              }
            }),
        ],
      ),
    );
  }

  String _extractFileNameFromUrl(String url) {
    try {
      // Extract filename from Firebase Storage URL
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final fileName = pathSegments.last;
        // Remove timestamp prefix if exists
        final parts = fileName.split('_');
        if (parts.length > 1) {
          return parts.sublist(1).join('_');
        }
        return fileName;
      }
      return 'Attachment';
    } catch (e) {
      return 'Attachment';
    }
  }

  // Download file from Base64 data
  Future<void> _downloadFileFromBase64(String fileName, String base64Data) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Decode Base64
      final bytes = base64Decode(base64Data);

      // Get download directory
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      // Write file
      await file.writeAsBytes(bytes);

      // Close loading indicator
      if (mounted) {
        Navigator.pop(context);
      }

      // Open file
      final result = await OpenFile.open(filePath);

      if (mounted) {
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File saved to: $filePath'),
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File downloaded and opened successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Format file size
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  // Build file item for new format (Base64)
  Widget _buildFileItemNewFormat(String fileName, int fileSize, String base64Data) {
    // Determine file icon based on extension
    IconData fileIcon = Icons.insert_drive_file;
    Color iconColor = Colors.grey;
    
    final lowerFileName = fileName.toLowerCase();
    if (lowerFileName.endsWith('.pdf')) {
      fileIcon = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (lowerFileName.endsWith('.doc') || lowerFileName.endsWith('.docx')) {
      fileIcon = Icons.description;
      iconColor = Colors.blue;
    } else if (lowerFileName.endsWith('.jpg') || lowerFileName.endsWith('.jpeg') || 
               lowerFileName.endsWith('.png') || lowerFileName.endsWith('.gif')) {
      fileIcon = Icons.image;
      iconColor = Colors.purple;
    } else if (lowerFileName.endsWith('.zip') || lowerFileName.endsWith('.rar') || 
               lowerFileName.endsWith('.7z')) {
      fileIcon = Icons.folder_zip;
      iconColor = Colors.orange;
    }

    return Builder(
      builder: (context) => InkWell(
        onTap: () async {
          if (_isTeacher) {
            // Teacher: Show file info
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('File Information'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Name: $fileName'),
                    const SizedBox(height: 8),
                    Text('Size: ${_formatFileSize(fileSize)}'),
                    const SizedBox(height: 8),
                    Text('Format: Base64 (Firestore)'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          } else {
            // Student: Download file
            await _downloadFileFromBase64(fileName, base64Data);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: iconColor.withOpacity(0.1),
                child: Icon(fileIcon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatFileSize(fileSize),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _isTeacher ? Icons.info_outline : Icons.download,
                color: Colors.grey.shade600,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileItem(String fileName, String fileUrl) {
    // Determine file icon based on extension
    IconData fileIcon = Icons.insert_drive_file;
    Color iconColor = Colors.grey;
    
    final lowerFileName = fileName.toLowerCase();
    if (lowerFileName.endsWith('.pdf')) {
      fileIcon = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (lowerFileName.endsWith('.doc') || lowerFileName.endsWith('.docx')) {
      fileIcon = Icons.description;
      iconColor = Colors.blue;
    } else if (lowerFileName.endsWith('.jpg') || lowerFileName.endsWith('.jpeg') || 
               lowerFileName.endsWith('.png') || lowerFileName.endsWith('.gif')) {
      fileIcon = Icons.image;
      iconColor = Colors.purple;
    } else if (lowerFileName.endsWith('.zip') || lowerFileName.endsWith('.rar')) {
      fileIcon = Icons.folder_zip;
      iconColor = Colors.orange;
    }

    return Builder(
      builder: (context) => InkWell(
        onTap: () async {
          // For students: Download file / 学生：下载文件
          // For teachers: Copy URL / 教师：复制URL
          if (_isTeacher) {
            await Clipboard.setData(ClipboardData(text: fileUrl));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("File URL copied to clipboard"),
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            // Download file functionality
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Please use the new file format for downloads"),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(fileIcon, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fileName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Builder(
                builder: (ctx) => IconButton(
                  icon: Icon(
                    _isTeacher ? Icons.copy : Icons.download,
                    color: Colors.grey,
                  ),
                  onPressed: () async {
                    if (_isTeacher) {
                      await Clipboard.setData(ClipboardData(text: fileUrl));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text("File URL copied to clipboard"),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } else {
                      // TODO: Download file / 待实现：下载文件
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text("Download functionality coming soon"),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  tooltip: _isTeacher ? "Copy URL" : "Download",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    // Different actions for teachers vs students / 教师和学生不同的操作
    if (_isTeacher) {
      // Teacher actions: View Submissions & Edit / 教师操作：查看提交和编辑
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: Navigate to submissions page / 待实现：导航到提交页面
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Submissions view coming soon")),
                  );
                },
                icon: const Icon(Icons.people),
                label: const Text("Submissions"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO: Navigate to edit assignment page / 待实现：导航到编辑作业页面
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Edit functionality coming soon")),
                  );
                },
                icon: const Icon(Icons.edit),
                label: const Text("Edit Task"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Student actions: Submit Work / 学生操作：提交作业
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO: Navigate to submit assignment page / 待实现：导航到提交作业页面
                  // This will allow students to upload their completed homework
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Submit assignment functionality coming soon")),
                  );
                },
                icon: const Icon(Icons.upload_file),
                label: const Text("Submit Work"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}