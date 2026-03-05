import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants.dart';
import '../../../data/models/bill.dart';
import '../../providers/bill_provider.dart';
import '../../providers/points_provider.dart';
import '../../widgets/wallet_sheet.dart';
import '../../widgets/reminder_settings_sheet.dart';
import '../../../services/notification_service.dart';
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
  static const int _recentBillsMaxShown = 10;
  bool _recentBillsExpanded = false;

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
      appBar: AppBar(
        title: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => LinearGradient(
                  colors: isDark
                      ? [AppColors.primaryGreen, AppColors.primaryGreen.withOpacity(0.85)]
                      : [AppColors.primaryGreen, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: const Text(
                  '哎呀，钱！',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '该省省，不该花花！',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: (isDark ? Colors.white70 : AppColors.deepText).withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
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
                isDark: isDark,
                onAddTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddBillPage()),
                  );
                  if (mounted) await _loadTotals();
                },
              ),
              const SizedBox(height: 20),
              _ShortcutCards(
                onAnalysis: () => _openAnalysisOrPrompt(context),
                onConsult: () => _openConsultOrPrompt(context),
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              Consumer<PointsProvider>(
                builder: (_, pp, __) => _PointsAndReminderCard(
                  balance: pp.balance,
                  onPointsTap: () => WalletSheet.show(
                    context,
                    pp.balance,
                    () => pp.syncFromServer(),
                  ),
                  onReminderTap: () => ReminderSettingsSheet.show(context),
                  isDark: isDark,
                ),
              ),
              const SizedBox(height: 24),
              _SectionTitle(icon: Icons.receipt_long_rounded, label: '最近记录'),
              const SizedBox(height: 12),
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
                    return _EmptyHint(onAdd: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddBillPage()),
                      );
                      if (mounted) await _loadTotals();
                    });
                  }
                  final total = bp.recentBills.length;
                  final showCount = _recentBillsExpanded
                      ? total
                      : total.clamp(0, _recentBillsMaxShown);
                  final hasMore = total > _recentBillsMaxShown && !_recentBillsExpanded;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: showCount,
                        itemBuilder: (_, i) {
                          final b = bp.recentBills[i];
                          return _BillTile(bill: b);
                        },
                      ),
                      if (hasMore)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InkWell(
                            onTap: () => setState(() => _recentBillsExpanded = true),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.expand_more,
                                    size: 20,
                                    color: AppColors.primaryGreen,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '继续查看（共 $total 条）',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.primaryGreen,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  '浙ICP备2026011869号-1',
                  style: TextStyle(
                    fontSize: 11,
                    color: (isDark ? Colors.white70 : AppColors.deepText).withOpacity(0.35),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

void _openAnalysisOrPrompt(BuildContext context) {
  final pp = context.read<PointsProvider>();
  if (pp.balance <= 0) {
    _showPointsRequiredSheet(context, '花哪了');
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalysisPage()));
}

void _openConsultOrPrompt(BuildContext context) {
  final pp = context.read<PointsProvider>();
  if (pp.balance <= 0) {
    _showPointsRequiredSheet(context, '该不该花');
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConsultPage()));
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white70 : AppColors.deepText;
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primaryGreen),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
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

class _PointsAndReminderCard extends StatelessWidget {
  final int balance;
  final VoidCallback onPointsTap;
  final VoidCallback onReminderTap;
  final bool isDark;

