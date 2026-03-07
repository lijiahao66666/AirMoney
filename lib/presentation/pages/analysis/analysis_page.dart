import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/bill.dart';
import '../../../services/analysis_service.dart';
import '../../providers/bill_provider.dart';
import '../../providers/points_provider.dart';
import '../../widgets/wallet_sheet.dart';
import '../add_bill/add_bill_page.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  final TextEditingController _noteFilterController = TextEditingController();

  List<Bill> _allBills = [];
  bool _loadingBills = false;
  bool _batchAnalyzing = false;

  BillType? _filterType;
  String? _filterCategory;
  String? _filterPayMethod;
  DateTimeRange? _filterDateRange;
  String _quickDateRange = 'none';

  String? _batchAnalysisResult;
  String? _batchAnalysisError;
  bool _batchAnalysisVisible = false;
  final Map<String, String> _batchAnalysisCache = <String, String>{};

  Object? _singleAnalysisBillKey;
  bool _singleAnalysisVisible = false;
  bool _singleAnalyzing = false;
  String? _singleAnalysisResult;
  String? _singleAnalysisError;
  final Map<Object, String> _singleAnalysisCache = <Object, String>{};

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  @override
  void dispose() {
    _noteFilterController.dispose();
    super.dispose();
  }

  Object _billKey(Bill bill) {
    return bill.id ?? bill.createdAt.microsecondsSinceEpoch;
  }

  String _buildBatchCacheKey(List<Bill> bills) {
    final parts = bills.map((bill) {
      final idPart =
          bill.id?.toString() ??
          bill.createdAt.microsecondsSinceEpoch.toString();
      final datePart = DateFormat('yyyy-MM-dd').format(bill.date);
      return '$idPart|$datePart|${bill.category}|${bill.amount.toStringAsFixed(2)}';
    }).toList()..sort();
    return parts.join('||');
  }

  Future<void> _loadBills() async {
    if (mounted) {
      setState(() => _loadingBills = true);
    }
    try {
      final bills = await context.read<BillProvider>().getAllBills();
      if (!mounted) return;
      setState(() {
        _allBills = bills;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingBills = false);
      }
    }
  }

  Future<void> _refreshAllData() async {
    await Future.wait([
      _loadBills(),
      context.read<BillProvider>().loadRecentBills(),
    ]);
  }

  List<String> get _categoryOptions {
    final base = _filterType == BillType.expense
        ? AppConstants.expenseCategories
        : _filterType == BillType.income
        ? AppConstants.incomeCategories
        : [...AppConstants.expenseCategories, ...AppConstants.incomeCategories];

    final set = <String>{...base};
    for (final bill in _allBills) {
      if (_filterType != null && bill.type != _filterType) continue;
      set.add(bill.category);
    }
    final list = set.toList();
    list.sort();
    return list;
  }

  List<String> get _payMethodOptions {
    final set = <String>{...AppConstants.payMethods};
    for (final bill in _allBills) {
      set.add(bill.payMethod);
    }
    final list = set.toList();
    list.sort();
    return list;
  }

  List<Bill> get _filteredBills {
    final noteKeyword = _noteFilterController.text.trim().toLowerCase();
    final start = _filterDateRange?.start;
    final end = _filterDateRange?.end;

    final result = _allBills.where((bill) {
      if (_filterType != null && bill.type != _filterType) return false;

      if (_filterCategory != null && _filterCategory!.isNotEmpty) {
        if (bill.category != _filterCategory) return false;
      }

      if (_filterPayMethod != null && _filterPayMethod!.isNotEmpty) {
        if (bill.payMethod != _filterPayMethod) return false;
      }

      if (noteKeyword.isNotEmpty &&
          !bill.note.toLowerCase().contains(noteKeyword)) {
        return false;
      }

      if (start != null && end != null) {
        final day = DateTime(bill.date.year, bill.date.month, bill.date.day);
        final rangeStart = DateTime(start.year, start.month, start.day);
        final rangeEnd = DateTime(end.year, end.month, end.day);
        if (day.isBefore(rangeStart) || day.isAfter(rangeEnd)) return false;
      }

      return true;
    }).toList();

    result.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return b.createdAt.compareTo(a.createdAt);
    });

    return result;
  }

  List<Bill> get _filteredExpenseBills =>
      _filteredBills.where((bill) => bill.isExpense).toList();

  bool get _hasFilters {
    return _filterType != null ||
        (_filterCategory?.isNotEmpty ?? false) ||
        (_filterPayMethod?.isNotEmpty ?? false) ||
        _filterDateRange != null ||
        _noteFilterController.text.trim().isNotEmpty;
  }

  void _clearSingleAnalysis() {
    setState(() {
      _singleAnalysisVisible = false;
      _singleAnalyzing = false;
    });
  }

  void _applyThisWeekRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: today.weekday - 1));
    setState(() {
      _quickDateRange = 'week';
      _filterDateRange = DateTimeRange(start: start, end: today);
      _batchAnalysisError = null;
      _batchAnalysisVisible = false;
    });
  }

  void _applyThisMonthRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(now.year, now.month, 1);
    setState(() {
      _quickDateRange = 'month';
      _filterDateRange = DateTimeRange(start: start, end: today);
      _batchAnalysisError = null;
      _batchAnalysisVisible = false;
    });
  }

  Future<void> _pickFilterDateRange() async {
    final now = DateTime.now();
    final initial =
        _filterDateRange ??
        DateTimeRange(
          start: DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 30)),
          end: DateTime(now.year, now.month, now.day),
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initial,
    );

    if (picked == null || !mounted) return;
    setState(() {
      _filterDateRange = picked;
      _quickDateRange = 'custom';
      _batchAnalysisError = null;
      _batchAnalysisVisible = false;
    });
  }

  void _clearFilters() {
    _noteFilterController.clear();
    setState(() {
      _filterType = null;
      _filterCategory = null;
      _filterPayMethod = null;
      _filterDateRange = null;
      _quickDateRange = 'none';
      _batchAnalysisError = null;
      _batchAnalysisVisible = false;
    });
  }

  Future<void> _editBill(Bill bill) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AddBillPage(editingBill: bill)));
    if (!mounted) return;
    await _refreshAllData();
  }

  Future<void> _deleteBill(Bill bill) async {
    final id = bill.id;
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text(
          '确定删除这条记录吗？\n${bill.category}  ¥${bill.amount.toStringAsFixed(0)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final deleted = await context.read<BillProvider>().deleteBill(id);
    if (!mounted) return;

    if (deleted) {
      final billKey = _billKey(bill);
      _singleAnalysisCache.remove(billKey);
      _batchAnalysisCache.clear();
      if (_singleAnalysisBillKey == billKey) {
        _clearSingleAnalysis();
        _singleAnalysisBillKey = null;
        _singleAnalysisResult = null;
        _singleAnalysisError = null;
      }
      _batchAnalysisVisible = false;
      _batchAnalysisResult = null;
      _batchAnalysisError = null;
      await _refreshAllData();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(deleted ? '记录已删除' : '删除失败，请重试'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _buildFilterLabel() {
    if (_quickDateRange == 'week') return '本周';
    if (_quickDateRange == 'month') return '本月';
    if (_filterDateRange != null) {
      final fmt = DateFormat('MM-dd');
      return '${fmt.format(_filterDateRange!.start)} ~ ${fmt.format(_filterDateRange!.end)}';
    }
    return '当前筛选';
  }

  Future<void> _runFilteredAnalysis() async {
    final points = context.read<PointsProvider>().balance;
    if (points <= 0) {
      WalletSheet.show(
        context,
        points,
        () => context.read<PointsProvider>().syncFromServer(),
      );
      return;
    }

    final expenseBills = _filteredExpenseBills;
    if (expenseBills.isEmpty) {
      setState(() {
        _batchAnalysisResult = '当前筛选下没有支出记录，无法反省。';
        _batchAnalysisError = null;
        _batchAnalysisVisible = true;
      });
      return;
    }

    final cacheKey = _buildBatchCacheKey(expenseBills);
    final cached = _batchAnalysisCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _batchAnalysisResult = cached;
        _batchAnalysisError = null;
        _batchAnalysisVisible = true;
      });
      return;
    }

    setState(() {
      _batchAnalyzing = true;
      _batchAnalysisError = null;
      _batchAnalysisVisible = true;
    });

    try {
      final total = expenseBills.fold<double>(
        0,
        (sum, bill) => sum + bill.amount,
      );
      final categoryTotals = <String, double>{};
      for (final bill in expenseBills) {
        categoryTotals[bill.category] =
            (categoryTotals[bill.category] ?? 0) + bill.amount;
      }

      final text = await analyzePeriod(
        bills: expenseBills,
        total: total,
        categoryTotals: categoryTotals,
        periodLabel: _buildFilterLabel(),
      );

      if (!mounted) return;
      setState(() {
        _batchAnalysisResult = text;
        _batchAnalyzing = false;
        _batchAnalysisCache[cacheKey] = text;
        _batchAnalysisVisible = true;
      });
      context.read<PointsProvider>().syncFromServer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _batchAnalysisError = e.toString().replaceAll('Exception:', '').trim();
        _batchAnalyzing = false;
        _batchAnalysisVisible = true;
      });
    }
  }

  Future<void> _runSingleAnalysis(Bill bill) async {
    if (!bill.isExpense) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('仅支出记录支持单条反省')));
      return;
    }

    final points = context.read<PointsProvider>().balance;
    if (points <= 0) {
      WalletSheet.show(
        context,
        points,
        () => context.read<PointsProvider>().syncFromServer(),
      );
      return;
    }

    final billKey = _billKey(bill);
    if (_singleAnalysisBillKey == billKey &&
        !_singleAnalysisVisible &&
        ((_singleAnalysisResult?.isNotEmpty ?? false) ||
            (_singleAnalysisError?.isNotEmpty ?? false))) {
      setState(() {
        _singleAnalysisVisible = true;
        _singleAnalyzing = false;
      });
      return;
    }

    final cached = _singleAnalysisCache[billKey];
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _singleAnalysisBillKey = billKey;
        _singleAnalysisVisible = true;
        _singleAnalyzing = false;
        _singleAnalysisResult = cached;
        _singleAnalysisError = null;
      });
      return;
    }

    setState(() {
      _singleAnalysisBillKey = billKey;
      _singleAnalysisVisible = true;
      _singleAnalyzing = true;
      _singleAnalysisResult = null;
      _singleAnalysisError = null;
    });

    try {
      final today = DateTime.now();
      final end = DateTime(today.year, today.month, today.day);
      final start = end.subtract(const Duration(days: 29));
      final categoryTotals = await context
          .read<BillProvider>()
          .getCategoryTotalsInRange(start, end, type: BillType.expense);
      Map<String, double>? sameCategoryTotals;
      final amount = categoryTotals[bill.category];
      if (amount != null && amount > 0) {
        sameCategoryTotals = {bill.category: amount};
      }

      final text = await analyzeSingleBill(
        bill,
        categoryTotals7d: sameCategoryTotals,
      );

      if (!mounted) return;
      setState(() {
        _singleAnalyzing = false;
        _singleAnalysisResult = text;
        _singleAnalysisCache[billKey] = text;
      });
      context.read<PointsProvider>().syncFromServer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _singleAnalyzing = false;
        _singleAnalysisError = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final bills = _filteredBills;
    final expenseCount = _filteredExpenseBills.length;

    return Scaffold(
      appBar: AppBar(title: const Text('反省一下')),
      body: RefreshIndicator(
        onRefresh: _refreshAllData,
        child: _loadingBills && _allBills.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _FilterPanel(
                        filterType: _filterType,
                        filterCategory: _filterCategory,
                        filterPayMethod: _filterPayMethod,
                        filterDateRange: _filterDateRange,
                        quickDateRange: _quickDateRange,
                        noteController: _noteFilterController,
                        categoryOptions: _categoryOptions,
                        payMethodOptions: _payMethodOptions,
                        hasFilters: _hasFilters,
                        onTypeChanged: (type) {
                          setState(() {
                            _filterType = type;
                            if (_filterCategory != null &&
                                !_categoryOptions.contains(_filterCategory)) {
                              _filterCategory = null;
                            }
                            _batchAnalysisError = null;
                            _batchAnalysisVisible = false;
                          });
                        },
                        onCategoryChanged: (value) {
                          setState(() {
                            _filterCategory = value;
                            _batchAnalysisError = null;
                            _batchAnalysisVisible = false;
                          });
                        },
                        onPayMethodChanged: (value) {
                          setState(() {
                            _filterPayMethod = value;
                            _batchAnalysisError = null;
                            _batchAnalysisVisible = false;
                          });
                        },
                        onNoteChanged: (_) {
                          setState(() {
                            _batchAnalysisError = null;
                            _batchAnalysisVisible = false;
                          });
                        },
                        onPickDateRange: _pickFilterDateRange,
                        onSelectWeek: _applyThisWeekRange,
                        onSelectMonth: _applyThisMonthRange,
                        onClearDateRange: () {
                          setState(() {
                            _filterDateRange = null;
                            _quickDateRange = 'none';
                            _batchAnalysisError = null;
                            _batchAnalysisVisible = false;
                          });
                        },
                        onClearFilters: _clearFilters,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: isDark
                              ? AppColors.cardShadowDark
                              : AppColors.cardShadowLight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '当前筛选：共 ${bills.length} 条，支出可反省 ${expenseCount} 条',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _batchAnalyzing
                                    ? null
                                    : _runFilteredAnalysis,
                                icon: _batchAnalyzing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.analytics_rounded),
                                label: Text(
                                  _batchAnalyzing ? '反省中...' : '反省当前筛选全部数据',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primaryGreen,
                                ),
                              ),
                            ),
                            if (_batchAnalysisError != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _batchAnalysisError!,
                                      style: const TextStyle(
                                        color: AppColors.expenseRed,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      WalletSheet.show(
                                        context,
                                        context.read<PointsProvider>().balance,
                                        () => context
                                            .read<PointsProvider>()
                                            .syncFromServer(),
                                      );
                                    },
                                    child: const Text('去获取积分'),
                                  ),
                                ],
                              ),
                            ],
                            if (_batchAnalysisVisible &&
                                _batchAnalysisResult != null &&
                                _batchAnalysisResult!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen.withOpacity(
                                    0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _batchAnalysisVisible = false;
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.expand_less_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('收起'),
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _batchAnalysisResult!,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                      child: Text(
                        '记录列表',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  if (bills.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyRecords(
                        hasAnyBill: _allBills.isNotEmpty,
                        onAdd: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AddBillPage(),
                            ),
                          );
                          if (!mounted) return;
                          await _refreshAllData();
                        },
                        onClearFilters: _clearFilters,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((_, i) {
                          final bill = bills[i];
                          final billKey = _billKey(bill);
                          final showInlinePanel =
                              _singleAnalysisVisible &&
                              _singleAnalysisBillKey == billKey;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              children: [
                                _RecordTile(
                                  bill: bill,
                                  onReflect: bill.isExpense
                                      ? () => _runSingleAnalysis(bill)
                                      : null,
                                  onEdit: () => _editBill(bill),
                                  onDelete: () => _deleteBill(bill),
                                ),
                                if (showInlinePanel)
                                  _InlineAnalysisPanel(
                                    loading: _singleAnalyzing,
                                    result: _singleAnalysisResult,
                                    error: _singleAnalysisError,
                                    onCollapse: _clearSingleAnalysis,
                                  ),
                              ],
                            ),
                          );
                        }, childCount: bills.length),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  final BillType? filterType;
  final String? filterCategory;
  final String? filterPayMethod;
  final DateTimeRange? filterDateRange;
  final String quickDateRange;
  final TextEditingController noteController;
  final List<String> categoryOptions;
  final List<String> payMethodOptions;
  final bool hasFilters;
  final ValueChanged<BillType?> onTypeChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onPayMethodChanged;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onPickDateRange;
  final VoidCallback onSelectWeek;
  final VoidCallback onSelectMonth;
  final VoidCallback onClearDateRange;
  final VoidCallback onClearFilters;

  const _FilterPanel({
    required this.filterType,
    required this.filterCategory,
    required this.filterPayMethod,
    required this.filterDateRange,
    required this.quickDateRange,
    required this.noteController,
    required this.categoryOptions,
    required this.payMethodOptions,
    required this.hasFilters,
    required this.onTypeChanged,
    required this.onCategoryChanged,
    required this.onPayMethodChanged,
    required this.onNoteChanged,
    required this.onPickDateRange,
    required this.onSelectWeek,
    required this.onSelectMonth,
    required this.onClearDateRange,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final controlTextColor = isDark ? Colors.white70 : Colors.black87;
    final controlHintColor = isDark ? Colors.white54 : Colors.black54;
    const double controlHeight = 40;
    const double controlFontSize = 14;
    const BorderRadius controlRadius = BorderRadius.all(Radius.circular(10));
    const OutlineInputBorder controlBorder = OutlineInputBorder(
      borderRadius: controlRadius,
    );

    String dateText = '日期范围';
    if (filterDateRange != null) {
      final fmt = DateFormat('yyyy-MM-dd');
      dateText =
          '${fmt.format(filterDateRange!.start)} ~ ${fmt.format(filterDateRange!.end)}';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? AppColors.cardShadowDark
            : AppColors.cardShadowLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<BillType?>(
            segments: const [
              ButtonSegment<BillType?>(
                value: null,
                label: Text('全部', style: TextStyle(fontSize: controlFontSize)),
              ),
              ButtonSegment<BillType?>(
                value: BillType.expense,
                label: Text('支出', style: TextStyle(fontSize: controlFontSize)),
              ),
              ButtonSegment<BillType?>(
                value: BillType.income,
                label: Text('收入', style: TextStyle(fontSize: controlFontSize)),
              ),
            ],
            selected: {filterType},
            onSelectionChanged: (value) => onTypeChanged(value.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: controlHeight,
                  child: DropdownButtonFormField<String?>(
                    value: filterCategory,
                    isExpanded: true,
                    style: TextStyle(
                      fontSize: controlFontSize,
                      color: controlTextColor,
                    ),
                    decoration: InputDecoration(
                      hintText: '分类',
                      hintStyle: TextStyle(
                        fontSize: controlFontSize,
                        color: controlHintColor,
                      ),
                      border: controlBorder,
                      enabledBorder: controlBorder,
                      focusedBorder: controlBorder,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          '全部',
                          style: TextStyle(
                            fontSize: controlFontSize,
                            color: controlTextColor,
                          ),
                        ),
                      ),
                      ...categoryOptions.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c,
                          child: Text(
                            c,
                            style: TextStyle(
                              fontSize: controlFontSize,
                              color: controlTextColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                    onChanged: onCategoryChanged,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: controlHeight,
                  child: DropdownButtonFormField<String?>(
                    value: filterPayMethod,
                    isExpanded: true,
                    style: TextStyle(
                      fontSize: controlFontSize,
                      color: controlTextColor,
                    ),
                    decoration: InputDecoration(
                      hintText: '支付方式',
                      hintStyle: TextStyle(
                        fontSize: controlFontSize,
                        color: controlHintColor,
                      ),
                      border: controlBorder,
                      enabledBorder: controlBorder,
                      focusedBorder: controlBorder,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          '全部',
                          style: TextStyle(
                            fontSize: controlFontSize,
                            color: controlTextColor,
                          ),
                        ),
                      ),
                      ...payMethodOptions.map(
                        (m) => DropdownMenuItem<String?>(
                          value: m,
                          child: Text(
                            m,
                            style: TextStyle(
                              fontSize: controlFontSize,
                              color: controlTextColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                    onChanged: onPayMethodChanged,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: controlHeight,
                  child: TextField(
                    controller: noteController,
                    onChanged: onNoteChanged,
                    style: const TextStyle(fontSize: controlFontSize),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: const InputDecoration(
                      hintText: '备注',
                      hintStyle: TextStyle(fontSize: controlFontSize),
                      border: controlBorder,
                      enabledBorder: controlBorder,
                      focusedBorder: controlBorder,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: controlHeight,
                child: OutlinedButton.icon(
                  onPressed: onPickDateRange,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, controlHeight),
                    textStyle: const TextStyle(fontSize: controlFontSize),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text(
                    dateText,
                    style: const TextStyle(fontSize: controlFontSize),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('本周', style: TextStyle(fontSize: 14)),
                selected: quickDateRange == 'week',
                onSelected: (_) => onSelectWeek(),
              ),
              ChoiceChip(
                label: const Text('本月', style: TextStyle(fontSize: 14)),
                selected: quickDateRange == 'month',
                onSelected: (_) => onSelectMonth(),
              ),
              if (hasFilters)
                ActionChip(
                  label: const Text('清空筛选', style: TextStyle(fontSize: 14)),
                  onPressed: onClearFilters,
                ),
              if (filterDateRange != null)
                ActionChip(
                  label: const Text('清除日期', style: TextStyle(fontSize: 14)),
                  onPressed: onClearDateRange,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final Bill bill;
  final VoidCallback? onReflect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RecordTile({
    required this.bill,
    required this.onReflect,
    required this.onEdit,
    required this.onDelete,
  });

  IconData _iconFromName(String iconName) {
    switch (iconName) {
      case 'restaurant':
        return Icons.restaurant;
      case 'directions_car':
        return Icons.directions_car;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'movie':
        return Icons.movie;
      case 'home':
        return Icons.home;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'school':
        return Icons.school;
      case 'work':
        return Icons.work;
      case 'emoji_events':
        return Icons.emoji_events;
      case 'handyman':
        return Icons.handyman;
      case 'trending_up':
        return Icons.trending_up;
      case 'redeem':
        return Icons.redeem;
      default:
        return Icons.more_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconName = AppConstants.categoryIcons[bill.category] ?? 'more_horiz';
    final icon = _iconFromName(iconName);
    final isIncome = bill.isIncome;
    final amountColor = isIncome
        ? AppColors.primaryGreen
        : AppColors.expenseRed;
    final prefix = isIncome ? '+' : '-';
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final shadow = isDark
        ? AppColors.cardShadowDark
        : AppColors.cardShadowLight;
    final id = bill.id ?? bill.createdAt.millisecondsSinceEpoch;

    return Slidable(
      key: ValueKey('analysis-bill-$id'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.44,
        children: [
          SlidableAction(
            onPressed: (_) => onEdit(),
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            icon: Icons.edit_rounded,
            label: '编辑',
            borderRadius: BorderRadius.circular(12),
          ),
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            label: '删除',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
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
            const SizedBox(width: 12),
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
                        ? '${bill.payMethod} · ${DateFormat('yyyy-MM-dd').format(bill.date)}'
                        : '${bill.note} · ${bill.payMethod} · ${DateFormat('yyyy-MM-dd').format(bill.date)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$prefix¥${bill.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: amountColor,
                  ),
                ),
                const SizedBox(height: 6),
                if (onReflect != null)
                  InkWell(
                    onTap: onReflect,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '反省',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineAnalysisPanel extends StatelessWidget {
  final bool loading;
  final String? result;
  final String? error;
  final VoidCallback onCollapse;

  const _InlineAnalysisPanel({
    required this.loading,
    required this.result,
    required this.error,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent =
        (result?.isNotEmpty ?? false) || (error?.isNotEmpty ?? false);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!loading && hasContent)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCollapse,
                icon: const Icon(Icons.expand_less_rounded, size: 16),
                label: const Text('收起'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (!loading && hasContent) const SizedBox(height: 4),
          if (loading)
            Row(
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('反省中...'),
              ],
            )
          else if (error != null && error!.isNotEmpty)
            Text(
              error!,
              style: const TextStyle(color: AppColors.expenseRed, height: 1.5),
            )
          else if (result != null && result!.isNotEmpty)
            Text(result!, style: const TextStyle(fontSize: 14, height: 1.6))
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  final bool hasAnyBill;
  final VoidCallback onAdd;
  final VoidCallback onClearFilters;

  const _EmptyRecords({
    required this.hasAnyBill,
    required this.onAdd,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    if (hasAnyBill) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_alt_off_rounded,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 10),
              Text(
                '当前筛选下没有记录',
                style: TextStyle(fontSize: 15, color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onClearFilters,
                child: const Text('清空筛选'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 10),
            Text(
              '还没有账单记录',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('记一笔'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
