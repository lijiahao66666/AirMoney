import 'models/bill.dart';

/// 账单存储抽象，用于平台差异化实现
abstract class BillStorage {
  Future<int> insert(Bill bill);
  Future<List<Map<String, dynamic>>> query({
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  });
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? args]);
}
