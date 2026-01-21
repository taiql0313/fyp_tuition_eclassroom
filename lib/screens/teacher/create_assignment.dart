import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Required for date formatting
import 'dart:io';

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

  // --- FUNCTION: UPLOAD ASSIGNMENT / 上传作业 ---
  Future<void> _uploadAssignment() async {

    if (_selectedFiles.isEmpty) {
      print("DEBUG: Warning - _selectedFiles is empty. Nothing will be uploaded.");
    } else {
      print("DEBUG: Preparing to upload ${_selectedFiles.length} files.");
    }

    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Title is empty")));
      return;
    }

    setState(() => _isLoading = true);
    List<String> fileUrls = [];

    try {
      print("DEBUG: Number of files to upload: ${_selectedFiles.length}");

      // 1. UPLOAD LOOP / 上传循环
      for (var file in _selectedFiles) {
        try {
          String fileName = "${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}";

          // 1. Get Reference / 获取引用
          Reference storageRef = FirebaseStorage.instance.ref().child('assignments/$fileName');

          // 2. Start Upload / 开始上传
          UploadTask uploadTask = storageRef.putFile(file);

          // 3. WAIT for the snapshot / 等待快照完成
          // This is the most important line!
          TaskSnapshot snapshot = await uploadTask.whenComplete(() => null);

          // 4. Now get the URL / 现在获取 URL
          String url = await snapshot.ref.getDownloadURL();
          fileUrls.add(url);

          print("DEBUG: Uploaded to $url");
        } catch (e) {
          print("DEBUG: File upload failed: $e");
        }
      }

      print("DEBUG: Final fileUrls list size: ${fileUrls.length}");

      // 2. SAVE TO FIRESTORE / 保存到 FIRESTORE
      await FirebaseFirestore.instance.collection('assignments').add({
        'title': _titleController.text,
        'instructions': _instructionsController.text,
        'points': _pointsController.text,
        'dueDate': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : null,
        'classId': widget.classId,
        'fileAttachments': fileUrls, // <--- THE GOLD GOES HERE
        'createdAt': FieldValue.serverTimestamp(),
      });

      Navigator.pop(context);
    } catch (e) {
      print("DEBUG: CRITICAL ERROR: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
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
            return Chip(
              label: Text(file.path.split('/').last, style: const TextStyle(fontSize: 12)),
              onDeleted: () {
                setState(() {
                  _selectedFiles.remove(file); // Remove from "Inventory"
                });
              },
            );
          }).toList(),
        ),
          ],
        ),
      ),
    );
  }
}