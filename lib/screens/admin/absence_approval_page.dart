import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fyp_tuition_eclassroom/services/attendance_service.dart';
import 'package:fyp_tuition_eclassroom/models/attendance_models.dart';
import 'package:fyp_tuition_eclassroom/utils/timezone_helper.dart';

class AbsenceApprovalPage extends StatefulWidget {
  const AbsenceApprovalPage({super.key});

  @override
  State<AbsenceApprovalPage> createState() => _AbsenceApprovalPageState();
}

class _AbsenceApprovalPageState extends State<AbsenceApprovalPage> with SingleTickerProviderStateMixin {
  final AttendanceService _attendanceService = AttendanceService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Absence Document Approval"),
        backgroundColor: const Color(0xff1458a3),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "Pending", icon: Icon(Icons.pending_outlined)),
            Tab(text: "All Documents", icon: Icon(Icons.history)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingTab(),
          _buildAllDocumentsTab(),
        ],
      ),
    );
  }

  Widget _buildPendingTab() {
    return StreamBuilder<List<AbsenceDocument>>(
      stream: _attendanceService.streamPendingDocuments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, size: 80, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  "No pending documents",
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  "All absence documents have been reviewed",
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        final documents = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentCard(documents[index], isPending: true);
          },
        );
      },
    );
  }

  Widget _buildAllDocumentsTab() {
    return StreamBuilder<List<AbsenceDocument>>(
      stream: _attendanceService.streamAllDocuments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text("No documents found"),
          );
        }

        final documents = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildDocumentCard(documents[index], isPending: false);
          },
        );
      },
    );
  }

  Widget _buildDocumentCard(AbsenceDocument document, {required bool isPending}) {
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPending ? statusColor.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
          width: isPending ? 2 : 1,
        ),
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
          document.studentName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              "${document.subject} - ${document.className}",
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              "${DateFormat('MMM d, yyyy').format(document.startDate)} - ${DateFormat('MMM d, yyyy').format(document.endDate)}",
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
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
                // Reason
                _buildInfoRow("Reason", document.reason),
                const SizedBox(height: 12),
                
                // Date Range
                _buildInfoRow(
                  "Date Range",
                  "${DateFormat('MMM d, yyyy').format(document.startDate)} - ${DateFormat('MMM d, yyyy').format(document.endDate)}",
                ),
                const SizedBox(height: 12),
                
                // Submitted At (in Malaysia time)
                _buildInfoRow(
                  "Submitted",
                  DateFormat('MMM d, yyyy • h:mm a').format(
                    TimezoneHelper.toMalaysiaTime(document.submittedAt),
                  ),
                ),
                
                // Review Info (if reviewed)
                if (document.reviewedBy != null) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    "Reviewed By",
                    document.reviewedBy ?? 'N/A',
                  ),
                    if (document.reviewedAt != null) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        "Reviewed At",
                        DateFormat('MMM d, yyyy • h:mm a').format(
                          TimezoneHelper.toMalaysiaTime(document.reviewedAt!),
                        ),
                      ),
                    ],
                ],
                
                // Review Notes (if any)
                if (document.reviewNotes != null && document.reviewNotes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow("Admin Notes", document.reviewNotes!),
                ],
                
                const SizedBox(height: 16),
                
                // File Preview/Download
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
                
                // Action Buttons (only for pending)
                if (isPending) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showRejectDialog(document),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text("Reject"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _approveDocument(document),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text("Approve"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
            style: TextStyle(
              color: Colors.grey[900],
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openFile(String fileRef) async {
    try {
      // Check if it's a Firestore reference or Storage URL
      if (fileRef.startsWith('firestore:')) {
        // Show loading
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
          // Get file from Firestore
          final fileData = await _attendanceService.getFileFromFirestore(fileRef);
          final base64Data = fileData['fileData'] as String;
          final originalFileName = fileData['originalFileName'] as String;
          final fileSize = fileData['fileSize'] as int;
          
          // Close loading dialog
          if (mounted) Navigator.pop(context);
          
          // Show file viewer dialog
          if (!mounted) return;
          _showFileViewerDialog(originalFileName, base64Data, fileSize);
        } catch (e) {
          // Close loading dialog
          if (mounted) Navigator.pop(context);
          rethrow;
        }
      } else {
        // It's a Storage URL - use url_launcher
        final uri = Uri.parse(fileRef);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Cannot open file")),
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
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xff1458a3),
                  borderRadius: const BorderRadius.only(
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
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // File info
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
                      
                      // Image preview
                      if (isImage) ...[
                        Container(
                          constraints: const BoxConstraints(maxHeight: 500),
                          child: Image.memory(
                            base64Decode(base64Data),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ] else if (isPdf) ...[
                        // PDF - show message
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
                              const SizedBox(height: 24),
                              const Text(
                                'PDF files cannot be previewed in-app.\nThe file data is available for download.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Other file types
                        Container(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              const Icon(Icons.insert_drive_file, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                fileName.split('.').last.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'File size: ${(fileSize / 1024).toStringAsFixed(2)} KB',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              // Footer with download option
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
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Copy base64 data to clipboard or show download option
                        _downloadFile(fileName, base64Data);
                      },
                      icon: const Icon(Icons.download),
                      label: const Text("Download"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff1458a3),
                        foregroundColor: Colors.white,
                      ),
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

  void _downloadFile(String fileName, String base64Data) {
    // For now, show the base64 data in a dialog
    // In a real app, you'd use a proper download mechanism
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("File Data"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("File: $fileName"),
            const SizedBox(height: 16),
            const Text(
              "File data is stored in Firestore. To download, the file data would need to be saved to device storage.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _approveDocument(AbsenceDocument document) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Approve Document"),
        content: const Text("Are you sure you want to approve this absence document?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Approve"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loading
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
                Text("Approving document and updating attendance records..."),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _attendanceService.updateDocumentStatus(
        documentId: document.id,
        status: 'approved',
        reviewedBy: user.displayName ?? user.email ?? 'Admin',
      );

      if (!mounted) return;
      
      // Close loading dialog
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Document approved successfully. Attendance records have been updated."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      // Close loading dialog
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error approving document: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _showRejectDialog(AbsenceDocument document) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Document"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Are you sure you want to reject this absence document?"),
            const SizedBox(height: 16),
            const Text(
              "Reason for rejection (optional):",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                hintText: "Enter rejection reason...",
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Reject"),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await _attendanceService.updateDocumentStatus(
        documentId: document.id,
        status: 'rejected',
        reviewedBy: user.displayName ?? user.email ?? 'Admin',
        reviewNotes: notesController.text.trim().isEmpty 
            ? null 
            : notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Document rejected"),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error rejecting document: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
