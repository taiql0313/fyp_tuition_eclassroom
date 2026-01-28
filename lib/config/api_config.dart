/// Centralized API configuration
/// 集中式 API 配置
class ApiConfig {
  // Groq API Key - Used for both Chatbot and Quiz Grading
  // Groq API 密钥 - 用于聊天机器人和测验评分
  // ⚠️ For production, move this to environment variables
  // ⚠️ 生产环境请将此移至环境变量
  static const String groqApiKey = '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';
  
  static const String groqApiUrl = 'https://api.groq.com/openai/v1/chat/completions';
  
  // Model for Chatbot (fast, free)
  // 聊天机器人使用的模型（快速，免费）
  static const String chatbotModel = 'llama-3.1-8b-instant';
  
  // Model for Quiz Grading (better quality for grading)
  // 测验评分使用的模型（评分质量更好）
  static const String gradingModel = 'llama-3.1-8b-instant'; // Can switch to 'llama-3.1-70b-versatile' if needed
}
