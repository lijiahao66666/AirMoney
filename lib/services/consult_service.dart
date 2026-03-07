import '../core/constants.dart';
import '../data/models/consult_session.dart';
import 'api_service.dart';
import 'auth_service.dart';

String _normalizeCategoryText(String text) {
  return text
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(
        RegExp(r'[，。！？、,.!?:：;；【】\[\]\(\)（）《》“”·\-_\/]'),
        '',
      );
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

/// 让 AI 判断用户购买意图属于哪个支出分类
Future<String?> classifyPurchaseIntentByAi(String userText) async {
  final t = userText.trim();
  if (t.isEmpty) return null;
  try {
    final resp = await ApiService.chatCompletions(
      messages: [
        {
          'role': 'user',
          'content': '''用户说想买/想花：$t

请判断这属于以下哪个支出分类：餐饮、交通、购物、娱乐、居家、医疗、教育、其他。

只回复分类名，不要标点、解释或其他内容。''',
        },
      ],
      authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
    );
    final cleaned = resp.trim().replaceAll(RegExp(r'[。，“”‘’`~\s]+'), '');
    final cat = _pickCategoryFromText(cleaned, AppConstants.expenseCategories);
    if (cat != null) return cat;
    final fallback = _pickCategoryFromText(resp, AppConstants.expenseCategories);
    if (fallback != null) return fallback;
    return null;
  } catch (_) {
    return null;
  }
}

/// 咨询：流式多轮对话，思考模型 + 搜索增强
/// 首条消息时：先展示「分析意图→查支出」步骤，再咨询
Stream<ConsultStreamChunk> consultStream({
  required List<Map<String, String>> conversationHistory,
  Map<String, double>? recentCategorySpending,
  bool enableAgentSteps = true,
  String? intentAnalysisTargetText,
  String? preclassifiedIntentCategory,
}) async* {
  Map<String, double>? filteredSpending;
  final userMsgs = conversationHistory.where(
    (x) => (x['role'] ?? '') == 'user',
  );
  final firstUserContent = userMsgs.isEmpty
      ? null
      : (userMsgs.first['content'] ?? '');
  final analysisTarget = (intentAnalysisTargetText ?? firstUserContent ?? '')
      .trim();
  final needsAgentSteps =
      enableAgentSteps &&
      analysisTarget.isNotEmpty &&
      recentCategorySpending != null &&
      recentCategorySpending.isNotEmpty;

  if (needsAgentSteps) {
    // 步骤1：分析购买意图
    yield ConsultStreamChunk(agentSteps: [const AgentStep('分析购买意图')]);
    final cat =
        preclassifiedIntentCategory ??
        await classifyPurchaseIntentByAi(analysisTarget);

    if (cat != null) {
      final matched = _findRecentCategoryAmount(recentCategorySpending, cat);
      final matchedCategory = matched?.key ?? cat;
      final amount = matched?.value;
      if (amount != null && amount > 0) {
        filteredSpending = {matchedCategory: amount};
        final amountStr = amount >= 1000
            ? '${(amount / 1000).toStringAsFixed(1)}k'
            : amount.toStringAsFixed(0);
        yield ConsultStreamChunk(
          agentSteps: [AgentStep('分析购买意图', cat), AgentStep('同类近30天支出')],
        );
        yield ConsultStreamChunk(
          agentSteps: [
            AgentStep('分析购买意图', cat),
            AgentStep('同类近30天支出', '$matchedCategory ¥$amountStr'),
          ],
        );
      } else {
        yield ConsultStreamChunk(
          agentSteps: [AgentStep('分析购买意图', '$cat（近30天无支出）')],
        );
      }
    } else {
      yield ConsultStreamChunk(
        agentSteps: [const AgentStep('分析购买意图', '未识别，跳过')],
      );
    }
  }

  const userInstruction =
      '''【你的角色】你是「哎呀，钱！」的买前咨询智能体，和用户像朋友一样聊「该不该花这笔钱」，不是在填表或按清单提问。

【核心任务】围绕「值不值得买」讨论。可探索：用途、有无替代、不买会怎样、是否必须马上买、预算等，顺序和取舍灵活应变，根据用户回答决定下一句聊什么。

【反应优先】每次回复先对用户上一句话做反应（理解、认同、追问细节），再自然过渡到新话题。不要用户一答完立刻跳下一题，要像真人聊天一样有来有回。

【近期支出】若下方有「近期相关支出」数据，可自然融入对话（如「你最近在这块花了不少」），仅当确实有助于讨论时提及，不必每次刻意提起。没有数据或数据无关时完全忽略。

【禁止】不要机械地一问一答。不要只介绍产品功能、参数、价格。不要一次抛出多个问题。

【风格】自然、有来有回，可以有小幽默和简短评价。敢于说「可以不买」「再等等」。不推销、不讨好。''';

  const noMetaLabelInstruction =
      '\n\n【输出约束】不要输出任何括号中的“动作/意图标签”，例如（追问细节）、（幽默+理解）、(总结) 等；只输出用户可见的自然回复。';

  final messages = <Map<String, String>>[];
  var lastUserIndex = -1;
  for (var i = conversationHistory.length - 1; i >= 0; i--) {
    if ((conversationHistory[i]['role'] ?? '') == 'user') {
      lastUserIndex = i;
      break;
    }
  }
  for (var i = 0; i < conversationHistory.length; i++) {
    final m = conversationHistory[i];
    final role = m['role'] ?? 'user';
    var content = m['content'] ?? '';
    if (role == 'user') {
      final isFirstUser = !conversationHistory
          .take(i)
          .any((x) => (x['role'] ?? '') == 'assistant');
      if (isFirstUser) {
        content =
            '$userInstruction$noMetaLabelInstruction\n\n---\n【用户说】$content';
      }
      // 将本轮相关支出注入到最新 user 消息，支持中途换话题后重新分析
      if (i == lastUserIndex &&
          filteredSpending != null &&
          filteredSpending.isNotEmpty) {
        content += '\n\n[近期相关支出] $filteredSpending';
      }
    }
    messages.add({'role': role, 'content': content});
  }
  if (messages.isEmpty) {
    messages.add({
      'role': 'user',
      'content':
          '$userInstruction$noMetaLabelInstruction\n\n---\n【用户说】（等待用户输入）',
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
