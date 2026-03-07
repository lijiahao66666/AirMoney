import '../bill_storage.dart';
import '../database.dart';
import '../models/bill.dart';

class BillRepository {
  BillStorage get _storage => createBillStorage();

  Future<int> insert(Bill bill) async {
    return _storage.insert(bill);
  }

  Future<int> updateById(int id, Bill bill) async {
    return _storage.updateById(id, bill);
  }

  Future<int> deleteById(int id) async {
    return _storage.deleteById(id);
  }

  Future<List<Bill>> getBillsInRange(
    DateTime start,
    DateTime end, {
    BillType? type,
  }) async {
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    String where = 'date >= ? AND date <= ?';
    List<dynamic> whereArgs = [startStr, endStr];
    if (type != null) {
      if (type == BillType.expense) {
        where += " AND (type = ? OR type IS NULL OR type = '')";
      } else {
        where += ' AND type = ?';
      }
      whereArgs.add(type.value);
    }
    final maps = await _storage.query(
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date DESC, created_at DESC',
    );
    return maps.map((m) => Bill.fromMap(m)).toList();
  }

  Future<List<Bill>> getRecentBills({int limit = 20}) async {
    final maps = await _storage.query(orderBy: 'created_at DESC', limit: limit);
    return maps.map((m) => Bill.fromMap(m)).toList();
  }

  Future<List<Bill>> getAllBills() async {
    final maps = await _storage.query(orderBy: 'created_at DESC');
    return maps.map((m) => Bill.fromMap(m)).toList();
  }

  Future<double> getTotalInRange(
    DateTime start,
    DateTime end, {
    BillType? type,
  }) async {
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    String sql =
        'SELECT SUM(amount) as total FROM bills WHERE date >= ? AND date <= ?';
    List<dynamic> args = [startStr, endStr];
    if (type != null) {
      if (type == BillType.expense) {
        sql += " AND (type = ? OR type IS NULL OR type = '')";
      } else {
        sql += ' AND type = ?';
      }
      args.add(type.value);
    }
    final result = await _storage.rawQuery(sql, args);
    final total = result.isNotEmpty ? result.first['total'] : null;
    return (total is num) ? total.toDouble() : 0;
  }

  Future<Map<String, double>> getCategoryTotalsInRange(
    DateTime start,
    DateTime end, {
    BillType type = BillType.expense,
  }) async {
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    final typeWhere = type == BillType.expense
        ? "(type = ? OR type IS NULL OR type = '')"
        : 'type = ?';
    final result = await _storage.rawQuery(
      '''
      SELECT category, SUM(amount) as total
      FROM bills WHERE date >= ? AND date <= ? AND $typeWhere
      GROUP BY category
    ''',
      [startStr, endStr, type.value],
    );
    final map = <String, double>{};
    for (final row in result) {
      final cat = row['category'] as String? ?? '其他';
      final t = row['total'];
      map[cat] = (t is num) ? t.toDouble() : 0;
    }
    return map;
  }

  Future<Bill?> getLatestBill() async {
    final list = await getRecentBills(limit: 1);
    return list.isEmpty ? null : list.first;
  }
}
