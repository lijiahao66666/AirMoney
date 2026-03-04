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

class ConsultMessage {
  final String role; // user | assistant
  final String content;

  ConsultMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  static ConsultMessage fromJson(Map<String, dynamic> json) => ConsultMessage(
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String? ?? '',
      );
}
