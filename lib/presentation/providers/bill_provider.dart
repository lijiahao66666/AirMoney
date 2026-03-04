import 'package:flutter/foundation.dart';
import '../../data/models/bill.dart';
import '../../data/repositories/bill_repository.dart';

class BillProvider extends ChangeNotifier {
  final BillRepository _repo = BillRepository();
  List<Bill> _recentBills = [];
  bool _loading = false;

  List<Bill> get recentBills => _recentBills;
  bool get loading => _loading;

  Future<void> loadRecentBills() async {
    _loading = true;
    notifyListeners();
    try {
      _recentBills = await _repo.getRecentBills();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<int> addBill(Bill bill) async {
    final id = await _repo.insert(bill);
    await loadRecentBills();
    return id;
  }

  Future<double> getTodayExpense() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _repo.getTotalInRange(start, end, type: BillType.expense);
  }

  Future<double> getWeekExpense() async {
    final now = DateTime.now();
    final weekday = now.weekday;
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: weekday - 1));
    final end = start.add(const Duration(days: 7));
    return _repo.getTotalInRange(start, end, type: BillType.expense);
  }

  Future<double> getTodayIncome() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _repo.getTotalInRange(start, end, type: BillType.income);
  }

  Future<double> getWeekIncome() async {
    final now = DateTime.now();
    final weekday = now.weekday;
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: weekday - 1));
    final end = start.add(const Duration(days: 7));
    return _repo.getTotalInRange(start, end, type: BillType.income);
  }

  Future<List<Bill>> getBillsInRange(DateTime start, DateTime end, {BillType? type}) async {
    return _repo.getBillsInRange(start, end, type: type);
  }

  Future<Map<String, double>> getCategoryTotalsInRange(
    DateTime start,
    DateTime end, {
    BillType type = BillType.expense,
  }) async {
    return _repo.getCategoryTotalsInRange(start, end, type: type);
  }

  Future<double> getTotalInRange(DateTime start, DateTime end, {BillType? type}) async {
    return _repo.getTotalInRange(start, end, type: type);
  }

  Future<Bill?> getLatestBill() async {
    return _repo.getLatestBill();
  }
}
