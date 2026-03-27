import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Service for auto-grading Short Answer questions using Groq API
class QuizGradingService {
  static const int _maxRetries = 2;
  static const int _shortAnswerMaxScore = 2; // 2 marks per short answer

  /// Grade a single Short Answer question
  /// 
  /// Returns: Map with 'score' (0-2), 'feedback' (String), 'status' ('graded' or 'pending_grading')

  Future<Map<String, dynamic>> gradeShortAnswer({
    required String question,
    required String studentAnswer,
    required String sampleAnswer,
    String? quizTitle,
    String? subject,
  }) async {
    // Build context for the AI
    String contextPrompt = _buildGradingPrompt(
      question: question,
      studentAnswer: studentAnswer,
      sampleAnswer: sampleAnswer,
      quizTitle: quizTitle,
      subject: subject,
    );

    // Retry logic
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final result = await _callGroqAPI(contextPrompt);
        
        if (result != null) {
          return {
            'score': result['score'],
            'feedback': result['feedback'],
            'status': 'graded',
          };
        }
      } catch (e) {
        print('QuizGradingService: Attempt ${attempt + 1} failed: $e');
        
        // If last attempt, return pending_grading
        if (attempt == _maxRetries) {
          return {
            'score': null,
            'feedback': null,
            'status': 'pending_grading',
          };
        }
        
        // Wait before retry (exponential backoff)
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }

    // Fallback to pending_grading
    return {
      'score': null,
      'feedback': null,
      'status': 'pending_grading',
    };
  }

  /// Build the prompt for Groq API
  String _buildGradingPrompt({
    required String question,
    required String studentAnswer,
    required String sampleAnswer,
    String? quizTitle,
    String? subject,
  }) {
    String context = '';
    if (quizTitle != null) context += 'Quiz: $quizTitle\n';
    if (subject != null) context += 'Subject: $subject\n';
    
    return '''You are an expert teacher grading a student's short answer question based on SEMANTIC MEANING, not exact wording.

Question: $question

Reference Answer: $sampleAnswer

Student's Answer: $studentAnswer

IMPORTANT GRADING PRINCIPLE: Grade based on MEANING, not exact words.
- If the student's answer has the SAME MEANING as the reference answer, give FULL marks (2).
- Different wording with same meaning = FULL marks (2).

Examples of SAME MEANING (all should get 2 marks):
- Reference: "China" → Student: "Country China" ✓ (same meaning)
- Reference: "China" → Student: "The answer is China" ✓ (same meaning)
- Reference: "Photosynthesis" → Student: "The process is photosynthesis" ✓ (same meaning)
- Reference: "1945" → Student: "The year 1945" ✓ (same meaning)

Scoring:
- 2 marks: Answer has the SAME MEANING as reference (even if worded differently)
- 1 mark: Answer is PARTIALLY correct (missing key info or has minor errors)
- 0 marks: Answer is WRONG or completely irrelevant

Respond in JSON format only:
{
  "score": <0, 1, or 2>,
  "feedback": "<brief feedback>"
}''';
  }

  /// Call Groq API
  Future<Map<String, dynamic>?> _callGroqAPI(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.groqApiUrl),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${ApiConfig.groqApiKey}",
        },
        body: jsonEncode({
          "model": ApiConfig.gradingModel,
          "messages": [
            {
              "role": "system",
              "content": "You are an expert teacher grading student answers based on SEMANTIC MEANING, not exact wording. If the student's answer means the same thing as the reference answer, give full marks. Always respond in valid JSON format only."
            },
            {
              "role": "user",
              "content": prompt
            }
          ],
          "temperature": 0.3, // Lower temperature for more consistent grading
        }),
      ).timeout(
        const Duration(seconds: 30), // 30 second timeout
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        
        // Parse JSON from response
        try {
          // Sometimes the response might have markdown code blocks
          String cleanedContent = content.trim();
          if (cleanedContent.startsWith('```json')) {
            cleanedContent = cleanedContent.replaceFirst('```json', '').replaceFirst('```', '').trim();
          } else if (cleanedContent.startsWith('```')) {
            cleanedContent = cleanedContent.replaceFirst('```', '').replaceFirst('```', '').trim();
          }
          
          final result = jsonDecode(cleanedContent) as Map<String, dynamic>;
          
          // Validate and normalize score
          int score = (result['score'] as num?)?.toInt() ?? 0;
          if (score < 0) score = 0;
          if (score > _shortAnswerMaxScore) score = _shortAnswerMaxScore;
          
          String feedback = result['feedback']?.toString() ?? 'No feedback provided.';
          
          return {
            'score': score,
            'feedback': feedback,
          };
        } catch (e) {
          print('QuizGradingService: Failed to parse JSON from response: $e');
          print('Response content: $content');
          return null;
        }
      } else {
        print('QuizGradingService: API error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      print('QuizGradingService: Network error: $e');
      rethrow;
    }
  }

  /// Get max score for short answer
  static int getShortAnswerMaxScore() => _shortAnswerMaxScore;
}
