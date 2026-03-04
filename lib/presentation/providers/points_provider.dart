import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class PointsProvider extends ChangeNotifier {
  static const _kBalance = 'points_balance';

  int _balance = 0;
  bool _syncing = false;

  int get balance => _balance;
  bool get syncing => _syncing;

  Future<void> syncFromServer() async {
    if (_syncing) return;
    _syncing = true;
    notifyListeners();
    try {
      final b = await ApiService.initPoints(
        authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
      );
      _balance = b;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBalance, b);
    } catch (e) {
      debugPrint('[Points] sync error: $e');
      final prefs = await SharedPreferences.getInstance();
      _balance = prefs.getInt(_kBalance) ?? 0;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _balance = prefs.getInt(_kBalance) ?? 0;
    notifyListeners();
    unawaited(syncFromServer());
  }

  void setBalance(int value) {
    _balance = value < 0 ? 0 : value;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_kBalance, _balance);
    });
  }

  void addPoints(int delta) {
    if (delta != 0) setBalance(_balance + delta);
  }

  bool get hasPoints => _balance > 0;
}
