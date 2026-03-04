/// 账单类型：支出 / 收入
enum BillType {
  expense,
  income,
}

extension BillTypeExt on BillType {
  String get value => this == BillType.expense ? 'expense' : 'income';
  bool get isExpense => this == BillType.expense;
}

class Bill {
  final int? id;
  final double amount;
  final String category;
  final String note;
  final String payMethod;
  final DateTime date;
  final DateTime createdAt;
  /// 支出(expense) 或 收入(income)
  final BillType type;

  Bill({
    this.id,
    required this.amount,
    required this.category,
    this.note = '',
    this.payMethod = '其他',
    required this.date,
    DateTime? createdAt,
    this.type = BillType.expense,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isExpense => type == BillType.expense;
  bool get isIncome => type == BillType.income;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'amount': amount,
      'category': category,
      'note': note,
      'pay_method': payMethod,
      'date': date.toIso8601String().substring(0, 10),
      'created_at': createdAt.toIso8601String(),
      'type': type.value,
    };
  }

  factory Bill.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String? ?? 'expense';
    final t = typeStr == 'income' ? BillType.income : BillType.expense;
    return Bill(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String,
      note: map['note'] as String? ?? '',
      payMethod: map['pay_method'] as String? ?? '其他',
      date: DateTime.parse(map['date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      type: t,
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
    BillType? type,
  }) {
    return Bill(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      note: note ?? this.note,
      payMethod: payMethod ?? this.payMethod,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
    );
  }
}
