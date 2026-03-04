import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants.dart';
import '../../../data/models/bill.dart';
import '../../providers/bill_provider.dart';
import '../add_bill/add_bill_page.dart';

class TabHomePage extends StatefulWidget {
  const TabHomePage({super.key});

  @override
  State<TabHomePage> createState() => _TabHomePageState();
}

class _TabHomePageState extends State<TabHomePage> {
  double _todayTotal = 0;
  double _weekTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadTotals();
  }

  Future<void> _loadTotals() async {
    final bp = context.read<BillProvider>();
    final today = await bp.getTodayTotal();
    final week = await bp.getWeekTotal();
    if (mounted) {
      setState(() {
        _todayTotal = today;
        _weekTotal = week;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;

    return Scaffold(
      appBar: AppBar(
        title: const Text('哎呀钱'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddBillPage()),
              );
            },
          ),
        ],
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
                todayTotal: _todayTotal,
                weekTotal: _weekTotal,
                cardBg: cardBg,
              ),
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

class _SummaryCard extends StatelessWidget {
  final double todayTotal;
  final double weekTotal;
  final Color cardBg;

  const _SummaryCard({
    required this.todayTotal,
    required this.weekTotal,
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
          const Text('今日支出', style: TextStyle(fontSize: 14, color: AppColors.neutralGrey)),
          const SizedBox(height: 4),
          Text(
            '¥${todayTotal.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.expenseRed,
            ),
          ),
          const SizedBox(height: 12),
          const Text('本周支出', style: TextStyle(fontSize: 14, color: AppColors.neutralGrey)),
          const SizedBox(height: 4),
          Text(
            '¥${weekTotal.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  final Bill bill;

  const _BillTile({required this.bill});

  @override
  Widget build(BuildContext context) {
    final iconName = AppConstants.categoryIcons[bill.category] ?? 'more_horiz';
    IconData icon;
    switch (iconName) {
      case 'restaurant': icon = Icons.restaurant; break;
      case 'directions_car': icon = Icons.directions_car; break;
      case 'shopping_cart': icon = Icons.shopping_cart; break;
      case 'movie': icon = Icons.movie; break;
      case 'home': icon = Icons.home; break;
      case 'local_hospital': icon = Icons.local_hospital; break;
      case 'school': icon = Icons.school; break;
      default: icon = Icons.more_horiz;
    }
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryLight,
        child: Icon(icon, color: AppColors.primaryGreen),
      ),
      title: Text(
        bill.category,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        bill.note.isEmpty
            ? DateFormat('yyyy-MM-dd').format(bill.date)
            : '${bill.note} · ${DateFormat('yyyy-MM-dd').format(bill.date)}',
        style: const TextStyle(fontSize: 12, color: AppColors.neutralGrey),
      ),
      trailing: Text(
        '¥${bill.amount.toStringAsFixed(0)}',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.expenseRed,
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
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '还没有记账记录',
              style: TextStyle(color: Colors.grey[600]),
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
