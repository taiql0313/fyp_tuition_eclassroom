import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:convert';

class EditAssignmentPage extends StatefulWidget {
  final String assignmentId;
  final Map<String, dynamic> assignmentData;

  const EditAssignmentPage({
    super.key,
    required this.assignmentId,
    required this.assignmentData,
  });

  @override
  State<EditAssignmentPage> createState() => _EditAssignmentPageState();
}

class _EditAssignmentPageState extends State<EditAssignmentPage> {
  List<File> _selectedFiles = [];
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _pointsController = TextEditingController();

  DateTime? _selectedDate;
  bool _isLoading = false;
  Map<String, String> _uploadProgress = {};
  List<Map<String, dynamic>> _existingFiles = [];

  // Supported file types
  static const List<String> _supportedExtensions = [
    '.zip', '.rar', '.7z',
    '.pdf',
    '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp',
    '.txt', '.md',
    '.mp4', '.avi', '.mov',
  ];

  static const int _maxFileSize = 716 * 1024; // 700KB

  @override
  void initState() {
    super.initState();
    _loadAssignmentData();
  }

  void _loadAssignmentData() {
    _titleController.text = widget.assignmentData['title'] ?? '';
    _instructionsController.text = widget.assignmentData['instructions'] ?? '';
    _pointsController.text = widget.assignmentData['points']?.toString() ?? '100';

    // Load due date
    if (widget.assignmentData['dueDate'] != null && widget.assignmentData['dueDate'] is Timestamp) {
      _selectedDate = (widget.assignmentData['dueDate'] as Timestamp).toDate();
    }

    // Load existing files
    final fileAttachments = widget.assignmentData['fileAttachments'] as List<dynamic>? ?? [];
    _existingFiles = fileAttachments
        .where((file) => file is Map<String, dynamic>)
        .map((file) => file as Map<String, dynamic>)
        .toList();
  }

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
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

  Future<void> _updateAssignment() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Title is empty")));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: You must be logged in to edit an assignment.")),
      );
      return;
    }

    setState(() => _isLoading = true);
    _uploadProgress.clear();

    try {
      List<Map<String, dynamic>> newFiles = [];

      print("DEBUG: Starting to process ${_selectedFiles.length} files");

      // Process new files
      for (var file in _selectedFiles) {
        try {
          final fileName = file.path.split('/').last;
          final fileSize = await file.length();

          if (fileSize > _maxFileSize) {
            final sizeInMB = (fileSize / 1024 / 1024).toStringAsFixed(2);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('File "$fileName" is too large ($sizeInMB MB). Maximum size is 700KB.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
            continue;
          }

          if (!_isFileTypeSupported(fileName)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('File type not supported: $fileName.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
            continue;
          }

          setState(() {
            _uploadProgress[fileName] = 'Encoding...';
          });

          final base64Data = await _fileToBase64(file);
          final mimeType = _getMimeType(fileName);

          newFiles.add({
            'fileName': fileName,
            'fileType': mimeType,
            'fileSize': fileSize,
            'base64Data': base64Data,
            'uploadedAt': Timestamp.now(),
          });

          setState(() {
            _uploadProgress[fileName] = 'Done';
          });
        } catch (e) {
          print("DEBUG: File processing failed for ${file.path}: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Error processing file: $e"),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }

      print("DEBUG: Processed ${newFiles.length} new files, ${_existingFiles.length} existing files");

      // Combine existing files with new files
      final allFiles = [..._existingFiles, ...newFiles];

      print("DEBUG: Total files to save: ${allFiles.length}");

      // Update Firestore - IMPORTANT: Preserve classId to maintain submission links
      final updateData = {
        'title': _titleController.text,
        'instructions': _instructionsController.text,
        'points': _pointsController.text,
        'dueDate': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : null,
        'teacherId': user.uid,
        'fileAttachments': allFiles,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // Preserve classId if it exists (critical for submissions linking)
      final classId = widget.assignmentData['classId'];
      if (classId != null) {
        updateData['classId'] = classId;
      }
      
      await FirebaseFirestore.instance.collection('assignments').doc(widget.assignmentId).update(updateData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assignment updated successfully!'),
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
        setState(() => _isLoading = false);
      }
    }
  }

  void _removeExistingFile(int index) {
    setState(() {
      _existingFiles.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Assignment", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _updateAssignment,
                  child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: "Title", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _instructionsController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: "Instructions (Optional)", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pointsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Points", border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ListTile(
                    title: const Text("Due Date", style: TextStyle(fontSize: 12)),
                    subtitle: Text(
                      _selectedDate == null
                          ? "No limit"
                          : DateFormat('MMM d, y').format(_selectedDate!),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    onTap: _pickDate,
                    trailing: const Icon(Icons.calendar_month),
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            // Existing files
            if (_existingFiles.isNotEmpty) ...[
              const Text("Existing Files", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              title: const Text("Attach New File"),
              subtitle: Text(_selectedFiles.isEmpty
                  ? "No new files attached"
                  : "${_selectedFiles.length} new files selected"),
              onTap: () async {
                try {
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    allowMultiple: true,
                    type: FileType.any,
                  );

                  if (result != null && result.paths.isNotEmpty) {
                    setState(() {
                      // Add new files to existing list instead of replacing
                      final newFiles = result.paths
                          .where((path) => path != null)
                          .map((path) => File(path!))
                          .toList();
                      _selectedFiles.addAll(newFiles);
                    });
                    print("DEBUG: Files added: ${_selectedFiles.length}");
                  } else {
                    print("DEBUG: No files selected or result is null");
                  }
                } catch (e) {
                  print("DEBUG: Error picking files: $e");
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Error selecting files: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
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
          ],
        ),
      ),
    );
  }
}
