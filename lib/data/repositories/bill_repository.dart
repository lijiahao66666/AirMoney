import '../bill_storage.dart';
import '../database.dart';
import '../models/bill.dart';

class BillRepository {
  BillStorage get _storage => createBillStorage();

  Future<int> insert(Bill bill) async {
    return _storage.insert(bill);
  }

  Future<List<Bill>> getBillsInRange(DateTime start, DateTime end) async {
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    final maps = await _storage.query(
      where: 'date >= ? AND date <= ?',
      whereArgs: [startStr, endStr],
      orderBy: 'date DESC, created_at DESC',
    );
    return maps.map((m) => Bill.fromMap(m)).toList();
  }

  Future<List<Bill>> getRecentBills({int limit = 20}) async {
    final maps = await _storage.query(
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((m) => Bill.fromMap(m)).toList();
  }

  Future<double> getTotalInRange(DateTime start, DateTime end) async {
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    final result = await _storage.rawQuery(
      'SELECT SUM(amount) as total FROM bills WHERE date >= ? AND date <= ?',
      [startStr, endStr],
    );
    final total = result.isNotEmpty ? result.first['total'] : null;
    return (total is num) ? total.toDouble() : 0;
  }

  Future<Map<String, double>> getCategoryTotalsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    final result = await _storage.rawQuery('''
      SELECT category, SUM(amount) as total
      FROM bills WHERE date >= ? AND date <= ?
      GROUP BY category
    ''', [startStr, endStr]);
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
