import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants.dart';
import '../../../data/models/bill.dart';
import '../../../services/analysis_service.dart';
import '../../providers/bill_provider.dart';
import '../../providers/points_provider.dart';
import '../../widgets/wallet_sheet.dart';
import 'single_analysis_page.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  String _period = '本周';
  String? _result;
  String? _error;
  bool _loading = false;

  DateTime _rangeStart() {
    final now = DateTime.now();
    switch (_period) {
      case '本周':
        final wd = now.weekday;
        return DateTime(now.year, now.month, now.day).subtract(Duration(days: wd - 1));
      case '本月':
        return DateTime(now.year, now.month, 1);
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  DateTime _rangeEnd() {
    final now = DateTime.now();
    switch (_period) {
      case '本周':
        final wd = now.weekday;
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: wd - 1));
        return start.add(const Duration(days: 6));
      case '本月':
        return DateTime(now.year, now.month + 1, 0);
      default:
        return now;
    }
  }

  Future<void> _runPeriodAnalysis() async {
    final points = context.read<PointsProvider>().balance;
    if (points <= 0) {
      setState(() => _error = '需要积分，请先签到或登录获取');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bp = context.read<BillProvider>();
      final start = _rangeStart();
      final end = _rangeEnd();
      final bills = await bp.getBillsInRange(start, end, type: BillType.expense);
      final total = await bp.getTotalInRange(start, end, type: BillType.expense);
      final catTotals = await bp.getCategoryTotalsInRange(start, end, type: BillType.expense);
      if (bills.isEmpty) {
        setState(() {
          _result = '这段时间没记过账，没法分析。先记几笔再来说反省吧～';
          _loading = false;
        });
        return;
      }
      final text = await analyzePeriod(
        bills: bills,
        total: total,
        categoryTotals: catTotals,
        periodLabel: _period,
      );
      if (mounted) {
        setState(() {
          _result = text;
          _loading = false;
        });
        context.read<PointsProvider>().syncFromServer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception:', '').trim();
          _loading = false;
        });
      }
    }
  }

  void _openSingleAnalysis(Bill bill) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SingleAnalysisPage(bill: bill)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;

    return Scaffold(
      appBar: AppBar(title: const Text('反省一下')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionCard(
              icon: Icons.receipt_long_rounded,
              title: '单次分析',
              subtitle: '选一笔最近的花销，看看值不值、怎么反省',
              isDark: isDark,
              child: Consumer<BillProvider>(
                builder: (_, bp, __) {
                  if (bp.loading && bp.recentBills.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final expenses = bp.recentBills
                      .where((b) => b.isExpense)
                      .toList();
                  if (expenses.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '还没有支出记录，记几笔再来分析吧～',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: expenses.length > 8 ? 8 : expenses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final b = expenses[i];
                      return _BillAnalysisTile(
                        bill: b,
                        cardBg: cardBg,
                        isDark: isDark,
                        onAnalyze: () => _openSingleAnalysis(b),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            _SectionCard(
              icon: Icons.analytics_rounded,
              title: '周期分析',
              subtitle: '看看这周/这月花多了没，给点反省建议',
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: '本周', label: Text('本周')),
                      ButtonSegment(value: '本月', label: Text('本月')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (s) => setState(() => _period = s.first),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loading ? null : _runPeriodAnalysis,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.analytics),
                    label: Text(_loading ? '反省中...' : '开始反省'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppColors.expenseRed),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            WalletSheet.show(
                              context,
                              context.read<PointsProvider>().balance,
                              () {
                                context.read<PointsProvider>().syncFromServer();
                                setState(() => _error = null);
                              },
                            );
                          },
                          child: const Text('去获取积分'),
                        ),
                      ],
                    ),
                  ],
                  if (_result != null && _result!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _result!,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final shadow = isDark ? AppColors.cardShadowDark : AppColors.cardShadowLight;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.primaryGreen, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _BillAnalysisTile extends StatelessWidget {
  final Bill bill;
  final Color cardBg;
  final bool isDark;
  final VoidCallback onAnalyze;

  const _BillAnalysisTile({
    required this.bill,
    required this.cardBg,
    required this.isDark,
    required this.onAnalyze,
  });

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAnalyze,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.expenseRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.expenseRed, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${bill.category} ¥${bill.amount.toStringAsFixed(0)}',
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '分析',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
