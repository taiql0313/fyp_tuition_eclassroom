import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class JoinClassroomPage extends StatefulWidget {
  const JoinClassroomPage({super.key});

  @override
  State<JoinClassroomPage> createState() => _JoinClassroomPageState();
}

class _JoinClassroomPageState extends State<JoinClassroomPage> {
  final TextEditingController _classCodeController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  Map<String, dynamic>? _foundClassroom;
  String? _errorMessage;

  Future<void> _searchClassroom() async {
    final classCode = _classCodeController.text.trim().toUpperCase();

    if (classCode.isEmpty) {
      setState(() {
        _errorMessage = "Please enter a class code";
        _foundClassroom = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _foundClassroom = null;
    });

    try {
      // Search for classroom by classCode
      final querySnapshot = await _firestore
          .collection('classrooms')
          .where('classCode', isEqualTo: classCode)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        setState(() {
          _errorMessage = "Classroom not found. Please check the class code.";
          _foundClassroom = null;
          _isLoading = false;
        });
        return;
      }

      final classroomDoc = querySnapshot.docs.first;
      final classroomData = classroomDoc.data();
      final classroomId = classroomDoc.id;

      // Check if classroom is archived - students cannot join archived classes
      if (classroomData['isArchived'] == true) {
        setState(() {
          _errorMessage = "This classroom has been archived and is no longer accepting new students.";
          _foundClassroom = null;
          _isLoading = false;
        });
        return;
      }

      // Check if student is already enrolled
      final user = _auth.currentUser;
      if (user != null) {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
        final classIds = userData?['classIds'] as List<dynamic>? ?? [];

        if (classIds.contains(classroomId)) {
          setState(() {
            _errorMessage = "You are already enrolled in this classroom.";
            _foundClassroom = null;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _foundClassroom = {
          ...classroomData,
          'id': classroomId,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Error searching for classroom: ${e.toString()}";
        _foundClassroom = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _joinClassroom() async {
    if (_foundClassroom == null) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please log in to join a classroom")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final classroomId = _foundClassroom!['id'] as String;
      final userDocRef = _firestore.collection('users').doc(user.uid);

      // Get current classIds
      final userDoc = await userDocRef.get();
      final userData = userDoc.data() ?? {};
      final classIds = List<String>.from(userData['classIds'] ?? []);

      // Check if already enrolled
      if (classIds.contains(classroomId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You are already enrolled in this classroom")),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Add classroom ID to student's classIds array
      classIds.add(classroomId);
      await userDocRef.update({
        'classIds': classIds,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Successfully joined classroom!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error joining classroom: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _classCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Classroom', style: TextStyle(fontWeight: FontWeight.bold)),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1458A3), Color(0xFF2196F3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.class_outlined, size: 60, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    "Join a Classroom",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Enter the class code provided by your teacher",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Class Code Input
            const Text(
              "Class Code",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _classCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: "Enter class code (e.g., CS201)",
                prefixIcon: const Icon(Icons.code),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1458A3), width: 2),
                ),
              ),
              onSubmitted: (_) => _searchClassroom(),
            ),

            const SizedBox(height: 20),

            // Search Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _searchClassroom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1458A3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        "Search Classroom",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),

            // Error Message
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Found Classroom Preview
            if (_foundClassroom != null) ...[
              const SizedBox(height: 30),
              const Text(
                "Classroom Found",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _foundClassroom!['className'] ?? 'Unnamed Classroom',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.person_outline, "Teacher", _foundClassroom!['teacherName'] ?? 'Teacher'),
                    if (_foundClassroom!['subject'] != null) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow(Icons.book_outlined, "Subject", _foundClassroom!['subject']),
                    ],
                    if (_foundClassroom!['section'] != null && _foundClassroom!['section'].toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow(Icons.layers_outlined, "Section", _foundClassroom!['section']),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _joinClassroom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                "Join Classroom",
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
