// lib/ai_server.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// OpenAI Chat Completions API 호출 서비스
class AIService {
  final String? _apiKey = dotenv.maybeGet('LLM_API_KEY');
  final String _apiUrl =
      dotenv.maybeGet('LLM_API_URL') ?? 'https://api.openai.com/v1/chat/completions';
  final String _model = dotenv.maybeGet('LLM_MODEL') ?? 'gpt-4o-mini';

  bool get isEnabled => _apiKey != null && _apiKey!.trim().isNotEmpty;

  /// 오늘 계획/집중/휴식/한줄 피드백 제안
  /// [mood] : 기분 (1~10)
  /// [logs] : 최근 기록 리스트
  Future<String> dailyPlan({
    required int mood,
    required List<Map<String, dynamic>> logs,
  }) async {
    if (!isEnabled) {
      return '⚠️ AI 비활성화: .env 파일에 LLM_API_KEY 설정이 필요합니다.';
    }

    try {
      final prompt = '''
너는 "학생 맞춤형 집중 코치"야.
- mood: $mood (1=매우 피곤, 10=매우 에너지 넘침)
- 최근 집중 기록: ${jsonEncode(logs)}

학생의 오늘 첫 세트 집중/휴식 계획을 제안하고, 동기부여 한 줄 피드백을 줘.
출력은 간결하게 (2~3줄).
''';

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': '너는 학생의 집중 학습을 돕는 코치야.'},
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 150,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['choices']?[0]?['message']?['content'];
        return (text != null && text.trim().isNotEmpty)
            ? text.trim()
            : 'AI 응답이 비어 있습니다.';
      } else if (response.statusCode == 429) {
        return '⚠️ 요청이 많아 잠시 후 다시 시도하세요. (429 Too Many Requests)';
      } else {
        return '⚠️ 오류 발생: ${response.statusCode} ${response.reasonPhrase}';
      }
    } catch (e) {
      return '⚠️ 네트워크 오류: $e';
    }
  }
}