  const _PointsAndReminderCard({
    required this.balance,
    required this.onPointsTap,
    required this.onReminderTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final shadow = isDark ? AppColors.cardShadowDark : AppColors.cardShadowLight;
    final dividerColor = (isDark ? Colors.white : Colors.black).withOpacity(0.08);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: shadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onReminderTap,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                child: FutureBuilder<List<String>>(
                  future: NotificationService.getReminderTimes(),
                  builder: (context, snap) {
                    final times = snap.data ?? [];
                    final nextTime = times.isNotEmpty ? times.first : '13:00';
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.notifications_active_rounded, color: AppColors.primaryGreen, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '提醒记账',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: (isDark ? Colors.white : Colors.black87).withOpacity(0.8),
                                  ),
                                ),
                                Text(
                                  '下次 $nextTime',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 18),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: dividerColor,
            ),
            Expanded(
              child: InkWell(
                onTap: onPointsTap,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.pointsGold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.account_balance_wallet_rounded, color: AppColors.pointsGold, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '积分',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: (isDark ? Colors.white : Colors.black87).withOpacity(0.8),
                              ),
                            ),
                            Text(
                              NumberFormat('#,###').format(balance),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.pointsGold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutCards extends StatelessWidget {
  final VoidCallback onAnalysis;
  final VoidCallback onConsult;
  final bool isDark;

  const _ShortcutCards({
    required this.onAnalysis,
    required this.onConsult,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ShortcutCard(
            icon: Icons.analytics_rounded,
            title: '花哪了',
            subtitle: '看看钱花哪儿了',
            onTap: onAnalysis,
            isDark: isDark,
            isPrimary: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ShortcutCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: '该不该花',
            subtitle: '这笔钱值不值得花',
            onTap: onConsult,
            isDark: isDark,
            isPrimary: false,
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
  final bool isPrimary;

  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDark,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final shadow = isDark ? AppColors.cardShadowDark : AppColors.cardShadowLight;
    final accentColor = isPrimary ? AppColors.primaryGreen : AppColors.pointsGold;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: shadow,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 26),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
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
  final bool isDark;
  final VoidCallback onAddTap;

  const _SummaryCard({
    required this.todayExpense,
    required this.weekExpense,
    required this.todayIncome,
    required this.weekIncome,
    required this.cardBg,
    required this.isDark,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    final shadow = isDark ? AppColors.cardShadowDark : AppColors.cardShadowLight;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryItem(
                        label: '今日支出',
                        amount: todayExpense,
                        color: AppColors.expenseRed,
                        icon: Icons.trending_down_rounded,
                        isDark: isDark,
                        isLarge: true,
                      ),
                    ),
                    Expanded(
                      child: _SummaryItem(
                        label: '今日收入',
                        amount: todayIncome,
                        color: AppColors.primaryGreen,
                        icon: Icons.trending_up_rounded,
                        isDark: isDark,
                        isLarge: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 1,
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryItem(
                        label: '本周支出',
                        amount: weekExpense,
                        color: AppColors.expenseRed,
                        icon: Icons.calendar_view_week_rounded,
                        isDark: isDark,
                        isLarge: false,
                      ),
                    ),
                    Expanded(
                      child: _SummaryItem(
                        label: '本周收入',
                        amount: weekIncome,
                        color: AppColors.primaryGreen,
                        icon: Icons.calendar_view_week_rounded,
                        isDark: isDark,
                        isLarge: false,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Material(
              color: AppColors.primaryGreen,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onAddTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '记一笔',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;
  final bool isDark;
  final bool isLarge;

  const _SummaryItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    required this.isDark,
    required this.isLarge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color.withOpacity(0.8)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, color: AppColors.neutralGrey)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '¥${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: isLarge ? 24 : 17,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconName = AppConstants.categoryIcons[bill.category] ?? 'more_horiz';
    final icon = _iconFromName(iconName);
    final isIncome = bill.isIncome;
    final amountColor = isIncome ? AppColors.primaryGreen : AppColors.expenseRed;
    final prefix = isIncome ? '+' : '-';
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final shadow = isDark ? AppColors.cardShadowDark : AppColors.cardShadowLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: shadow,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: amountColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: amountColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isIncome ? '收入' : '支出'} · ${bill.category}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bill.note.isEmpty
                          ? DateFormat('yyyy-MM-dd').format(bill.date)
                          : '${bill.note} · ${DateFormat('yyyy-MM-dd').format(bill.date)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Text(
                '$prefix¥${bill.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: amountColor,
                ),
              ),
            ],
          ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final shadow = isDark ? AppColors.cardShadowDark : AppColors.cardShadowLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: shadow,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.savings_rounded, size: 56, color: AppColors.primaryGreen.withOpacity(0.8)),
            ),
            const SizedBox(height: 24),
            Text(
              '记下第一笔，养成好习惯',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '省下的每一笔从记录开始',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('记一笔'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
