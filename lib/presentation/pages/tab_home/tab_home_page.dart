import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants.dart';
import '../../../data/models/bill.dart';
import '../../providers/bill_provider.dart';
import '../../providers/points_provider.dart';
import '../../widgets/wallet_sheet.dart';
import '../add_bill/add_bill_page.dart';
import '../analysis/analysis_page.dart';
import '../consult/consult_page.dart';

class TabHomePage extends StatefulWidget {
  const TabHomePage({super.key});

  @override
  State<TabHomePage> createState() => _TabHomePageState();
}

class _TabHomePageState extends State<TabHomePage> {
  double _todayExpense = 0;
  double _weekExpense = 0;
  double _todayIncome = 0;
  double _weekIncome = 0;

  @override
  void initState() {
    super.initState();
    _loadTotals();
  }

  Future<void> _loadTotals() async {
    final bp = context.read<BillProvider>();
    final todayE = await bp.getTodayExpense();
    final weekE = await bp.getWeekExpense();
    final todayI = await bp.getTodayIncome();
    final weekI = await bp.getWeekIncome();
    if (mounted) {
      setState(() {
        _todayExpense = todayE;
        _weekExpense = weekE;
        _todayIncome = todayI;
        _weekIncome = weekI;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;

    return Scaffold(
      appBar: AppBar(title: const Text('哎呀，钱！')),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<BillProvider>().loadRecentBills();
          await _loadTotals();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryCard(
                todayExpense: _todayExpense,
                weekExpense: _weekExpense,
                todayIncome: _todayIncome,
                weekIncome: _weekIncome,
                cardBg: cardBg,
              ),
              const SizedBox(height: 16),
              Consumer<PointsProvider>(
                builder: (_, pp, __) => _PointsEntryCard(
                  balance: pp.balance,
                  onTap: () => WalletSheet.show(
                    context,
                    pp.balance,
                    () => pp.syncFromServer(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ShortcutCards(
                onAnalysis: () => _openAnalysisOrPrompt(context),
                onConsult: () => _openConsultOrPrompt(context),
              ),
              const SizedBox(height: 16),
              _NotificationReminderCard(),
              const SizedBox(height: 24),
              const Text(
                '最近记录',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Consumer<BillProvider>(
                builder: (_, bp, __) {
                  if (bp.loading && bp.recentBills.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (bp.recentBills.isEmpty) {
                    return _EmptyHint(onAdd: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddBillPage()),
                      );
                    });
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: bp.recentBills.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = bp.recentBills[i];
                      return _BillTile(bill: b);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddBillPage()),
          );
        },
        backgroundColor: AppColors.primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

void _openAnalysisOrPrompt(BuildContext context) {
  final pp = context.read<PointsProvider>();
  if (pp.balance <= 0) {
    _showPointsRequiredSheet(context, '分析');
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalysisPage()));
}

void _openConsultOrPrompt(BuildContext context) {
  final pp = context.read<PointsProvider>();
  if (pp.balance <= 0) {
    _showPointsRequiredSheet(context, '买前咨询');
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConsultPage()));
}

void _showPointsRequiredSheet(BuildContext context, String featureName) {
  final pp = context.read<PointsProvider>();
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.orange[300]),
          const SizedBox(height: 16),
          Text(
            '$featureName需要积分',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '请先签到或登录获取积分',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    WalletSheet.show(context, pp.balance, () => pp.syncFromServer());
                  },
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primaryGreen),
                  child: const Text('去获取积分'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PointsEntryCard extends StatelessWidget {
  final int balance;
  final VoidCallback onTap;

  const _PointsEntryCard({required this.balance, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet, color: AppColors.pointsGold, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '积分',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '${NumberFormat('#,###').format(balance)} · 签到领积分',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[500], size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationReminderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('通知提醒功能即将支持，到时间会提醒你记账')),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.notifications_outlined, color: AppColors.primaryGreen, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '通知提醒',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '到时间提醒你记账',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[500], size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutCards extends StatelessWidget {
  final VoidCallback onAnalysis;
  final VoidCallback onConsult;

  const _ShortcutCards({
    required this.onAnalysis,
    required this.onConsult,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: _ShortcutCard(
            icon: Icons.analytics,
            title: '分析',
            subtitle: '你是不是又花多了？',
            onTap: onAnalysis,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ShortcutCard(
            icon: Icons.chat_bubble_outline,
            title: '买前咨询',
            subtitle: '一定要花这个钱吗？',
            onTap: onConsult,
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDark;

  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primaryGreen, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double todayExpense;
  final double weekExpense;
  final double todayIncome;
  final double weekIncome;
  final Color cardBg;

  const _SummaryCard({
    required this.todayExpense,
    required this.weekExpense,
    required this.todayIncome,
    required this.weekIncome,
    required this.cardBg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('今日支出', style: TextStyle(fontSize: 13, color: AppColors.neutralGrey)),
                    Text(
                      '¥${todayExpense.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.expenseRed,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('今日收入', style: TextStyle(fontSize: 13, color: AppColors.neutralGrey)),
                    Text(
                      '¥${todayIncome.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('本周支出', style: TextStyle(fontSize: 13, color: AppColors.neutralGrey)),
                    Text(
                      '¥${weekExpense.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.expenseRed,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('本周收入', style: TextStyle(fontSize: 13, color: AppColors.neutralGrey)),
                    Text(
                      '¥${weekIncome.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  final Bill bill;

  const _BillTile({required this.bill});

  IconData _iconFromName(String iconName) {
    switch (iconName) {
      case 'restaurant': return Icons.restaurant;
      case 'directions_car': return Icons.directions_car;
      case 'shopping_cart': return Icons.shopping_cart;
      case 'movie': return Icons.movie;
      case 'home': return Icons.home;
      case 'local_hospital': return Icons.local_hospital;
      case 'school': return Icons.school;
      case 'work': return Icons.work;
      case 'emoji_events': return Icons.emoji_events;
      case 'handyman': return Icons.handyman;
      case 'trending_up': return Icons.trending_up;
      case 'redeem': return Icons.redeem;
      default: return Icons.more_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconName = AppConstants.categoryIcons[bill.category] ?? 'more_horiz';
    final icon = _iconFromName(iconName);
    final isIncome = bill.isIncome;
    final amountColor = isIncome ? AppColors.primaryGreen : AppColors.expenseRed;
    final prefix = isIncome ? '+¥' : '-¥';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryLight,
        child: Icon(icon, color: isIncome ? AppColors.primaryGreen : AppColors.expenseRed),
      ),
      title: Text(
        '${isIncome ? '收入' : '支出'} · ${bill.category}',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        bill.note.isEmpty
            ? DateFormat('yyyy-MM-dd').format(bill.date)
            : '${bill.note} · ${DateFormat('yyyy-MM-dd').format(bill.date)}',
        style: const TextStyle(fontSize: 12, color: AppColors.neutralGrey),
      ),
      trailing: Text(
        '$prefix${bill.amount.toStringAsFixed(0)}',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: amountColor,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyHint({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.savings_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '还没记过账？省下的第一笔从记录开始',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('记一笔'),
            ),
          ],
        ),
      ),
    );
  }
}
