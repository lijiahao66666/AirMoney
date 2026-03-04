import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/bill.dart';
import '../../../services/analysis_service.dart';
import '../../providers/bill_provider.dart';
import '../../providers/points_provider.dart';

class SingleAnalysisPage extends StatefulWidget {
  final Bill bill;

  const SingleAnalysisPage({super.key, required this.bill});

  @override
  State<SingleAnalysisPage> createState() => _SingleAnalysisPageState();
}

class _SingleAnalysisPageState extends State<SingleAnalysisPage> {
  String? _result;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _analyze());
  }

  Future<void> _analyze() async {
    final points = context.read<PointsProvider>().balance;
    if (points <= 0) {
      setState(() {
        _error = '积分不足，请先登录或签到获取积分';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bp = context.read<BillProvider>();
      final end = widget.bill.date;
      final start = end.subtract(const Duration(days: 7));
      final catTotals = await bp.getCategoryTotalsInRange(start, end, type: BillType.expense);
      final cat7d = catTotals[widget.bill.category];
      final map = cat7d != null ? {widget.bill.category: cat7d} : null;
      final text = await analyzeSingleBill(widget.bill, categoryTotals7d: map);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('单次分析'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BillSummary(bill: widget.bill),
            const SizedBox(height: 24),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在分析...'),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.expenseRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!, style: const TextStyle(color: AppColors.expenseRed)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _analyze,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              )
            else if (_result != null && _result!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _result!,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BillSummary extends StatelessWidget {
  final Bill bill;

  const _BillSummary({required this.bill});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, color: AppColors.primaryGreen, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${bill.category} ¥${bill.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (bill.note.isNotEmpty)
                  Text(
                    bill.note,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.neutralGrey,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
