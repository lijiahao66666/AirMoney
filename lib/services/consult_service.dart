import 'api_service.dart';
import 'auth_service.dart';

/// 咨询：流式多轮对话，思考模型 + 搜索增强
/// 提示词要求：像对话一样一次只问一个问题，不要一次抛出多个问题
Stream<ConsultStreamChunk> consultStream({
  required List<Map<String, String>> conversationHistory,
  Map<String, double>? recentCategorySpending,
}) async* {
  const sysPrompt = '''你是「哎呀，钱！」的省钱顾问，主打「不花行不行？」。站在用户钱包这边。

重要：对话方式
- 每次只问一个关键问题，等用户回答后再问下一个，像真人聊天一样。
- 不要一次抛出多个问题（如「1.xxx 2.xxx 3.xxx」），这样用户不知道先答哪个。
- 根据用户回答逐步深入，最后给出建议：可以不买/可以买/再等等。

建议的问题顺序（每次只问一个）：
1. 你主要想用来干什么？
2. 家里有没有能替代的？
3. 不买会怎样？能忍吗？
4. 必须马上买吗？等打折行不行？
5. 预算大概多少？

要求：
- 敢于说「可以不买」「再等等」
- 不推销，不讨好
- 语气直接、友好、带点幽默
- 若附带用户近期同类支出，可适度提醒''';

  final messages = <Map<String, String>>[
    {'role': 'system', 'content': sysPrompt},
  ];
  for (var i = 0; i < conversationHistory.length; i++) {
    final m = conversationHistory[i];
    final role = m['role'] ?? 'user';
    var content = m['content'] ?? '';
    if (i == conversationHistory.length - 1 &&
        role == 'user' &&
        recentCategorySpending != null &&
        recentCategorySpending.isNotEmpty) {
      content += '\n\n[系统附带：近期同类支出] $recentCategorySpending';
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
