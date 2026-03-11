/// Centralized API configuration
class ApiConfig {
  // Groq API Key - Used for both Chatbot and Quiz Grading
  // For production, move this to environment variables
  static const String groqApiKey = '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';
  
  static const String groqApiUrl = 'https://api.groq.com/openai/v1/chat/completions';
  
  // Model for Chatbot (fast, free)
  static const String chatbotModel = 'llama-3.1-8b-instant';
  
  // Model for Quiz Grading (better quality for grading)
  static const String gradingModel = 'llama-3.1-8b-instant'; // Can switch to 'llama-3.1-70b-versatile' if needed
}
