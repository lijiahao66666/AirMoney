import '../data/models/bill.dart';
import 'api_service.dart';
import 'auth_service.dart';

String _getCurrentDateInfo() {
  final now = DateTime.now();
  final weekday = ['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1];
  return '${now.year}年${now.month}月${now.day}日（周$weekday）';
}

/// 单次分析：从最近记录中选择一笔进行深度分析
Future<String> analyzeSingleBill(
  Bill bill, {
  Map<String, double>? categoryTotals7d,
}) async {
  final dateInfo = _getCurrentDateInfo();
  final sysPrompt =
      '''你是「哎呀，钱！」的消费分析顾问。主打「少花点，存多点」。

当前日期：$dateInfo

输入：用户的单笔账单数据

任务：判断这笔是否偏冲动/不必要，给1-2条简短建议和1个反思问题。

要求：
- 语气温和、不指责、带点幽默
- 建议具体、可操作
- 控制字数约100字
- 用「建议」「可以尝试」等措辞
- 涉及时间判断时，以当前日期为准
- 如需查询实时信息（如当前物价、优惠活动等），可联网搜索后给出建议''';

  final catInfo = categoryTotals7d != null && categoryTotals7d.isNotEmpty
      ? '\n该分类近7天汇总：$categoryTotals7d'
      : '';
  final userContent =
      '''本次记录：
- 金额：${bill.amount}元
- 分类：${bill.category}
- 备注：${bill.note.isEmpty ? '无' : bill.note}
- 日期：${bill.date.toString().substring(0, 10)}
$catInfo

请给出分析、建议和反思问题。''';

  final messages = [
    {'role': 'system', 'content': sysPrompt},
    {'role': 'user', 'content': userContent},
  ];
  return ApiService.chatCompletions(
    messages: messages,
    authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
  );
}

/// 周期分析
Future<String> analyzePeriod({
  required List<Bill> bills,
  required double total,
  required Map<String, double> categoryTotals,
  required String periodLabel,
}) async {
  final dateInfo = _getCurrentDateInfo();
  final sysPrompt =
      '''你是「哎呀，钱！」的消费分析顾问。主打「少花点，存多点」。

当前日期：$dateInfo

输入：用户一段时间内的账单数据及统计

任务：概括消费特点、指出可能的浪费点、给2-3条可执行建议，帮用户反省反省。

要求：
- 语气温和、不指责、带点幽默
- 建议具体、可操作
- 控制字数约200字
- 用「建议」「可以尝试」等措辞
- 涉及时间判断时，以当前日期为准
- 如需查询实时信息（如当前物价、优惠活动等），可联网搜索后给出建议''';

  final catLines = categoryTotals.entries
      .map((e) => '- ${e.key} ${e.value.toStringAsFixed(0)}元')
      .join('\n');
  final userContent =
      '''$periodLabel 支出统计：
- 总额：${total.toStringAsFixed(0)}元
- 分类分布：
$catLines

最近几笔：${bills.take(10).map((b) => '${b.date.toString().substring(0, 10)} ${b.category} ${b.amount}元${b.note.isNotEmpty ? " (${b.note})" : ""}').join('；')}

请给出分析报告。''';

  final messages = [
    {'role': 'system', 'content': sysPrompt},
    {'role': 'user', 'content': userContent},
  ];
  return ApiService.chatCompletions(
    messages: messages,
    authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
  );
}
