import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateClassroomPage extends StatefulWidget {
  const CreateClassroomPage({super.key});

  @override
  State<CreateClassroomPage> createState() => _CreateClassroomPageState();
}

class _CreateClassroomPageState extends State<CreateClassroomPage> {
  // 1. Controllers to capture the "Guild" info
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  String? _selectedSubject; // For the dropdown
  final List<String> _subjects = ["Physics", "Mathematics", "Computer Science", "Biology", "English"];

  // 2. The "Save to Firebase" function
  Future<void> _saveClassroom() async {
    // 1. Get the current logged-in teacher's info
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) return; // Guard: Must be logged in

    try {
      // 2. Add to "classrooms" collection
      await FirebaseFirestore.instance.collection('classrooms').add({
        'className': _nameController.text,
        'subject': _selectedSubject,
        'classCode': _codeController.text,
        'section': _sectionController.text,
        'description': _descController.text,

        // CRITICAL: Link to this specific teacher
        'teacherId': user.uid,
        'teacherName': user.displayName ?? "Teacher",

        'createdAt': FieldValue.serverTimestamp(),
      });

      Navigator.pop(context); // Go back after success
    } catch (e) {
      print("Error saving class: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Classroom', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TOP PREVIEW CARD (Matches your pic) ---
            _buildPreviewCard(),

            const SizedBox(height: 30),
            const Text("Classroom Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // --- INPUT FIELDS ---
            _buildInputField("Classroom Name", "e.g., Data Structures 2024", Icons.book, _nameController),

            const SizedBox(height: 15),
            _buildDropdownField(),

            const SizedBox(height: 15),
            _buildInputField("Class Code", "e.g., CS201", Icons.code, _codeController),

            const SizedBox(height: 15),
            _buildInputField("Section (Optional)", "e.g., Section A", Icons.layers, _sectionController),

            const SizedBox(height: 15),
            _buildInputField("Description (Optional)", "Describe your classroom...", Icons.description, _descController, isLong: true),

            const SizedBox(height: 30),

            // --- CREATE BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _saveClassroom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1458A3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("CREATE CLASSROOM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI HELPER METHODS ---

  Widget _buildPreviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue.shade300, Colors.indigo.shade400]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
            child: const Text("CLASS CODE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 15),
          const Text("Classroom Name", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          Text(_selectedSubject ?? "Subject", style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.school, color: Colors.white70, size: 18),
              SizedBox(width: 5), Text("Teacher", style: TextStyle(color: Colors.white70)),
              SizedBox(width: 20),
              Icon(Icons.people, color: Colors.white70, size: 18),
              SizedBox(width: 5), Text("0 Students", style: TextStyle(color: Colors.white70)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInputField(String label, String hint, IconData icon, TextEditingController controller, {bool isLong = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: isLong ? 3 : 1,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Subject", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text("Select Subject"),
              value: _selectedSubject,
              items: _subjects.map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
              onChanged: (val) => setState(() => _selectedSubject = val),
            ),
          ),
        ),
      ],
    );
  }
}