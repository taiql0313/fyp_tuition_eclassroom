import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_tuition_eclassroom/services/attendance_service.dart';
import 'package:fyp_tuition_eclassroom/services/user_service.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';

class AbsenceDocumentPage extends StatefulWidget {
  const AbsenceDocumentPage({super.key});

  @override
  State<AbsenceDocumentPage> createState() => _AbsenceDocumentPageState();
}

class _AbsenceDocumentPageState extends State<AbsenceDocumentPage> {
  final _dateController = TextEditingController();
  final _reasonController = TextEditingController();
  final AttendanceService _attendanceService = AttendanceService();
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  File? _selectedFile;
  bool _isFileSelected = false;
  String _fileName = "";
  DateTimeRange? _selectedDateRange;
  bool _isLoading = false;
  Map<String, Map<String, dynamic>> _classes = {}; // classId -> classData
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final appUser = await _userService.getUser(user.uid);
    if (appUser == null) return;

    setState(() {
      _currentUser = appUser;
    });

    // Load class information
    if (appUser.classIds.isNotEmpty) {
      for (var classId in appUser.classIds) {
        final classDoc = await _db.collection('classrooms').doc(classId).get();
        if (classDoc.exists) {
          setState(() {
            _classes[classId] = classDoc.data()!;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  // Date Range Picker Logic
  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xff1458a3), // Header background color
              onPrimary: Colors.white, // Header text color
              onSurface: Colors.black, // Body text color
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Validate: end date must be >= start date
      if (picked.end.isBefore(picked.start)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("End date must be on or after start date"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _selectedDateRange = picked;
        // Format: "2023-10-01 - 2023-10-03" or just "2023-10-01" if same day
        final start = DateFormat('yyyy-MM-dd').format(picked.start);
        final end = DateFormat('yyyy-MM-dd').format(picked.end);

        if (start == end) {
          _dateController.text = start;
        } else {
          _dateController.text = "$start  to  $end";
        }
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        
        // Check file size before proceeding (1MB limit)
        final fileSize = await file.length();
        const maxSize = 1024 * 1024; // 1MB
        if (fileSize > maxSize) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File is too large (${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB). '
                'Maximum size is 1MB. Please compress or resize the file.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }

        if (fileSize == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Selected file is empty (0 bytes)"),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        setState(() {
          _selectedFile = file;
          _isFileSelected = true;
          _fileName = result.files.single.name;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error selecting file: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitForm() async {
    if (_dateController.text.isEmpty || _reasonController.text.isEmpty || !_isFileSelected || _selectedDateRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all fields and upload a document."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please log in to submit document."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You are not enrolled in any classes."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Upload file to Firebase Storage once
      final fileUrl = await _attendanceService.uploadAbsenceDocumentFile(
        _selectedFile!,
        user.uid,
      );

      // Filter classes that have sessions/records in the selected date range
      final applicableClasses = <MapEntry<String, Map<String, dynamic>>>[];
      
      for (var entry in _classes.entries) {
        final classId = entry.key;
        final hasSessions = await _attendanceService.hasClassSessionsInDateRange(
          classId,
          _selectedDateRange!.start,
          _selectedDateRange!.end,
        );
        
        if (hasSessions) {
          applicableClasses.add(entry);
        }
      }

      if (applicableClasses.isEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No classes have attendance sessions in the selected date range. "
              "Please select a date range that includes days when classes were held.",
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      // Submit document only for classes with sessions in the date range
      for (var entry in applicableClasses) {
        final classId = entry.key;
        final classData = entry.value;
        
        await _attendanceService.submitAbsenceDocumentWithUrl(
          studentId: user.uid,
          studentName: user.displayName ?? 'Student',
          classId: classId,
          className: classData['className'] ?? 'Class',
          subject: classData['subject'] ?? 'Subject',
          startDate: _selectedDateRange!.start,
          endDate: _selectedDateRange!.end,
          reason: _reasonController.text,
          fileUrl: fileUrl, // Same file URL for all classes
          fileName: _fileName,
        );
      }

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Document submitted successfully for ${applicableClasses.length} class(es) "
            "with sessions in the selected date range!",
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error submitting document: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Submit Absence Proof"),
        backgroundColor: const Color(0xff1458a3),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Upload Supporting Document",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              "Please upload a clear photo or PDF of your Medical Certificate (MC) or explanation letter. This will only apply to classes that have attendance sessions in the selected date range.",
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            if (_classes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                "Note: This document will only apply to classes that have attendance sessions in the selected date range.",
                style: TextStyle(color: Colors.orange[700], fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 24),

            // --- Enhanced File Upload Area ---
            GestureDetector(
              onTap: _isLoading ? null : _pickFile,
              child: Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isFileSelected ? Colors.green.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isFileSelected ? Colors.green : Colors.grey.shade300,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isFileSelected ? Icons.check_circle : Icons.cloud_upload_outlined,
                      size: 50,
                      color: _isFileSelected ? Colors.green : const Color(0xff1458a3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isFileSelected ? "File Selected" : "Tap to Select File",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _isFileSelected ? Colors.green : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isFileSelected ? _fileName : "Supported formats: JPG, PNG, PDF",
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    if (_isFileSelected)
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() {
                                _isFileSelected = false;
                                _selectedFile = null;
                                _fileName = "";
                              }),
                        child: const Text("Remove", style: TextStyle(color: Colors.red)),
                      )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            const Text("Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // --- Date Range Picker Input ---
            TextFormField(
              controller: _dateController,
              readOnly: true, // Prevent manual typing
              onTap: () => _selectDateRange(context),
              decoration: _inputDecoration("Date Range of Absence", Icons.date_range),
            ),
            const SizedBox(height: 16),

            // --- Reason Input ---
            TextFormField(
              controller: _reasonController,
              maxLines: 4,
              decoration: _inputDecoration("Reason / Remarks", Icons.edit_note).copyWith(
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 40),

            // --- Submit Button ---
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff1458a3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                onPressed: (_isLoading || !_isFileSelected) ? null : _submitForm,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Submit Document",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper for consistent input styling
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xff1458a3)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff1458a3), width: 2),
      ),
    );
  }
}