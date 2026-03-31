/// Centralized API configuration
class ApiConfig {
  // Groq API Key - Used for both Chatbot and Quiz Grading
  // For production, move this to environment variables
  static const String groqApiKey = '';
  
  static const String groqApiUrl = 'https://api.groq.com/openai/v1/chat/completions';
  
  // Model for Chatbot (fast, free)
  static const String chatbotModel = 'llama-3.1-8b-instant';
  
  // Model for Quiz Grading (better quality for grading)
  static const String gradingModel = 'llama-3.1-8b-instant'; // Can switch to 'llama-3.1-70b-versatile' if needed
}
