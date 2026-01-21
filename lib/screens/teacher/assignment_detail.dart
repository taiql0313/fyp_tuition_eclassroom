import 'package:flutter/material.dart';

class TeacherAssignmentDetailPage extends StatelessWidget {
  final Map<String, dynamic> assignmentData;

  const TeacherAssignmentDetailPage({super.key, required this.assignmentData});

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
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {
              // Menu for Edit or Delete
            },
          ),
        ],
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20)),
                child: const Text("Computer Science", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                child: const Text("100 points", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            "Data Structures Project",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            "Implement a binary search tree with the following operations: insert, delete, search, and traversal. Write a report.",
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.calendar_today, "Due Date", "Mon, Dec 15, 2025", Colors.red.shade100, Colors.red),
          const Divider(height: 30),
          _buildInfoRow(Icons.person_outline, "Teacher", "Dr. Sarah Johnson", Colors.blue.shade100, Colors.blue),
          const Divider(height: 30),
          _buildInfoRow(Icons.access_time, "Assigned", "Dec 07", Colors.green.shade100, Colors.green),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Attachments", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text("3 files", style: TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 15),
          _buildFileItem("Project Guidelines.pdf"),
        ],
      ),
    );
  }

  Widget _buildFileItem(String fileName) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(child: Text(fileName, style: const TextStyle(fontWeight: FontWeight.w500))),
          const Icon(Icons.download, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.people),
              label: const Text("Submissions"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                // FIXED: Added RoundedRectangleBorder
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.edit),
              label: const Text("Edit Task"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                // FIXED: Added RoundedRectangleBorder
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