import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ChatService {
  // Now using centralized API config / 现在使用集中式 API 配置
  static const apiKey = ApiConfig.groqApiKey;
  static const apiUrl = ApiConfig.groqApiUrl;

  Future<String?> sendMessage(String userMessage) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
        },
        body: jsonEncode({
          "model": ApiConfig.chatbotModel, // This model is always free and fast
          "messages": [
            {
              "role": "system",
              "content": "You are a helpful AI Tutor for a Tuition App. Keep answers short."

            },
            {
              "role": "user",
              "content": userMessage
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        return "Error: ${response.statusCode} - ${response.body}";
      }
    } catch (e) {
      return "Network Error: $e";
    }
  }
}