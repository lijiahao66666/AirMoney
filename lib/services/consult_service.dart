import 'api_service.dart';
import 'auth_service.dart';

/// 咨询：流式多轮对话，思考模型 + 搜索增强
/// 提示词要求：像对话一样一次只问一个问题，不要一次抛出多个问题
Stream<ConsultStreamChunk> consultStream({
  required List<Map<String, String>> conversationHistory,
  Map<String, double>? recentCategorySpending,
}) async* {
  const sysPrompt = '''你是「哎呀，钱！」的买前咨询顾问，核心任务是帮用户分析「该不该花这笔钱」。

重点：用户说想买某物时，你必须围绕「值不值得买」进行提问和分析，而不是只给产品介绍。
- 可以先简单了解产品（功能、价位等），但紧接着要通过提问帮用户理性思考、做购买决策。
- 若涉及产品信息，应服务于「值不值得买」的分析，而非单纯科普。

对话方式：
- 每次只问一个关键问题，等用户回答后再问下一个，不要一次抛出多个问题。
- 建议提问顺序：用途→有无替代→不买会怎样→是否必须马上买→预算。
- 根据用户回答逐步深入，最终给出明确建议：可以不买/可以买/再等等。

要求：
- 敢于说「可以不买」「再等等」，不推销、不讨好。语气直接、友好、带点幽默。
- 若附带用户近期同类支出，可适度提醒。''';

  final messages = <Map<String, String>>[
    {'role': 'system', 'content': sysPrompt},
  ];
  for (var i = 0; i < conversationHistory.length; i++) {
    final m = conversationHistory[i];
    final role = m['role'] ?? 'user';
    var content = m['content'] ?? '';
    // 首条用户消息前加「买前咨询」约束，提高模型遵循率（system 有时被弱化）
    if (i == conversationHistory.length - 1 && role == 'user') {
      final isFirstUser = !conversationHistory.take(i).any((m) => (m['role'] ?? '') == 'assistant');
      if (isFirstUser) {
        content = '[买前咨询：请围绕「值不值得买」提问分析，不要只介绍产品。每次只问一个问题。]\n\n$content';
      }
      if (recentCategorySpending != null && recentCategorySpending.isNotEmpty) {
        content += '\n\n[系统附带：近期同类支出] $recentCategorySpending';
      }
    }
    messages.add({'role': role, 'content': content});
  }
  if (messages.length == 1) {
    messages.add({'role': 'user', 'content': '用户还没有输入，请等待。'});
  }

  final stream = ApiService.chatCompletionsStream(
    messages: messages,
    authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
  );

  await for (final chunk in stream) {
    yield ConsultStreamChunk(
      content: chunk.content,
      reasoningContent: chunk.reasoningContent,
      isReasoning: chunk.isReasoning,
      isComplete: chunk.isComplete,
      pointsBalance: chunk.pointsBalance,
    );
  }
}

class ConsultStreamChunk {
  final String content;
  final String? reasoningContent;
  final bool isReasoning;
  final bool isComplete;
  final int? pointsBalance;

  ConsultStreamChunk({
    required this.content,
    this.reasoningContent,
    this.isReasoning = false,
    this.isComplete = false,
    this.pointsBalance,
  });
}
