import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StudentQuizResultPage extends StatelessWidget {
  final String submissionId;
  final Map<String, dynamic> submissionData;
  final Map<String, dynamic> quizData;

  const StudentQuizResultPage({
    super.key,
    required this.submissionId,
    required this.submissionData,
    required this.quizData,
  });

  @override
  Widget build(BuildContext context) {
    final answers = submissionData['answers'] as List<dynamic>? ?? [];
    final questions = quizData['questions'] as List<dynamic>? ?? [];
    final totalScore = submissionData['totalScore'] ?? 0;
    final maxTotalScore = submissionData['maxTotalScore'] ?? 0;
    final mcqCorrect = submissionData['mcqCorrect'] ?? 0;
    final mcqTotal = submissionData['mcqTotal'] ?? 0;
    final status = submissionData['status'] ?? 'graded';
    final quizTitle = quizData['title'] ?? 'Quiz Result';
    final teacherFeedback = submissionData['teacherFeedback'] as String?;

    // Calculate percentage
    final percentage = maxTotalScore > 0 ? (totalScore / maxTotalScore * 100).round() : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Result'),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Score Card / 分数卡片
            _buildScoreCard(
              quizTitle: quizTitle,
              totalScore: totalScore,
              maxTotalScore: maxTotalScore,
              percentage: percentage,
              mcqCorrect: mcqCorrect,
              mcqTotal: mcqTotal,
              status: status,
            ),
            const SizedBox(height: 24),

            // Teacher's general feedback
            if (teacherFeedback != null && teacherFeedback.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.edit_note, size: 20, color: Colors.purple),
                        SizedBox(width: 8),
                        Text(
                          "Teacher's Feedback",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      teacherFeedback,
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ],
                ),
              ),

            // Results Header
            const Text(
              'Your Answers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // Answer Cards
            ...answers.asMap().entries.map((entry) {
              final index = entry.key;
              final answer = entry.value as Map<String, dynamic>;
              final question = index < questions.length
                  ? questions[index] as Map<String, dynamic>
                  : <String, dynamic>{};
              return _buildAnswerCard(index, answer, question);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard({
    required String quizTitle,
    required int totalScore,
    required int maxTotalScore,
    required int percentage,
    required int mcqCorrect,
    required int mcqTotal,
    required String status,
  }) {
    Color scoreColor;
    String grade;
    IconData gradeIcon;

    if (percentage >= 80) {
      scoreColor = Colors.green;
      grade = 'Excellent!';
      gradeIcon = Icons.emoji_events;
    } else if (percentage >= 60) {
      scoreColor = Colors.blue;
      grade = 'Good Job!';
      gradeIcon = Icons.thumb_up;
    } else if (percentage >= 40) {
      scoreColor = Colors.orange;
      grade = 'Keep Trying!';
      gradeIcon = Icons.trending_up;
    } else {
      scoreColor = Colors.red;
      grade = 'Need Improvement';
      gradeIcon = Icons.school;
    }

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
          BoxShadow(
            color: scoreColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Quiz Title
          Text(
            quizTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Score Circle
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
                Text(
                  '$totalScore/$maxTotalScore',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Grade
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(gradeIcon, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                grade,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // MCQ Stats
          if (mcqTotal > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'MCQ: $mcqCorrect/$mcqTotal correct',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // Status Badge
          if (status == 'pending_grading')
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_empty, color: Colors.orange, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Short answers pending grading',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
    final maxScore = answer['maxScore'] ?? 10;
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
      // Short Answer
      if (status == 'pending_grading') {
        cardColor = Colors.orange.shade50;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Pending Grading';
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
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                // Question Number
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Q${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: type == 'MCQ' ? Colors.orange.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    type == 'MCQ' ? 'MCQ' : 'Short Answer',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: type == 'MCQ' ? Colors.orange.shade700 : Colors.green.shade700,
                    ),
                  ),
                ),
                const Spacer(),
                // Status
                Row(
                  children: [
                    Icon(
                      statusIcon,
                      size: 18,
                      color: type == 'MCQ'
                          ? (isCorrect ? Colors.green : Colors.red)
                          : (status == 'pending_grading' ? Colors.orange : Colors.blue),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: type == 'MCQ'
                            ? (isCorrect ? Colors.green : Colors.red)
                            : (status == 'pending_grading' ? Colors.orange : Colors.blue),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Question Text
            Text(
              questionText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            // Answer Details
            if (type == 'MCQ') ...[
              _buildMCQAnswer(answer, question),
            ] else ...[
              _buildShortAnswerResult(answer),
            ],

            // Score
            if (score != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Score: $score/$maxScore',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMCQAnswer(Map<String, dynamic> answer, Map<String, dynamic> question) {
    final options = question['options'] as List<dynamic>? ?? [];
    final studentAnswer = answer['studentAnswer'] as int?;
    final correctAnswer = answer['correctAnswer'] as int?;
    final labels = ['A', 'B', 'C', 'D'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Your Answer
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: studentAnswer == correctAnswer ? Colors.green : Colors.red,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: studentAnswer == correctAnswer ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    studentAnswer != null && studentAnswer < labels.length
                        ? labels[studentAnswer]
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your Answer:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      studentAnswer != null && studentAnswer < options.length
                          ? options[studentAnswer].toString()
                          : 'No answer',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Icon(
                studentAnswer == correctAnswer ? Icons.check_circle : Icons.cancel,
                color: studentAnswer == correctAnswer ? Colors.green : Colors.red,
              ),
            ],
          ),
        ),

        // Correct Answer (if wrong)
        if (studentAnswer != correctAnswer && correctAnswer != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      correctAnswer < labels.length ? labels[correctAnswer] : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Correct Answer:',
                        style: TextStyle(fontSize: 11, color: Colors.green),
                      ),
                      Text(
                        correctAnswer < options.length
                            ? options[correctAnswer].toString()
                            : 'Unknown',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
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

  Widget _buildShortAnswerResult(Map<String, dynamic> answer) {
    final studentAnswer = answer['studentAnswer'] as String? ?? '';
    final aiFeedback = answer['aiFeedback'] as String?;
    final teacherFeedback = answer['teacherFeedback'] as String?;
    final status = answer['status'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Student Answer
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Answer:',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                studentAnswer.isNotEmpty ? studentAnswer : 'No answer provided',
                style: TextStyle(
                  fontSize: 14,
                  color: studentAnswer.isNotEmpty ? Colors.black87 : Colors.grey,
                ),
              ),
            ],
          ),
        ),

        // AI Feedback (if available)
        if (aiFeedback != null && aiFeedback.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.smart_toy, size: 16, color: Colors.blue),
                    SizedBox(width: 4),
                    Text(
                      'AI Feedback:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  aiFeedback,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),

        // Teacher Feedback (if available)
        if (teacherFeedback != null && teacherFeedback.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.edit_note, size: 16, color: Colors.purple),
                    SizedBox(width: 4),
                    Text(
                      'Teacher Feedback:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  teacherFeedback,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),

        // Pending Status
        if (status == 'pending_grading')
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.hourglass_empty, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Waiting for grading...',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
