import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Teacher view: Single student's quiz result - view, grade pending, add feedback

class TeacherQuizStudentDetailPage extends StatefulWidget {
  final String quizId;
  final Map<String, dynamic> quizData;
  final String classId;
  final String studentId;
  final String studentName;
  final String studentEmail;
  final Map<String, dynamic>? submission;

  const TeacherQuizStudentDetailPage({
    super.key,
    required this.quizId,
    required this.quizData,
    required this.classId,
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    required this.submission,
  });

  @override
  State<TeacherQuizStudentDetailPage> createState() => _TeacherQuizStudentDetailPageState();
}

class _TeacherQuizStudentDetailPageState extends State<TeacherQuizStudentDetailPage> {
  Map<String, dynamic>? _submissionData;
  late List<Map<String, dynamic>> _answers;
  final _feedbackController = TextEditingController();
  final Map<int, TextEditingController> _pendingScoreControllers = {};
  final Map<int, TextEditingController> _pendingFeedbackControllers = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _submissionData = widget.submission != null ? Map<String, dynamic>.from(widget.submission!) : null;
    _loadFromSubmission(_submissionData);
  }

  void _loadFromSubmission(Map<String, dynamic>? sub) {
    if (sub == null) {
      _answers = [];
      return;
    }

    _feedbackController.text = sub['teacherFeedback']?.toString() ?? '';

    final ansList = sub['answers'] as List<dynamic>? ?? [];
    _answers = ansList.map((a) => Map<String, dynamic>.from(a as Map)).toList();

    for (var c in _pendingScoreControllers.values) c.dispose();
    for (var c in _pendingFeedbackControllers.values) c.dispose();
    _pendingScoreControllers.clear();
    _pendingFeedbackControllers.clear();

    for (int i = 0; i < _answers.length; i++) {
      final a = _answers[i];
      if (a['type'] == 'ShortAnswer' && a['status'] == 'pending_grading') {
        _pendingScoreControllers[i] = TextEditingController(
          text: a['score']?.toString() ?? '0',
        );
        _pendingFeedbackControllers[i] = TextEditingController(
          text: a['teacherFeedback']?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    for (var c in _pendingScoreControllers.values) c.dispose();
    for (var c in _pendingFeedbackControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _saveGrading() async {
    if (_submissionData == null) return;

    setState(() => _isSaving = true);

    try {
      final submissionId = _submissionData!['submissionId'] as String?;
      if (submissionId == null) throw Exception('Submission ID not found');

      // Collect pending answers that teacher graded
      for (int i = 0; i < _answers.length; i++) {
        final a = _answers[i];
        if (a['type'] == 'ShortAnswer' && a['status'] == 'pending_grading') {
          final scoreCtrl = _pendingScoreControllers[i];
          final feedbackCtrl = _pendingFeedbackControllers[i];
          if (scoreCtrl != null) {
            int score = int.tryParse(scoreCtrl.text) ?? 0;
            if (score < 0) score = 0;
            final maxScore = (a['maxScore'] as num?)?.toInt() ?? 2;
            if (score > maxScore) score = maxScore;
            _answers[i]['score'] = score;
            _answers[i]['status'] = 'graded';
            _answers[i]['teacherFeedback'] = feedbackCtrl?.text ?? '';
          }
        }
      }

      // Recalculate total score
      int totalScore = 0;
      int maxTotalScore = 0;
      for (var a in _answers) {
        final score = a['score'];
        final max = (a['maxScore'] as num?)?.toInt() ?? 2;
        maxTotalScore += max;
        if (score != null) totalScore += (score as num).toInt();
      }

      final allGraded = !_answers.any((a) => a['status'] == 'pending_grading');

      await FirebaseFirestore.instance
          .collection('quiz_submissions')
          .doc(submissionId)
          .update({
        'answers': _answers,
        'totalScore': totalScore,
        'maxTotalScore': maxTotalScore,
        'status': allGraded ? 'graded' : 'pending_grading',
        'teacherFeedback': _feedbackController.text.trim(),
        'gradedBy': 'teacher',
        'gradedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        final doc = await FirebaseFirestore.instance
            .collection('quiz_submissions')
            .doc(submissionId)
            .get();
        if (doc.exists) {
          setState(() {
            _submissionData = {...doc.data()!, 'submissionId': doc.id};
            _loadFromSubmission(_submissionData);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submissionData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: Text(widget.studentName, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1458A3),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pending_actions, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Not Submitted',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              Text(
                'This student has not submitted the quiz yet.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final questions = widget.quizData['questions'] as List<dynamic>? ?? [];
    final totalScore = _submissionData!['totalScore'] ?? 0;
    final maxTotalScore = _submissionData!['maxTotalScore'] ?? 0;
    final percentage = maxTotalScore > 0 ? (totalScore / maxTotalScore * 100).round() : 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(widget.studentName, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1458A3),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_hasPendingToGrade() || _feedbackController.text != (_submissionData?['teacherFeedback']?.toString() ?? ''))
            TextButton(
              onPressed: _isSaving ? null : _saveGrading,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('SAVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Score card
            _buildScoreCard(totalScore, maxTotalScore, percentage),
            const SizedBox(height: 24),

            // Teacher feedback section
            const Text(
              'Your Feedback to Student',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _feedbackController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add feedback for this student...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),

            // Answers
            const Text(
              'Student Answers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 16),

            ...(_answers.asMap().entries.map((entry) {
              final i = entry.key;
              final answer = entry.value;
              final question = i < questions.length ? questions[i] as Map<String, dynamic> : <String, dynamic>{};
              return _buildAnswerCard(i, answer, question);
            })),
          ],
        ),
      ),
    );
  }

  bool _hasPendingToGrade() {
    return _answers.any((a) => a['type'] == 'ShortAnswer' && a['status'] == 'pending_grading');
  }

  Widget _buildScoreCard(int totalScore, int maxTotalScore, int percentage) {
    Color scoreColor = percentage >= 80
        ? Colors.green
        : percentage >= 60
            ? Colors.blue
            : percentage >= 40
                ? Colors.orange
                : Colors.red;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scoreColor.withOpacity(0.8), scoreColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: scoreColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$percentage%', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: scoreColor)),
                Text('$totalScore/$maxTotalScore', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (widget.studentEmail.isNotEmpty)
                  Text(
                    widget.studentEmail,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (_hasPendingToGrade())
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Pending grading',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerCard(int index, Map<String, dynamic> answer, Map<String, dynamic> question) {
    final type = answer['type'] as String? ?? 'MCQ';
    final isCorrect = answer['isCorrect'] as bool? ?? false;
    final score = answer['score'];
    final maxScore = (answer['maxScore'] as num?)?.toInt() ?? 2;
    final status = answer['status'] as String?;
    final questionText = question['question'] as String? ?? 'Question ${index + 1}';

    Color cardColor;
    IconData statusIcon;
    String statusText;

    if (type == 'MCQ') {
      cardColor = isCorrect ? Colors.green.shade50 : Colors.red.shade50;
      statusIcon = isCorrect ? Icons.check_circle : Icons.cancel;
      statusText = isCorrect ? 'Correct' : 'Incorrect';
    } else {
      if (status == 'pending_grading') {
        cardColor = Colors.orange.shade50;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Grade this';
      } else {
        cardColor = Colors.blue.shade50;
        statusIcon = Icons.grading;
        statusText = score != null ? '$score/$maxScore' : 'Graded';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: Text('Q${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: type == 'MCQ' ? Colors.orange.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    type == 'MCQ' ? 'MCQ' : 'Short Answer',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: type == 'MCQ' ? Colors.orange.shade700 : Colors.green.shade700),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(statusIcon, size: 18, color: status == 'pending_grading' ? Colors.orange : Colors.blue),
                    const SizedBox(width: 4),
                    Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: status == 'pending_grading' ? Colors.orange : Colors.blue)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(questionText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(height: 12),

            if (type == 'MCQ')
              _buildMCQDisplay(answer, question)
            else
              _buildShortAnswerDisplay(index, answer, question, maxScore),

            if (score != null && type != 'ShortAnswer')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
                      child: Text('Score: $score/$maxScore', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMCQDisplay(Map<String, dynamic> answer, Map<String, dynamic> question) {
    final options = question['options'] as List<dynamic>? ?? [];
    final studentAnswer = answer['studentAnswer'] as int?;
    final correctAnswer = answer['correctAnswer'] as int?;
    final labels = ['A', 'B', 'C', 'D'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: studentAnswer == correctAnswer ? Colors.green : Colors.red, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: studentAnswer == correctAnswer ? Colors.green : Colors.red, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    studentAnswer != null && studentAnswer < labels.length ? labels[studentAnswer] : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Student Answer:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      studentAnswer != null && studentAnswer < options.length ? options[studentAnswer].toString() : 'No answer',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Icon(studentAnswer == correctAnswer ? Icons.check_circle : Icons.cancel, color: studentAnswer == correctAnswer ? Colors.green : Colors.red),
            ],
          ),
        ),
        if (studentAnswer != correctAnswer && correctAnswer != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green, width: 1)),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      correctAnswer < labels.length ? labels[correctAnswer] : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Correct Answer:', style: TextStyle(fontSize: 11, color: Colors.green)),
                      Text(
                        correctAnswer < options.length ? options[correctAnswer].toString() : 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildShortAnswerDisplay(int index, Map<String, dynamic> answer, Map<String, dynamic> question, int maxScore) {
    final studentAnswer = answer['studentAnswer'] as String? ?? '';
    final aiFeedback = answer['aiFeedback'] as String?;
    final teacherFeedback = answer['teacherFeedback'] as String?;
    final status = answer['status'] as String?;
    final isPending = status == 'pending_grading';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Student Answer:', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(studentAnswer.isNotEmpty ? studentAnswer : 'No answer provided', style: TextStyle(fontSize: 14, color: studentAnswer.isNotEmpty ? Colors.black87 : Colors.grey)),
            ],
          ),
        ),
        if (aiFeedback != null && aiFeedback.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [Icon(Icons.smart_toy, size: 16, color: Colors.blue), SizedBox(width: 4), Text('AI Feedback:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue))]),
                const SizedBox(height: 4),
                Text(aiFeedback, style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ],
            ),
          ),
        if (teacherFeedback != null && teacherFeedback.isNotEmpty && !isPending)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [Icon(Icons.edit_note, size: 16, color: Colors.purple), SizedBox(width: 4), Text('Your Feedback:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple))]),
                const SizedBox(height: 4),
                Text(teacherFeedback, style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ],
            ),
          ),

        // Teacher grading section for pending
        if (isPending) ...[
          const SizedBox(height: 12),
          Text('Grade this answer (0–$maxScore):', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _pendingScoreControllers[index],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '0',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Text('/ $maxScore', style: const TextStyle(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Your feedback:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _pendingFeedbackControllers[index],
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add feedback for this answer...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],

        if (!isPending && answer['score'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
                  child: Text('Score: ${answer['score']}/$maxScore', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
