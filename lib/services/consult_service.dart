import 'api_service.dart';
import 'auth_service.dart';

/// 咨询：流式多轮对话，思考模型 + 搜索增强
/// 提示词要求：像对话一样一次只问一个问题，不要一次抛出多个问题
Stream<ConsultStreamChunk> consultStream({
  required List<Map<String, String>> conversationHistory,
  Map<String, double>? recentCategorySpending,
}) async* {
  // system 不起作用，全部放入 user 中
  const userInstruction = '''【你的角色】你是「哎呀，钱！」的买前咨询智能体，和用户像朋友一样聊「该不该花这笔钱」，不是在填表或按清单提问。

【核心任务】围绕「值不值得买」讨论。可探索：用途、有无替代、不买会怎样、是否必须马上买、预算等，但顺序和取舍灵活应变，根据用户回答决定下一句聊什么。

【反应优先】每次回复先对用户上一句话做反应（理解、认同、追问细节），再自然过渡到新话题。不要用户一答完立刻跳下一题，要像真人聊天一样有来有回。

【禁止】不要机械地一问一答。不要只介绍产品功能、参数、价格。不要一次抛出多个问题。

【风格】自然、有来有回，可以有小幽默和简短评价。敢于说「可以不买」「再等等」。不推销、不讨好。''';

  final messages = <Map<String, String>>[];
  for (var i = 0; i < conversationHistory.length; i++) {
    final m = conversationHistory[i];
    final role = m['role'] ?? 'user';
    var content = m['content'] ?? '';
    if (role == 'user') {
      final isFirstUser = !conversationHistory.take(i).any((x) => (x['role'] ?? '') == 'assistant');
      if (isFirstUser) {
        content = '$userInstruction\n\n---\n【用户说】$content';
      }
      if (i == conversationHistory.length - 1 &&
          recentCategorySpending != null &&
          recentCategorySpending.isNotEmpty) {
        content += '\n\n[附加：近期同类支出] $recentCategorySpending';
      }
    }
    messages.add({'role': role, 'content': content});
  }
  if (messages.isEmpty) {
    messages.add({'role': 'user', 'content': '$userInstruction\n\n---\n【用户说】（等待用户输入）'});
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
