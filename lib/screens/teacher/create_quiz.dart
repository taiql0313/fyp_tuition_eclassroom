import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateQuizPage extends StatefulWidget {
  const CreateQuizPage({super.key});

  @override
  State<CreateQuizPage> createState() => _CreateQuizPageState();
}

class _CreateQuizPageState extends State<CreateQuizPage> {
  // 1. Controllers for the main Quiz info
  final TextEditingController _quizTitleController = TextEditingController();

  // 2. This List acts as your "Inventory" for all questions added
  final List<Map<String, dynamic>> _questions = [];

  // Function to add a new question "Slot" to the list
  void _addNewQuestion(String type) {
    setState(() {
      if (type == 'MCQ') {
        _questions.add({
          'type': 'MCQ',
          'question': TextEditingController(),
          'options': [TextEditingController(), TextEditingController(), TextEditingController(), TextEditingController()],
          'correctAnswer': 0,
        });
      } else {
        _questions.add({
          'type': 'ShortAnswer',
          'question': TextEditingController(),
          'sampleAnswer': TextEditingController(),
        });
      }
    });
  }

  // The "Save" Skill - Sending data to Firebase
  Future<void> _saveQuizToFirebase() async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: You must be logged in to create a quiz!")),
      );
      return;
    }

    if (_quizTitleController.text.isEmpty || _questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add a title and at least one question!")),
      );
      return;
    }

    // Convert Controllers into simple Strings for the database
    List<Map<String, dynamic>> serializedQuestions = _questions.map((q) {
      if (q['type'] == 'MCQ') {
        return {
          'type': 'MCQ',
          'question': q['question'].text,
          'options': (q['options'] as List<TextEditingController>)
              .map((c) => c.text)
              .toList(),
          'correctAnswer': q['correctAnswer'],
        };
      } else {
        return {
          'type': 'ShortAnswer',
          'question': q['question'].text,
          'sampleAnswer': q['sampleAnswer'].text,
        };
      }
    }).toList();

    try {
      await FirebaseFirestore.instance.collection('quizzes').add({
        'title': _quizTitleController.text,
        'teacherId': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'questions': serializedQuestions,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Quiz Created Successfully! 🎉")),
        );
        Navigator.pop(context); // Go back to Dashboard
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Light background
      appBar: AppBar(
        title: const Text('Create Quiz', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1458A3),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // QUIZ TITLE SECTION
            const Text("Quiz Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _quizTitleController,
              decoration: const InputDecoration(
                labelText: 'Enter Quiz Title',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
            ),
            const Divider(height: 40),

            // DYNAMIC QUESTION LIST
            ..._questions.asMap().entries.map((entry) {
              int index = entry.key;
              Map<String, dynamic> q = entry.value;
              return _buildQuestionCard(index, q);
            }),

            const SizedBox(height: 20),

            // BUTTONS TO ADD QUESTIONS
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _addNewQuestion('MCQ'),
                    icon: const Icon(Icons.list),
                    label: const Text("Add MCQ"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _addNewQuestion('Short'),
                    icon: const Icon(Icons.short_text),
                    label: const Text("Add Short Answer"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // SAVE BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveQuizToFirebase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1458A3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("PUBLISH QUIZ", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // The Card "Template" for each question
  Widget _buildQuestionCard(int index, Map<String, dynamic> q) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Question ${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1458A3))),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => setState(() => _questions.removeAt(index)),
                ),
              ],
            ),
            TextField(
              controller: q['question'],
              decoration: const InputDecoration(hintText: "Enter your question here"),
            ),
            const SizedBox(height: 15),

            if (q['type'] == 'MCQ') ...[
              const Text("Options:", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ...(q['options'] as List<TextEditingController>).asMap().entries.map((opt) {
                // Define labels A, B, C, D
                List<String> labels = ['A', 'B', 'C', 'D'];

                return TextField(
                  controller: opt.value,
                  decoration: InputDecoration(
                    labelText: "Option ${labels[opt.key]}", // Shows Option A, Option B, etc.
                    prefixIcon: Radio(
                      value: opt.key,
                      groupValue: q['correctAnswer'],
                      onChanged: (val) => setState(() => q['correctAnswer'] = val),
                    ),
                  ),
                );
              }),
            ] else ...[
              TextField(
                controller: q['sampleAnswer'],
                decoration: const InputDecoration(labelText: "Correct Answer (for AI Grading Reference)"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}