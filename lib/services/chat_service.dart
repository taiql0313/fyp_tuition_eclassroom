import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatService {
  // ⚠️ PASTE YOUR NEW GROQ KEY HERE
  static const apiKey = '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';

  static const apiUrl = 'https://api.groq.com/openai/v1/chat/completions';

  Future<String?> sendMessage(String userMessage) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $apiKey",
        },
        body: jsonEncode({
          "model": "llama-3.1-8b-instant", // This model is always free and fast
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