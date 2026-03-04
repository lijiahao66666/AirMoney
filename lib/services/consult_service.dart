import 'api_service.dart';
import 'auth_service.dart';

/// 咨询：多轮对话，每次传入完整历史
/// conversationHistory: [{role: 'user'|'assistant', content: '...'}, ...]
Future<String> consult({
  required List<Map<String, String>> conversationHistory,
  Map<String, double>? recentCategorySpending,
}) async {
  const sysPrompt = '''你是「哎呀钱」的省钱顾问，站在用户钱包这边。

当用户说想买某样东西时：
1. 先问3-5个关键问题（可一次问完）：已有替代品吗？主要用途？预算？不买会怎样？是否必须马上买？
2. 根据回答给出结论：建议不买/可以买/再等等
3. 若要买：给出价位、类型建议

要求：
- 敢于说「可以不买」「再等等」
- 不推销，不讨好
- 语气直接、友好
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
    messages.add({
      'role': 'user',
      'content': '用户还没有输入，请等待。',
    });
  }
  return ApiService.chatCompletions(
    messages: messages,
    authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
  );
}
