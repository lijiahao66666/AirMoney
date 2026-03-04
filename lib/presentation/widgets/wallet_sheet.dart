import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../pages/auth/login_page.dart';

class WalletSheet extends StatelessWidget {
  final int balance;
  final VoidCallback onBalanceChanged;

  const WalletSheet({
    super.key,
    required this.balance,
    required this.onBalanceChanged,
  });

  static Future<void> show(BuildContext context, int balance, VoidCallback onBalanceChanged) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => WalletSheet(balance: balance, onBalanceChanged: onBalanceChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _WalletSheetContent(
      initialBalance: balance,
      onBalanceChanged: onBalanceChanged,
    );
  }
}

class _WalletSheetContent extends StatefulWidget {
  final int initialBalance;
  final VoidCallback onBalanceChanged;

  const _WalletSheetContent({
    required this.initialBalance,
    required this.onBalanceChanged,
  });

  @override
  State<_WalletSheetContent> createState() => _WalletSheetContentState();
}

class _WalletSheetContentState extends State<_WalletSheetContent> {
  int _currentBalance = 0;
  bool _checkedInToday = false;
  bool _checkinBusy = false;
  int _checkinPoints = 5000;
  int _initialGrantPoints = 500000;

  @override
  void initState() {
    super.initState();
    _currentBalance = widget.initialBalance;
    _loadCheckinStatus();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final resp = await ApiService.getConfig();
      if (mounted) {
        setState(() {
          _checkinPoints = (resp['checkin_points'] as num?)?.toInt() ?? 5000;
          _initialGrantPoints = (resp['initial_grant_points'] as num?)?.toInt() ?? 500000;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCheckinStatus() async {
    try {
      final status = await ApiService.getCheckinStatus(
        authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
      );
      if (mounted) setState(() => _checkedInToday = status);
    } catch (_) {}
  }

  Future<void> _refreshBalance() async {
    try {
      final b = await ApiService.getPointsBalance(
        authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
      );
      if (mounted) setState(() => _currentBalance = b);
    } catch (_) {}
  }

  Future<void> _doCheckin() async {
    if (_checkedInToday || _checkinBusy) return;
    setState(() => _checkinBusy = true);
    try {
      final result = await ApiService.checkin(
        authToken: AuthService.token.isNotEmpty ? AuthService.token : null,
      );
      if (mounted) {
        setState(() {
          _checkedInToday = true;
          if (result.balance != null) {
            _currentBalance = result.balance!;
          } else {
            _currentBalance += result.points;
          }
        });
        widget.onBalanceChanged();
        if (result.points > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('签到成功！+${NumberFormat('#,###').format(result.points)} 积分'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('签到失败: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _checkinBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '积分钱包',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
              const Spacer(),
              Text(
                '余额：${fmt.format(_currentBalance)}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.pointsGold),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _sectionCard(
            context,
            Row(
              children: [
                Icon(
                  AuthService.isLoggedIn ? Icons.account_circle_rounded : Icons.account_circle_outlined,
                  color: AuthService.isLoggedIn ? AppColors.primaryGreen : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AuthService.isLoggedIn ? (AuthService.phone) : '未登录',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AuthService.isLoggedIn ? '积分跨设备同步' : '登录赠送积分，跨设备同步',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (AuthService.isLoggedIn) {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('退出登录'),
                          content: const Text('确定退出？积分将保留在账户中。'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await AuthService.logout();
                        widget.onBalanceChanged();
                        if (mounted) {
                          await _refreshBalance();
                          setState(() {});
                        }
                      }
                    } else {
                      final success = await LoginPage.show(context);
                      if (success == true && mounted) {
                        widget.onBalanceChanged();
                        await _refreshBalance();
                        setState(() {});
                      }
                    }
                  },
                  child: Text(AuthService.isLoggedIn ? '退出' : '登录'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            Row(
              children: [
                Icon(
                  _checkedInToday ? Icons.check_circle : Icons.calendar_today,
                  color: _checkedInToday ? AppColors.primaryGreen : AppColors.primaryGreen,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('每日签到', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(
                        _checkedInToday ? '今日已签到' : '签到领 +${fmt.format(_checkinPoints)} 积分',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _checkedInToday || _checkinBusy ? null : _doCheckin,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primaryGreen),
                  child: Text(_checkinBusy ? '签到中…' : (_checkedInToday ? '已签到' : '立即签到')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '哎呀，钱！- 少花点，存多点',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
