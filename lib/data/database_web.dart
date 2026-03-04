import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/bill.dart';
import 'bill_storage.dart';

BillStorage createBillStorage() => _WebBillStorage();

class _WebBillStorage implements BillStorage {
  static const _key = 'airmoney_bills';

  List<Map<String, dynamic>> _bills = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json != null && json.isNotEmpty) {
        _bills = List<Map<String, dynamic>>.from(
          (jsonDecode(json) as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    } catch (e) {
      debugPrint('[WebBillStorage] load error: $e');
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_bills));
    } catch (e) {
      debugPrint('[WebBillStorage] persist error: $e');
    }
  }

  @override
  Future<int> insert(Bill bill) async {
    await _ensureLoaded();
    final nextId = _bills.isEmpty
        ? 1
        : (_bills.map((m) => m['id'] as int? ?? 0).reduce((a, b) => a > b ? a : b) + 1);
    _bills.add({
      ...bill.toMap(),
      'id': nextId,
    });
    await _persist();
    return nextId;
  }

  @override
  Future<List<Map<String, dynamic>>> query({
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    await _ensureLoaded();
    var list = List<Map<String, dynamic>>.from(_bills);
    if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
      if (where.contains('date')) {
        final startStr = whereArgs.isNotEmpty ? whereArgs[0].toString() : '';
        final endStr = whereArgs.length > 1 ? whereArgs[1].toString() : '';
        list = list.where((m) {
          final d = m['date'] as String? ?? '';
          return (startStr.isEmpty || d.compareTo(startStr) >= 0) &&
              (endStr.isEmpty || d.compareTo(endStr) <= 0);
        }).toList();
      }
    }
    if (orderBy != null) {
      if (orderBy.contains('created_at') && orderBy.contains('DESC')) {
        list.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
      } else if (orderBy.contains('date') && orderBy.contains('DESC')) {
        list.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
      }
    }
    if (limit != null && limit > 0) {
      list = list.take(limit).toList();
    }
    return list;
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? args]) async {
    await _ensureLoaded();
    if (sql.contains('SUM(amount)') && sql.contains('WHERE')) {
      final startStr = args != null && args.isNotEmpty ? args[0].toString() : '';
      final endStr = args != null && args.length > 1 ? args[1].toString() : '';
      double total = 0;
      for (final m in _bills) {
        final d = m['date'] as String? ?? '';
        if ((startStr.isEmpty || d.compareTo(startStr) >= 0) &&
            (endStr.isEmpty || d.compareTo(endStr) <= 0)) {
          total += (m['amount'] as num?)?.toDouble() ?? 0;
        }
      }
      return [{'total': total}];
    }
    if (sql.contains('GROUP BY category')) {
      final startStr = args != null && args.isNotEmpty ? args[0].toString() : '';
      final endStr = args != null && args.length > 1 ? args[1].toString() : '';
      final map = <String, double>{};
      for (final m in _bills) {
        final d = m['date'] as String? ?? '';
        if ((startStr.isEmpty || d.compareTo(startStr) >= 0) &&
            (endStr.isEmpty || d.compareTo(endStr) <= 0)) {
          final cat = m['category'] as String? ?? '其他';
          map[cat] = (map[cat] ?? 0) + ((m['amount'] as num?)?.toDouble() ?? 0);
        }
      }
      return map.entries.map((e) => {'category': e.key, 'total': e.value}).toList();
    }
    return [];
  }
}
