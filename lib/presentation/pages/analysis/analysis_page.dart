import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/analysis_service.dart';
import '../../providers/bill_provider.dart';
import '../../providers/points_provider.dart';

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
      setState(() => _error = '积分不足，请先登录或签到');
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
      final bills = await bp.getBillsInRange(start, end);
      final total = await bp.getTotalInRange(start, end);
      final catTotals = await bp.getCategoryTotalsInRange(start, end);
      if (bills.isEmpty) {
        setState(() {
          _result = '该时间段暂无记账数据，无法分析。';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分析')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '单次分析',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '记完一笔后会自动弹出分析',
              style: TextStyle(fontSize: 14, color: AppColors.neutralGrey),
            ),
            const SizedBox(height: 24),
            const Text(
              '周期分析',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '本周', label: Text('本周')),
                ButtonSegment(value: '本月', label: Text('本月')),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _runPeriodAnalysis,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.analytics),
                label: Text(_loading ? '分析中...' : '开始分析'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.expenseRed)),
            ],
            if (_result != null && _result!.isNotEmpty) ...[
              const SizedBox(height: 24),
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
          ],
        ),
      ),
    );
  }
}
