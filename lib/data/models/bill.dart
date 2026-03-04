class Bill {
  final int? id;
  final double amount;
  final String category;
  final String note;
  final String payMethod;
  final DateTime date;
  final DateTime createdAt;

  Bill({
    this.id,
    required this.amount,
    required this.category,
    this.note = '',
    this.payMethod = '其他',
    required this.date,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'amount': amount,
      'category': category,
      'note': note,
      'pay_method': payMethod,
      'date': date.toIso8601String().substring(0, 10),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Bill.fromMap(Map<String, dynamic> map) {
    return Bill(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String,
      note: map['note'] as String? ?? '',
      payMethod: map['pay_method'] as String? ?? '其他',
      date: DateTime.parse(map['date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Bill copyWith({
    int? id,
    double? amount,
    String? category,
    String? note,
    String? payMethod,
    DateTime? date,
    DateTime? createdAt,
  }) {
    return Bill(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      note: note ?? this.note,
      payMethod: payMethod ?? this.payMethod,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
