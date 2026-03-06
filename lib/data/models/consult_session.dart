/// 买前咨询会话
class ConsultSession {
  final String id;
  final String title; // 首条用户消息摘要，用于列表展示
  final List<ConsultMessage> messages;
  final DateTime updatedAt;

  ConsultSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });

  ConsultSession copyWith({
    String? id,
    String? title,
    List<ConsultMessage>? messages,
    DateTime? updatedAt,
  }) =>
      ConsultSession(
        id: id ?? this.id,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static ConsultSession fromJson(Map<String, dynamic> json) => ConsultSession(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '新对话',
        messages: (json['messages'] as List<dynamic>?)
                ?.map((e) => ConsultMessage.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// 智能体步骤（分析意图、查支出等，可展示）
class AgentStep {
  final String label;
  final String? result;

  const AgentStep(this.label, [this.result]);

  Map<String, dynamic> toJson() => {'label': label, if (result != null) 'result': result};
  static AgentStep fromJson(Map<String, dynamic> j) => AgentStep(
        j['label'] as String? ?? '',
        j['result'] as String?,
      );
}

class ConsultMessage {
  final String role; // user | assistant
  final String content;
  final String? reasoning; // 思考过程，仅 assistant
  final List<AgentStep>? agentSteps; // 智能体步骤，仅 assistant 首条

  ConsultMessage({required this.role, required this.content, this.reasoning, this.agentSteps});

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (reasoning != null && reasoning!.isNotEmpty) 'reasoning': reasoning,
        if (agentSteps != null && agentSteps!.isNotEmpty)
          'agentSteps': agentSteps!.map((s) => s.toJson()).toList(),
      };

  static ConsultMessage fromJson(Map<String, dynamic> json) => ConsultMessage(
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String? ?? '',
        reasoning: json['reasoning'] as String?,
        agentSteps: (json['agentSteps'] as List<dynamic>?)
            ?.map((e) => AgentStep.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
