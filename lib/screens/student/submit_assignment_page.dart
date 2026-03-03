import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/notification_service.dart';

class SubmitAssignmentPage extends StatefulWidget {
  final String assignmentId;
  final String classId;
  final String assignmentTitle;

  const SubmitAssignmentPage({
    super.key,
    required this.assignmentId,
    required this.classId,
    required this.assignmentTitle,
  });

  @override
  State<SubmitAssignmentPage> createState() => _SubmitAssignmentPageState();
}

class _SubmitAssignmentPageState extends State<SubmitAssignmentPage> {
  bool _isSubmitting = false;
  bool _isLoading = true;
  String? _submissionId;
  Timestamp? _submittedAt;
  List<Map<String, dynamic>> _existingFiles = [];
  List<File> _selectedFiles = [];
  final Map<String, String> _uploadProgress = {};
  final _notificationService = NotificationService();

  static const int _maxFileSize = 716 * 1024; // 700KB
  static const List<String> _supportedExtensions = [
    '.zip', '.rar', '.7z',
    '.pdf',
    '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp',
    '.txt', '.md',
    '.mp4', '.avi', '.mov',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingSubmission();
  }

  Future<void> _loadExistingSubmission() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('assignment_submissions')
          .where('assignmentId', isEqualTo: widget.assignmentId)
          .where('studentId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();
        _submissionId = doc.id;
        _submittedAt = data['submittedAt'] as Timestamp?;
        final files = data['fileAttachments'] as List<dynamic>? ?? [];
        _existingFiles = files
            .where((file) => file is Map<String, dynamic>)
            .map((file) => file as Map<String, dynamic>)
            .toList();
      }
    } catch (_) {
      // Ignore load errors for now
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmCancelSubmission() async {
    if (_submissionId == null) return;

    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel submission'),
          content: const Text(
            'Are you sure you want to cancel this submission? '
            'You will be able to submit again afterwards.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, cancel'),
            ),
          ],
        );
      },
    );

    if (shouldCancel == true) {
      await _cancelSubmission();
    }
  }

  Future<void> _cancelSubmission() async {
    if (_submissionId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('assignment_submissions')
          .doc(_submissionId)
          .delete();

      if (mounted) {
        setState(() {
          _submissionId = null;
          _submittedAt = null;
          _existingFiles = [];
          _selectedFiles = [];
          _uploadProgress.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Submission cancelled. You can submit again.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling submission: $e'),
          ),
        );
      }
    }
  }

  bool _isFileTypeSupported(String fileName) {
    final extension = fileName.toLowerCase();
    return _supportedExtensions.any((ext) => extension.endsWith(ext));
  }

  String _getMimeType(String fileName) {
    final extension = fileName.toLowerCase();
    if (extension.endsWith('.zip')) return 'application/zip';
    if (extension.endsWith('.rar')) return 'application/x-rar-compressed';
    if (extension.endsWith('.7z')) return 'application/x-7z-compressed';
    if (extension.endsWith('.pdf')) return 'application/pdf';
    if (extension.endsWith('.doc')) return 'application/msword';
    if (extension.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (extension.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (extension.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (extension.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (extension.endsWith('.pptx')) return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    if (extension.endsWith('.jpg') || extension.endsWith('.jpeg')) return 'image/jpeg';
    if (extension.endsWith('.png')) return 'image/png';
    if (extension.endsWith('.gif')) return 'image/gif';
    if (extension.endsWith('.bmp')) return 'image/bmp';
    if (extension.endsWith('.webp')) return 'image/webp';
    if (extension.endsWith('.txt')) return 'text/plain';
    if (extension.endsWith('.md')) return 'text/markdown';
    if (extension.endsWith('.mp4')) return 'video/mp4';
    if (extension.endsWith('.avi')) return 'video/x-msvideo';
    if (extension.endsWith('.mov')) return 'video/quicktime';
    return 'application/octet-stream';
  }

  Future<String> _fileToBase64(File file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.paths.isNotEmpty) {
        setState(() {
          final newFiles = result.paths
              .where((path) => path != null)
              .map((path) => File(path!))
              .toList();
          _selectedFiles.addAll(newFiles);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error selecting files: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeExistingFile(int index) {
    setState(() => _existingFiles.removeAt(index));
  }

  Future<void> _submitWork() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: You must be logged in to submit.")),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _uploadProgress.clear();
    });

    try {
      final List<Map<String, dynamic>> newFiles = [];

      for (var file in _selectedFiles) {
        final fileName = file.path.split('/').last;
        final fileSize = await file.length();

        if (fileSize > _maxFileSize) {
          final sizeInMB = (fileSize / 1024 / 1024).toStringAsFixed(2);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File "$fileName" is too large ($sizeInMB MB). Maximum size is 700KB.'),
              backgroundColor: Colors.orange,
            ),
          );
          continue;
        }

        if (!_isFileTypeSupported(fileName)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File type not supported: $fileName.'),
              backgroundColor: Colors.orange,
            ),
          );
          continue;
        }

        setState(() => _uploadProgress[fileName] = 'Encoding...');

        final base64Data = await _fileToBase64(file);
        final mimeType = _getMimeType(fileName);

        newFiles.add({
          'fileName': fileName,
          'fileType': mimeType,
          'fileSize': fileSize,
          'base64Data': base64Data,
          'uploadedAt': Timestamp.now(),
        });

        setState(() => _uploadProgress[fileName] = 'Done');
      }

      final allFiles = [..._existingFiles, ...newFiles];

      final submissionData = {
        'assignmentId': widget.assignmentId,
        'classId': widget.classId,
        'studentId': user.uid,
        'studentName': user.displayName ?? 'Student',
        'fileAttachments': allFiles,
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_submissionId != null) {
        await FirebaseFirestore.instance
            .collection('assignment_submissions')
            .doc(_submissionId)
            .update(submissionData);
      } else {
        await FirebaseFirestore.instance
            .collection('assignment_submissions')
            .add(submissionData);
      }

      // Send notification to teacher
      try {
        final classDoc = await FirebaseFirestore.instance
            .collection('classrooms')
            .doc(widget.classId)
            .get();
        final teacherId = classDoc.data()?['teacherId'] as String?;
        if (teacherId != null) {
          await _notificationService.createForUser(
            userId: teacherId,
            type: 'assignment',
            title: 'Assignment Submitted',
            message: '${user.displayName ?? 'A student'} submitted "${widget.assignmentTitle}"',
          );
        }
      } catch (e) {
        print('Error sending notification: $e');
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Submission saved successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Work'),
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.assignmentTitle,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (_submittedAt != null)
                          Text(
                            'Last submitted: ${DateFormat('MMM d, y • h:mm a').format(_submittedAt!.toDate())}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        const SizedBox(height: 16),
                        const Divider(),
                        if (_existingFiles.isNotEmpty) ...[
                          const Text('Previous Files', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ..._existingFiles.asMap().entries.map((entry) {
                            final index = entry.key;
                            final file = entry.value;
                            final fileName = file['fileName'] as String? ?? 'File';
                            return Chip(
                              label: Text(fileName, style: const TextStyle(fontSize: 12)),
                              onDeleted: () => _removeExistingFile(index),
                              deleteIcon: const Icon(Icons.close, size: 18),
                            );
                          }),
                          const SizedBox(height: 16),
                        ],
                        ListTile(
                          leading: const Icon(Icons.attach_file, color: Colors.blue),
                          title: const Text('Attach File'),
                          subtitle: Text(
                            _selectedFiles.isEmpty
                                ? 'No new files selected'
                                : '${_selectedFiles.length} new files selected',
                          ),
                          onTap: _pickFiles,
                        ),
                        Wrap(
                          spacing: 8.0,
                          children: _selectedFiles.map((file) {
                            final fileName = file.path.split('/').last;
                            final progress = _uploadProgress[fileName];
                            return Chip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (progress != null && progress != 'Done')
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  if (progress != null && progress != 'Done') const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      fileName,
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              onDeleted: () {
                                setState(() {
                                  _selectedFiles.remove(file);
                                  _uploadProgress.remove(fileName);
                                });
                              },
                            );
                          }).toList(),
                        ),
                        if (_selectedFiles.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'Note: Maximum file size is 700KB. Please compress large files.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ),
                        const SizedBox(height: 80), // space above bottom buttons
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submitWork,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Submit',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                        if (_submissionId != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _isSubmitting ? null : _confirmCancelSubmission,
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              label: const Text(
                                'Cancel submission',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
