import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Required for date formatting
import 'dart:io';
import 'dart:convert'; // For Base64 encoding

class CreateAssignmentPage extends StatefulWidget {

  final String classId;

  const CreateAssignmentPage({super.key, required this.classId});

  @override
  State<CreateAssignmentPage> createState() => _CreateAssignmentPageState();
}

class _CreateAssignmentPageState extends State<CreateAssignmentPage> {
  List<File> _selectedFiles = [];
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _pointsController = TextEditingController(text: "100");

  DateTime? _selectedDate;
  bool _isLoading = false;
  Map<String, String> _uploadProgress = {}; // Track upload progress per file

  // Supported file types
  static const List<String> _supportedExtensions = [
    '.zip', '.rar', '.7z', // Archives
    '.pdf', // Documents
    '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', // Office
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', // Images
    '.txt', '.md', // Text
    '.mp4', '.avi', '.mov', // Videos (small ones)
  ];

  // Maximum file size: 700KB (716,800 bytes)
  static const int _maxFileSize = 716 * 1024; // 700KB

  // --- FUNCTION: SELECT DATE / 选择日期 ---
  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // Check if file type is supported
  bool _isFileTypeSupported(String fileName) {
    final extension = fileName.toLowerCase();
    return _supportedExtensions.any((ext) => extension.endsWith(ext));
  }

  // Get MIME type from file extension
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

  // Convert file to Base64
  Future<String> _fileToBase64(File file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  // --- FUNCTION: UPLOAD ASSIGNMENT / 上传作业 ---
  Future<void> _uploadAssignment() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Title is empty")));
      return;
    }

    setState(() => _isLoading = true);
    _uploadProgress.clear();

    try {
      if (_selectedFiles.isEmpty) {
        // Allow creating assignment without files
        await _saveAssignmentToFirestore([]);
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      List<Map<String, dynamic>> fileAttachments = [];

      // Validate and process each file
      for (var file in _selectedFiles) {
        try {
          final fileName = file.path.split('/').last;
          final fileSize = await file.length();

          // Check file size
          if (fileSize > _maxFileSize) {
            final sizeInMB = (fileSize / 1024 / 1024).toStringAsFixed(2);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'File "$fileName" is too large ($sizeInMB MB). Maximum size is 700KB. Please compress the file.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
            continue;
          }

          // Check file type
          if (!_isFileTypeSupported(fileName)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('File type not supported: $fileName. Please use supported file types.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
            continue;
          }

          // Update progress
          setState(() {
            _uploadProgress[fileName] = 'Encoding...';
          });

          // Convert to Base64
          final base64Data = await _fileToBase64(file);
          final mimeType = _getMimeType(fileName);

          // Add to attachments
          // Note: Cannot use FieldValue.serverTimestamp() inside arrays, so use Timestamp.now() instead
          fileAttachments.add({
            'fileName': fileName,
            'fileType': mimeType,
            'fileSize': fileSize,
            'base64Data': base64Data,
            'uploadedAt': Timestamp.now(), // Use Timestamp.now() instead of FieldValue.serverTimestamp() in arrays
          });

          setState(() {
            _uploadProgress[fileName] = 'Done';
          });
        } catch (e) {
          print("DEBUG: File processing failed for ${file.path}: $e");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error processing file: $e")),
          );
        }
      }

      if (fileAttachments.isEmpty && _selectedFiles.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No valid files to upload. Please check file size and type."),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Save to Firestore
      await _saveAssignmentToFirestore(fileAttachments);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print("DEBUG: CRITICAL ERROR: $e");
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

  // Save assignment to Firestore
  Future<void> _saveAssignmentToFirestore(List<Map<String, dynamic>> fileAttachments) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: You must be logged in to create an assignment.")),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('assignments').add({
      'title': _titleController.text,
      'instructions': _instructionsController.text,
      'points': _pointsController.text,
      'dueDate': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : null,
      'classId': widget.classId,
      'teacherId': user.uid,
      'fileAttachments': fileAttachments, // Array of file objects with Base64 data
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Assignment", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          _isLoading
              ? const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton(
            onPressed: _uploadAssignment,
            child: const Text("Assign", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
            ListTile(
              leading: const Icon(Icons.attach_file, color: Colors.blue),
              title: const Text("Attach File"),
              subtitle: Text(_selectedFiles.isEmpty
                  ? "No files attached"
                  : "${_selectedFiles.length} files selected"),
              onTap: () async {
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  allowMultiple: true,
                  type: FileType.any,
                );

                if (result != null) {
                  // IMPORTANT: You must call setState to update the inventory!
                  setState(() {
                    _selectedFiles = result.paths.map((path) => File(path!)).toList();
                  });
                  print("DEBUG: Files added to list: ${_selectedFiles.length}");
                } else {
                  print("DEBUG: User cancelled file picker");
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