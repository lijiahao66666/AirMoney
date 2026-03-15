import '../core/constants.dart';
import '../data/models/consult_session.dart';
import 'api_service.dart';
import 'auth_service.dart';

String _getCurrentDateInfo() {
  final now = DateTime.now();
  final weekday = ['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1];
  return '${now.year}年${now.month}月${now.day}日（周$weekday）';
}

String _normalizeCategoryText(String text) {
  return text
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[^0-9A-Za-z\u4e00-\u9fff]'), '');
}

String? _pickCategoryFromText(String? text, Iterable<String> categories) {
  if (text == null) return null;
  final normalized = _normalizeCategoryText(text);
  if (normalized.isEmpty) return null;
  for (final category in categories) {
    final normalizedCategory = _normalizeCategoryText(category);
    if (normalizedCategory.isEmpty) continue;
    if (normalized == normalizedCategory ||
        normalized.contains(normalizedCategory) ||
        normalizedCategory.contains(normalized)) {
      return category;
    }
  }
  return null;
}

MapEntry<String, double>? _findRecentCategoryAmount(
  Map<String, double> totals,
  String category,
) {
  final direct = totals[category];
  if (direct != null && direct > 0) {
    return MapEntry(category, direct);
  }
  final normalizedTarget = _normalizeCategoryText(category);
  if (normalizedTarget.isEmpty) return null;

  String? matchedKey;
  var sum = 0.0;
  for (final entry in totals.entries) {
    final normalizedKey = _normalizeCategoryText(entry.key);
    if (normalizedKey.isEmpty) continue;
    final matched =
        normalizedKey == normalizedTarget ||
        normalizedKey.contains(normalizedTarget) ||
        normalizedTarget.contains(normalizedKey);
    if (!matched) continue;
    matchedKey ??= entry.key;
    sum += entry.value;
  }

  if (sum <= 0) return null;
  return MapEntry(matchedKey ?? category, sum);
}

Future<String?> classifyPurchaseIntentByAi(String userText) async {
  final text = userText.trim();
  if (text.isEmpty) return null;

  try {
    final response = await ApiService.chatCompletions(
      messages: <Map<String, String>>[
        <String, String>{
          'role': 'user',
          'content': '''用户说想买/想花：$text

请从以下分类中只返回一个分类名：餐饮、交通、购物、娱乐、居家、医疗、教育、其他。
只回复分类名，不要解释。''',
        },
      ],
      authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
    );

    final cleaned = response.trim().replaceAll(RegExp(r'[。，“”‘’`~\s]+'), '');
    final picked = _pickCategoryFromText(
      cleaned,
      AppConstants.expenseCategories,
    );
    if (picked != null) return picked;

    return _pickCategoryFromText(response, AppConstants.expenseCategories);
  } catch (_) {
    return null;
  }
}

Stream<ConsultStreamChunk> consultStream({
  required List<Map<String, String>> conversationHistory,
  Map<String, double>? recentCategorySpending,
  bool enableAgentSteps = true,
  String? intentAnalysisTargetText,
  String? preclassifiedIntentCategory,
}) async* {
  final dateInfo = _getCurrentDateInfo();
  Map<String, double>? filteredSpending;
  const stepIntent = '分析购买意图';
  const stepRecent = '同类近30天支出';

  final userMessages = conversationHistory.where(
    (x) => (x['role'] ?? '') == 'user',
  );
  final firstUserContent = userMessages.isEmpty
      ? null
      : (userMessages.first['content'] ?? '');
  final analysisTarget = (intentAnalysisTargetText ?? firstUserContent ?? '')
      .trim();
  final needsAgentSteps = enableAgentSteps && analysisTarget.isNotEmpty;

  if (needsAgentSteps) {
    yield ConsultStreamChunk(
      agentSteps: <AgentStep>[const AgentStep(stepIntent)],
    );

    final category =
        preclassifiedIntentCategory ??
        await classifyPurchaseIntentByAi(analysisTarget);

    if (category != null) {
      MapEntry<String, double>? matched;
      if (recentCategorySpending != null && recentCategorySpending.isNotEmpty) {
        matched = _findRecentCategoryAmount(recentCategorySpending, category);
      }

      if (matched != null && matched.value > 0) {
        filteredSpending = <String, double>{matched.key: matched.value};
        final amountText = matched.value >= 1000
            ? '${(matched.value / 1000).toStringAsFixed(1)}k'
            : matched.value.toStringAsFixed(0);

        yield ConsultStreamChunk(
          agentSteps: <AgentStep>[
            AgentStep(stepIntent, category),
            AgentStep(stepRecent, '${matched.key} ¥$amountText'),
          ],
        );
      } else {
        yield ConsultStreamChunk(
          agentSteps: <AgentStep>[
            AgentStep(stepIntent, category),
            const AgentStep(stepRecent, '无支出'),
          ],
        );
      }
    } else {
      yield ConsultStreamChunk(
        agentSteps: <AgentStep>[const AgentStep(stepIntent, '未识别，跳过')],
      );
    }
  }

  final userInstruction =
      '''【角色】你是"该不该花"咨询智能体，像朋友一样聊天，可以有一点幽默。
【当前日期】$dateInfo
【最终目标】尽量帮助用户不买，或者延迟购买；如果确实要买，也尽量降级和控预算。
【对话方式】自由发挥，不要按固定问答模板盘问；先回应用户当下的情绪和诉求，再自然推进到建议。
【建议方向】优先考虑：不买 > 延迟买（给等待天数和触发条件） > 替代/二手/降级 > 必买时给预算上限。
【避免偏题】除非用户明确要参数建议，不主动展开配置评测、版本比较，也不要反问"买哪个版本"。
【联网搜索】如需查询实时信息（如当前价格、优惠活动、新品发布等），可联网搜索后给出建议。
【输出风格】像朋友聊天，不说教；可以简短、有梗，但不要油腻。
【输出约束】不要输出括号里的动作标签，例如（追问细节）（总结）等。''';

  final messages = <Map<String, String>>[];
  var lastUserIndex = -1;
  for (var i = conversationHistory.length - 1; i >= 0; i--) {
    if ((conversationHistory[i]['role'] ?? '') == 'user') {
      lastUserIndex = i;
      break;
    }
  }

  for (var i = 0; i < conversationHistory.length; i++) {
    final message = conversationHistory[i];
    final role = message['role'] ?? 'user';
    var content = message['content'] ?? '';

    if (role == 'user') {
      final isFirstUser = !conversationHistory
          .take(i)
          .any((x) => (x['role'] ?? '') == 'assistant');
      if (isFirstUser) {
        content = '$userInstruction\n\n---\n【用户说】$content';
      }

      if (i == lastUserIndex &&
          filteredSpending != null &&
          filteredSpending.isNotEmpty) {
        content += '\n\n[近期相关支出] $filteredSpending';
      }
    }

    messages.add(<String, String>{'role': role, 'content': content});
  }

  if (messages.isEmpty) {
    messages.add(<String, String>{
      'role': 'user',
      'content': '$userInstruction\n\n---\n【用户说】（等待用户输入）',
    });
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
  final List<AgentStep>? agentSteps;

  ConsultStreamChunk({
    this.content = '',
    this.reasoningContent,
    this.isReasoning = false,
    this.isComplete = false,
    this.pointsBalance,
    this.agentSteps,
  });
}
