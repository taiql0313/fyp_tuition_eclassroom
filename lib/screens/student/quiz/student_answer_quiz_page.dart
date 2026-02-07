import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'student_quiz_result_page.dart';
import '../../../services/quiz_grading_service.dart';

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
  final Map<int, TextEditingController> _shortAnswerControllers = {}; // controllers for short answers
  bool _isSubmitting = false;
  bool _isSubmitted = false;
  String? _submissionId;
  Map<String, dynamic>? _submissionData;
  final QuizGradingService _gradingService = QuizGradingService();

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _checkIfAlreadySubmitted();
  }
  
  void _initializeControllers() {
    final questions = widget.quizData['questions'] as List<dynamic>? ?? [];
    for (int i = 0; i < questions.length; i++) {
      final question = questions[i] as Map<String, dynamic>;
      if (question['type'] == 'ShortAnswer') {
        _shortAnswerControllers[i] = TextEditingController();
      }
    }
  }
  
  @override
  void dispose() {
    for (var controller in _shortAnswerControllers.values) {
      controller.dispose();
    }
    super.dispose();
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

      print('DEBUG _checkIfAlreadySubmitted: Found ${submission.docs.length} submissions');

      if (submission.docs.isNotEmpty) {
        final doc = submission.docs.first;
        final data = doc.data();
        
        print('DEBUG _checkIfAlreadySubmitted: Submission ID = ${doc.id}');
        print('DEBUG _checkIfAlreadySubmitted: Data keys = ${data.keys.toList()}');
        
        // Load previous answers from graded answers list
        final answersData = data['answers'];
        print('DEBUG _checkIfAlreadySubmitted: answers type = ${answersData.runtimeType}');
        
        final Map<int, dynamic> loadedAnswers = {};
        
        if (answersData is List) {
          // New format: List of graded answers
          for (var answer in answersData) {
            if (answer is Map<String, dynamic>) {
              final index = answer['questionIndex'] as int?;
              final studentAnswer = answer['studentAnswer'];
              if (index != null) {
                loadedAnswers[index] = studentAnswer;
                print('DEBUG _checkIfAlreadySubmitted: Loaded answer[$index] = $studentAnswer');
              }
            }
          }
        } else if (answersData is Map) {
          // Old format: Map of answers
          answersData.forEach((key, value) {
            final index = int.tryParse(key.toString());
            if (index != null) {
              loadedAnswers[index] = value;
              print('DEBUG _checkIfAlreadySubmitted: Loaded answer[$index] = $value (old format)');
            }
          });
        }
        
        setState(() {
          _isSubmitted = true;
          _submissionId = doc.id;
          _submissionData = data;
          _answers.clear();
          _answers.addAll(loadedAnswers);
          
          // Update short answer controllers with loaded answers
          loadedAnswers.forEach((index, answer) {
            if (_shortAnswerControllers.containsKey(index) && answer is String) {
              _shortAnswerControllers[index]!.text = answer;
            }
          });
        });
        
        print('DEBUG _checkIfAlreadySubmitted: Total loaded answers = ${_answers.length}');
        print('DEBUG _checkIfAlreadySubmitted: _isSubmitted = $_isSubmitted');
        print('DEBUG _checkIfAlreadySubmitted: _submissionId = $_submissionId');
      }
    } catch (e, stackTrace) {
      print('Error checking submission: $e');
      print('Stack trace: $stackTrace');
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
      // Auto-grade MCQ questions / 自动评分 MCQ 题目
      final List<Map<String, dynamic>> gradedAnswers = [];
      int totalScore = 0;
      int maxTotalScore = 0;
      int mcqCorrect = 0;
      int mcqTotal = 0;
      int shortAnswerTotal = 0;
      
      // Get quiz context for grading / 获取测验上下文用于评分
      final quizTitle = widget.quizData['title'] ?? 'Untitled Quiz';
      final subject = widget.quizData['subject'] as String?;
      
      // First, grade all MCQ questions / 首先，评分所有 MCQ 题目
      for (int i = 0; i < questions.length; i++) {
        final question = questions[i] as Map<String, dynamic>;
        final questionType = question['type'] as String? ?? 'MCQ';
        final studentAnswer = _answers[i];
        
        if (questionType == 'MCQ') {
          // MCQ: Auto-grade by comparing with correct answer
          // MCQ：对比正确答案自动评分
          final correctAnswer = question['correctAnswer'] as int?;
          final isCorrect = studentAnswer == correctAnswer;
          final score = isCorrect ? 1 : 0; // 1 mark per MCQ / 每题 1 分
          
          gradedAnswers.add({
            'questionIndex': i,
            'type': 'MCQ',
            'studentAnswer': studentAnswer,
            'correctAnswer': correctAnswer,
            'isCorrect': isCorrect,
            'score': score,
            'maxScore': 1,
          });
          
          totalScore += score;
          maxTotalScore += 1;
          mcqTotal++;
          if (isCorrect) mcqCorrect++;
        }
      }
      
      // Then, grade Short Answer questions with AI (Option A - user waits) / 然后，使用 AI 评分简答题（选项 A - 用户等待）
      final shortAnswerMaxScore = QuizGradingService.getShortAnswerMaxScore(); // 2 marks / 2 分
      
      for (int i = 0; i < questions.length; i++) {
        final question = questions[i] as Map<String, dynamic>;
        final questionType = question['type'] as String? ?? 'MCQ';
        final studentAnswer = _answers[i];
        
        if (questionType == 'ShortAnswer') {
          // Show loading message for this question
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Grading question ${i + 1}..."),
                duration: const Duration(seconds: 1),
              ),
            );
          }
          
          // Call AI grading service / 调用 AI 评分服务
          final gradingResult = await _gradingService.gradeShortAnswer(
            question: question['question'] ?? '',
            studentAnswer: studentAnswer?.toString() ?? '',
            sampleAnswer: question['sampleAnswer'] ?? '',
            quizTitle: quizTitle,
            subject: subject,
          );
          
          final shortAnswerScore = gradingResult['score'] as int? ?? 0;
          final aiFeedback = gradingResult['feedback'] as String?;
          final status = gradingResult['status'] as String? ?? 'pending_grading';
          
          gradedAnswers.add({
            'questionIndex': i,
            'type': 'ShortAnswer',
            'studentAnswer': studentAnswer?.toString() ?? '',
            'sampleAnswer': question['sampleAnswer'] ?? '',
            'score': status == 'graded' ? shortAnswerScore : null,
            'maxScore': shortAnswerMaxScore, // 2 marks / 2 分
            'status': status,
            'aiFeedback': aiFeedback, // AI feedback / AI 反馈
          });
          
          if (status == 'graded') {
            totalScore += shortAnswerScore;
          }
          maxTotalScore += shortAnswerMaxScore;
          shortAnswerTotal++;
        }
      }

      // Check if submission already exists
      final existingSubmission = await FirebaseFirestore.instance
          .collection('quiz_submissions')
          .where('quizId', isEqualTo: widget.quizId)
          .where('studentId', isEqualTo: user.uid)
          .limit(1)
          .get();

      final submissionData = {
        'quizId': widget.quizId,
        'quizTitle': widget.quizData['title'] ?? 'Untitled Quiz',
        'studentId': user.uid,
        'studentName': user.displayName ?? 'Student',
        'classId': widget.quizData['classId'],
        'answers': gradedAnswers,
        'totalScore': totalScore,
        'maxTotalScore': maxTotalScore,
        'mcqScore': mcqCorrect,   // 1 mark per MCQ / 每题 1 分
        'mcqMaxScore': mcqTotal,
        'mcqCorrect': mcqCorrect,
        'mcqTotal': mcqTotal,
        'status': gradedAnswers.any((a) => a['status'] == 'pending_grading') 
            ? 'pending_grading' 
            : 'graded',
        'submittedAt': FieldValue.serverTimestamp(),
      };

      String newSubmissionId;
      
      if (existingSubmission.docs.isNotEmpty) {
        // Update existing submission
        newSubmissionId = existingSubmission.docs.first.id;
        await FirebaseFirestore.instance
            .collection('quiz_submissions')
            .doc(newSubmissionId)
            .update({
          ...submissionData,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new submission
        final docRef = await FirebaseFirestore.instance.collection('quiz_submissions').add({
          ...submissionData,
          'createdAt': FieldValue.serverTimestamp(),
        });
        newSubmissionId = docRef.id;
      }

      if (mounted) {
        setState(() {
          _isSubmitted = true;
          _submissionId = newSubmissionId;
          _submissionData = submissionData;
        });
        
        // Show score summary / 显示分数摘要
        String message = "Quiz submitted successfully! 🎉";
        if (mcqTotal > 0) {
          message += "\nMCQ Score: $mcqCorrect/$mcqTotal correct";
        }
        final pendingCount = gradedAnswers.where((a) => a['status'] == 'pending_grading').length;
        if (pendingCount > 0) {
          message += "\n$pendingCount short answer(s) pending teacher grading.";
        } else if (shortAnswerTotal > 0) {
          message += "\nAll questions graded! Total: $totalScore/$maxTotalScore";
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
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
      appBar: AppBar(
        title: Text(quizTitle),
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
            
            // View Results Button (after submission)
            if (_isSubmitted)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // If we don't have submission data, fetch it first
                    if (_submissionId == null || _submissionData == null) {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) return;
                      
                      final submission = await FirebaseFirestore.instance
                          .collection('quiz_submissions')
                          .where('quizId', isEqualTo: widget.quizId)
                          .where('studentId', isEqualTo: user.uid)
                          .limit(1)
                          .get();
                      
                      if (submission.docs.isNotEmpty) {
                        _submissionId = submission.docs.first.id;
                        _submissionData = submission.docs.first.data();
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not load submission data')),
                          );
                        }
                        return;
                      }
                    }
                    
                    if (mounted && _submissionId != null && _submissionData != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StudentQuizResultPage(
                            submissionId: _submissionId!,
                            submissionData: _submissionData!,
                            quizData: widget.quizData,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.assessment, color: Colors.white),
                  label: const Text(
                    "VIEW RESULTS",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    // Get or create controller
    if (!_shortAnswerControllers.containsKey(questionIndex)) {
      _shortAnswerControllers[questionIndex] = TextEditingController(
        text: _answers[questionIndex] as String? ?? '',
      );
    }
    
    final controller = _shortAnswerControllers[questionIndex]!;

    return TextField(
      enabled: !_isSubmitted,
      maxLines: 4,
      controller: controller,
      onChanged: (value) {
        _answers[questionIndex] = value;
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
