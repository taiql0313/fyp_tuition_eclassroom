import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StudentAnswerQuizPage extends StatefulWidget {
  final String quizId;
  final Map<String, dynamic> quizData;

  const StudentAnswerQuizPage({
    super.key,
    required this.quizId,
    required this.quizData,
  });

  @override
  State<StudentAnswerQuizPage> createState() => _StudentAnswerQuizPageState();
}

class _StudentAnswerQuizPageState extends State<StudentAnswerQuizPage> {
  final Map<int, dynamic> _answers = {}; // questionIndex -> answer
  bool _isSubmitting = false;
  bool _isSubmitted = false;

  @override
  void initState() {
    super.initState();
    _checkIfAlreadySubmitted();
  }

  Future<void> _checkIfAlreadySubmitted() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final submission = await FirebaseFirestore.instance
          .collection('quiz_submissions')
          .where('quizId', isEqualTo: widget.quizId)
          .where('studentId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (submission.docs.isNotEmpty) {
        setState(() {
          _isSubmitted = true;
          // Load previous answers
          final submissionData = submission.docs.first.data();
          final savedAnswers = submissionData['answers'] as Map<String, dynamic>? ?? {};
          savedAnswers.forEach((key, value) {
            _answers[int.parse(key)] = value;
          });
        });
      }
    } catch (e) {
      print('Error checking submission: $e');
    }
  }

  Future<void> _submitQuiz() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: You must be logged in to submit quiz!")),
      );
      return;
    }

    final questions = widget.quizData['questions'] as List<dynamic>? ?? [];
    
    // Check if all questions are answered
    for (int i = 0; i < questions.length; i++) {
      if (!_answers.containsKey(i)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Please answer all questions. Question ${i + 1} is missing.")),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      // Convert answers to string keys for Firestore
      final answersMap = <String, dynamic>{};
      _answers.forEach((key, value) {
        answersMap[key.toString()] = value;
      });

      // Check if submission already exists
      final existingSubmission = await FirebaseFirestore.instance
          .collection('quiz_submissions')
          .where('quizId', isEqualTo: widget.quizId)
          .where('studentId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (existingSubmission.docs.isNotEmpty) {
        // Update existing submission
        await FirebaseFirestore.instance
            .collection('quiz_submissions')
            .doc(existingSubmission.docs.first.id)
            .update({
          'answers': answersMap,
          'submittedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new submission
        await FirebaseFirestore.instance.collection('quiz_submissions').add({
          'quizId': widget.quizId,
          'studentId': user.uid,
          'studentName': user.displayName ?? 'Student',
          'classId': widget.quizData['classId'],
          'answers': answersMap,
          'submittedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        setState(() => _isSubmitted = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Quiz submitted successfully! 🎉"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error submitting quiz: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.quizData['questions'] as List<dynamic>? ?? [];
    final quizTitle = widget.quizData['title'] ?? 'Untitled Quiz';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(quizTitle, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1458A3),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quiz Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.quiz, color: Colors.purple, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quizTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${questions.length} ${questions.length == 1 ? 'question' : 'questions'}",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isSubmitted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 16),
                          SizedBox(width: 4),
                          Text(
                            "Submitted",
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Questions List
            ...questions.asMap().entries.map((entry) {
              int index = entry.key;
              Map<String, dynamic> question = entry.value as Map<String, dynamic>;
              return _buildQuestionCard(index, question);
            }),

            const SizedBox(height: 24),

            // Submit Button
            if (!_isSubmitted)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitQuiz,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1458A3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          "SUBMIT QUIZ",
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(int index, Map<String, dynamic> question) {
    final questionType = question['type'] as String? ?? 'MCQ';
    final questionText = question['question'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Question ${index + 1}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: questionType == 'MCQ' ? Colors.orange.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    questionType == 'MCQ' ? 'MCQ' : 'Short Answer',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: questionType == 'MCQ' ? Colors.orange.shade700 : Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Question Text
            Text(
              questionText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // Answer Input
            if (questionType == 'MCQ') ...[
              _buildMCQOptions(index, question),
            ] else ...[
              _buildShortAnswerInput(index),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMCQOptions(int questionIndex, Map<String, dynamic> question) {
    final options = question['options'] as List<dynamic>? ?? [];
    final selectedAnswer = _answers[questionIndex] as int?;

    return Column(
      children: options.asMap().entries.map((entry) {
        int optionIndex = entry.key;
        String optionText = entry.value.toString();
        final labels = ['A', 'B', 'C', 'D'];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selectedAnswer == optionIndex
                  ? const Color(0xFF1458A3)
                  : Colors.grey.shade300,
              width: selectedAnswer == optionIndex ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: selectedAnswer == optionIndex
                ? const Color(0xFF1458A3).withOpacity(0.05)
                : Colors.white,
          ),
          child: RadioListTile<int>(
            value: optionIndex,
            groupValue: selectedAnswer,
            onChanged: _isSubmitted
                ? null
                : (value) {
                    setState(() {
                      _answers[questionIndex] = value;
                    });
                  },
            title: Text(
              optionText,
              style: TextStyle(
                color: _isSubmitted ? Colors.grey.shade600 : Colors.black87,
              ),
            ),
            secondary: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selectedAnswer == optionIndex
                    ? const Color(0xFF1458A3)
                    : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  labels[optionIndex],
                  style: TextStyle(
                    color: selectedAnswer == optionIndex ? Colors.white : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildShortAnswerInput(int questionIndex) {
    final currentAnswer = _answers[questionIndex] as String? ?? '';

    return TextField(
      enabled: !_isSubmitted,
      maxLines: 4,
      controller: TextEditingController(text: currentAnswer)
        ..selection = TextSelection.collapsed(offset: currentAnswer.length),
      onChanged: (value) {
        setState(() {
          _answers[questionIndex] = value;
        });
      },
      decoration: InputDecoration(
        hintText: "Type your answer here...",
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: _isSubmitted ? Colors.grey.shade100 : Colors.white,
      ),
    );
  }
}
