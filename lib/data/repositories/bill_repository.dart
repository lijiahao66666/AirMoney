import '../bill_storage.dart';
import '../database.dart';
import '../models/bill.dart';

class BillRepository {
  BillStorage get _storage => createBillStorage();

  bool _matchesType(Bill bill, BillType? type) {
    if (type == null) return true;
    return bill.type == type;
  }

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
    const where = 'date >= ? AND date <= ?';
    final whereArgs = <dynamic>[startStr, endStr];
    final maps = await _storage.query(
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date DESC, created_at DESC',
    );
    return maps
        .map((m) => Bill.fromMap(m))
        .where((bill) => _matchesType(bill, type))
        .toList();
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
    final bills = await getBillsInRange(start, end, type: type);
    return bills.fold<double>(0, (sum, bill) => sum + bill.amount);
  }

  Future<Map<String, double>> getCategoryTotalsInRange(
    DateTime start,
    DateTime end, {
    BillType type = BillType.expense,
  }) async {
    final map = <String, double>{};
    final bills = await getBillsInRange(start, end, type: type);
    for (final bill in bills) {
      final category = bill.category.trim();
      if (category.isEmpty) continue;
      map[category] = (map[category] ?? 0) + bill.amount;
    }
    return map;
  }

  Future<Bill?> getLatestBill() async {
    final list = await getRecentBills(limit: 1);
    return list.isEmpty ? null : list.first;
  }
}
