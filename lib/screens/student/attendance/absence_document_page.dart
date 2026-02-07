import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fyp_tuition_eclassroom/services/attendance_service.dart';
import 'package:fyp_tuition_eclassroom/services/user_service.dart';
import 'package:fyp_tuition_eclassroom/models/user_model.dart';
import 'package:fyp_tuition_eclassroom/models/attendance_models.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

// Same day names as teacher's create_attendance_code_page (classrooms collection uses these)
const List<String> _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

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

  /// Check if a class has a session on any date in the range using the same logic as the
  /// teacher's create_attendance_code_page: classrooms collection with day (e.g. "Wednesday").
  /// Returns true if the classroom's scheduled day falls on any date in [startDate]..[endDate].
  bool _classHasSessionInDateRange(
    Map<String, dynamic> classData,
    DateTime startDate,
    DateTime endDate,
  ) {
    final dayStr = classData['day'] as String?;
    if (dayStr == null || dayStr.isEmpty) return false;

    final dayIndex = _dayNames.indexOf(dayStr);
    if (dayIndex < 0) return false;
    // Dart DateTime.weekday: Monday=1, Sunday=7
    final weekday = dayIndex + 1;

    DateTime current = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    while (!current.isAfter(end)) {
      if (current.weekday == weekday) return true;
      current = current.add(const Duration(days: 1));
    }
    return false;
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

      // Filter classes that have sessions in the selected date range using the same
      // logic as teacher's attendance code page: classroom day (e.g. Wednesday) must
      // fall on at least one date in the range.
      final applicableClasses = <MapEntry<String, Map<String, dynamic>>>[];
      for (var entry in _classes.entries) {
        final classData = entry.value;
        final hasSessions = _classHasSessionInDateRange(
          classData,
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
      // Clear form so list updates and user can submit again if needed
      setState(() {
        _dateController.clear();
        _reasonController.clear();
        _selectedDateRange = null;
        _selectedFile = null;
        _isFileSelected = false;
        _fileName = "";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Document submitted successfully for ${applicableClasses.length} class(es).",
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
      // Do not pop - stay on page so history section updates
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Submit Absence Proof"),
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
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

            // --- Absence document history ---
            const SizedBox(height: 40),
            const Text(
              "Absence document history",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            if (_auth.currentUser != null) _buildHistorySection(_auth.currentUser!.uid) else const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection(String studentId) {
    return StreamBuilder<List<AbsenceDocument>>(
      stream: _attendanceService.streamStudentDocuments(studentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.history, size: 40, color: Colors.grey[400]),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    "No absence documents submitted yet.",
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ),
              ],
            ),
          );
        }
        final documents = snapshot.data!;
        return Column(
          children: documents.map((doc) => _buildDocumentHistoryCard(doc)).toList(),
        );
      },
    );
  }

  Widget _buildDocumentHistoryCard(AbsenceDocument document) {
    final isApproved = document.status == 'approved';
    final isRejected = document.status == 'rejected';
    Color statusColor;
    IconData statusIcon;
    String statusText;
    if (isApproved) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'Approved';
    } else if (isRejected) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      statusText = 'Rejected';
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.pending;
      statusText = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(statusIcon, color: statusColor, size: 24),
        ),
        title: Text(
          "${DateFormat('MMM d, yyyy').format(document.startDate)} – ${DateFormat('MMM d, yyyy').format(document.endDate)}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow("Reason", document.reason),
                const SizedBox(height: 12),
                _buildInfoRow(
                  "Submitted",
                  DateFormat('MMM d, yyyy • h:mm a').format(
                    TimezoneHelper.toMalaysiaTime(document.submittedAt),
                  ),
                ),
                if (document.reviewedBy != null) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow("Reviewed by", document.reviewedBy ?? 'N/A'),
                  if (document.reviewedAt != null) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      "Reviewed at",
                      DateFormat('MMM d, yyyy • h:mm a').format(
                        TimezoneHelper.toMalaysiaTime(document.reviewedAt!),
                      ),
                    ),
                  ],
                ],
                if (document.reviewNotes != null && document.reviewNotes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow("Admin notes", document.reviewNotes!),
                ],
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => _openFile(document.fileUrl),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            document.fileName,
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.open_in_new, color: Colors.blue, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            "$label:",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: Colors.grey[900], fontSize: 13),
          ),
        ),
      ],
    );
  }

  Future<void> _openFile(String fileRef) async {
    try {
      if (fileRef.startsWith('firestore:')) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Loading file..."),
                  ],
                ),
              ),
            ),
          ),
        );
        try {
          final fileData = await _attendanceService.getFileFromFirestore(fileRef);
          final base64Data = fileData['fileData'] as String;
          final originalFileName = fileData['originalFileName'] as String;
          final fileSize = fileData['fileSize'] as int;
          if (mounted) Navigator.pop(context);
          if (!mounted) return;
          _showFileViewerDialog(originalFileName, base64Data, fileSize);
        } catch (e) {
          if (mounted) Navigator.pop(context);
          rethrow;
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Document link is not available for preview here.")),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error opening file: ${e.toString()}"),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showFileViewerDialog(String fileName, String base64Data, int fileSize) {
    final fileExtension = fileName.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExtension);
    final isPdf = fileExtension == 'pdf';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xff1458a3),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.grey[700]),
                            const SizedBox(width: 8),
                            Text(
                              'File size: ${(fileSize / 1024).toStringAsFixed(2)} KB',
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isImage)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 500),
                          child: Image.memory(
                            base64Decode(base64Data),
                            fit: BoxFit.contain,
                          ),
                        )
                      else if (isPdf)
                        Container(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              const Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              const Text(
                                'PDF Document',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'File size: ${(fileSize / 1024).toStringAsFixed(2)} KB',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              const Icon(Icons.insert_drive_file, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                'File size: ${(fileSize / 1024).toStringAsFixed(2)} KB',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                    ),
                  ],
                ),
              ),
            ],
          ),
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