import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
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
  bool _billsLoading = false;
  List<Bill> _allBills = [];
  BillType? _filterType;
  String? _filterCategory;
  String? _filterPayMethod;
  DateTimeRange? _filterDateRange;
  final TextEditingController _noteFilterController = TextEditingController();
  bool _reminderEnabled = false;
  String? _nextReminderTime;

  @override
  void initState() {
    super.initState();
    _loadTotals();
    _loadReminderPreview();
  }

  @override
  void dispose() {
    _noteFilterController.dispose();
    super.dispose();
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
  Future<void> _loadReminderPreview() async {
    final entries = await NotificationService.getReminderEntries();
    final enabledTimes = entries
        .where((entry) => entry.enabled)
        .map((entry) => entry.time)
        .toList();

    final nextReminder = _findNextReminderTime(enabledTimes);
    if (!mounted) return;
    setState(() {
      _reminderEnabled = enabledTimes.isNotEmpty;
      _nextReminderTime = nextReminder;
    });
  }

  String? _findNextReminderTime(List<String> times) {
    if (times.isEmpty) return null;
    final now = DateTime.now();
    DateTime? nextDateTime;
    String? nextTime;

    for (final time in times) {
      final parts = time.split(':');
      final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 13 : 13;
      final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

      var candidate = DateTime(now.year, now.month, now.day, hour, minute);
      if (!candidate.isAfter(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }

      if (nextDateTime == null || candidate.isBefore(nextDateTime)) {
        nextDateTime = candidate;
        nextTime = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      }
    }

    return nextTime;
  }

  Future<void> _openReminderSettings() async {
    final saved = await ReminderSettingsSheet.show(context);
    if (!mounted) return;
    await _loadReminderPreview();
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒设置已保存')),
      );
    }
  }

  Future<void> _loadBills() async {
    if (mounted) {
      setState(() => _billsLoading = true);
    }
    try {
      final bills = await context.read<BillProvider>().getAllBills();
      if (!mounted) return;
      setState(() {
        _allBills = bills;
      });
    } finally {
      if (mounted) {
        setState(() => _billsLoading = false);
      }
    }
  }

  Future<void> _refreshAllData() async {
    await Future.wait([
      _loadTotals(),
      context.read<BillProvider>().loadRecentBills(),
      _loadReminderPreview(),
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

  List<Bill> get _filteredBills {
    final noteKeyword = _noteFilterController.text.trim().toLowerCase();
    final range = _filterDateRange;
    final start = range?.start;
    final end = range?.end;
    return _allBills.where((bill) {
      if (_filterType != null && bill.type != _filterType) return false;
      if (_filterCategory != null &&
          _filterCategory!.isNotEmpty &&
          bill.category != _filterCategory) {
        return false;
      }
      if (_filterPayMethod != null &&
          _filterPayMethod!.isNotEmpty &&
          bill.payMethod != _filterPayMethod) {
        return false;
      }
      if (noteKeyword.isNotEmpty &&
          !bill.note.toLowerCase().contains(noteKeyword)) {
        return false;
      }
      if (start != null && end != null) {
        final d = DateTime(bill.date.year, bill.date.month, bill.date.day);
        final rangeStart = DateTime(start.year, start.month, start.day);
        final rangeEnd = DateTime(end.year, end.month, end.day);
        if (d.isBefore(rangeStart) || d.isAfter(rangeEnd)) {
          return false;
        }
      }
      return true;
    }).toList();
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
    if (picked != null && mounted) {
      setState(() {
        _filterDateRange = picked;
        _recentBillsExpanded = false;
      });
    }
  }

  void _clearFilters() {
    _noteFilterController.clear();
    setState(() {
      _filterType = null;
      _filterCategory = null;
      _filterPayMethod = null;
      _filterDateRange = null;
      _recentBillsExpanded = false;
    });
  }

  Future<void> _deleteRecentBill(Bill bill) async {
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

    final bp = context.read<BillProvider>();
    final deleted = await bp.deleteBill(id);
    if (!mounted) return;
    if (deleted) {
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

  Future<void> _editRecentBill(Bill bill) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AddBillPage(editingBill: bill)));
    if (!mounted) return;
    await _refreshAllData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;

    return Scaffold(
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              '浙ICP备2026011869号-4A',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: (isDark ? Colors.white70 : AppColors.deepText)
                    .withOpacity(0.35),
              ),
            ),
          ),
        ),
      ),
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
                      ? [
                          AppColors.primaryGreen,
                          AppColors.primaryGreen.withOpacity(0.85),
                        ]
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
                  color: (isDark ? Colors.white70 : AppColors.deepText)
                      .withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAllData,
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
                  if (mounted) await _refreshAllData();
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
                  onReminderTap: () {
                    _openReminderSettings();
                  },
                  isDark: isDark,
                  reminderEnabled: _reminderEnabled,
                  nextReminderTime: _nextReminderTime,
                ),
              ),
              const SizedBox(height: 24),

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
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const AnalysisPage()));
}

void _openConsultOrPrompt(BuildContext context) {
  final pp = context.read<PointsProvider>();
  if (pp.balance <= 0) {
    _showPointsRequiredSheet(context, '该不该花');
    return;
  }
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ConsultPage()));
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

class _BillFilterPanel extends StatelessWidget {
  final BillType? filterType;
  final String? filterCategory;
  final String? filterPayMethod;
  final DateTimeRange? filterDateRange;
  final TextEditingController noteController;
  final List<String> categoryOptions;
  final ValueChanged<BillType?> onTypeChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onPayMethodChanged;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onPickDateRange;
  final VoidCallback onClear;

  const _BillFilterPanel({
    required this.filterType,
    required this.filterCategory,
    required this.filterPayMethod,
    required this.filterDateRange,
    required this.noteController,
    required this.categoryOptions,
    required this.onTypeChanged,
    required this.onCategoryChanged,
    required this.onPayMethodChanged,
    required this.onNoteChanged,
    required this.onPickDateRange,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final shadow = isDark
        ? AppColors.cardShadowDark
        : AppColors.cardShadowLight;
    final textColor = isDark ? Colors.white70 : AppColors.deepText;
    final rangeText = filterDateRange == null
        ? '不限日期'
        : '${DateFormat('yyyy-MM-dd').format(filterDateRange!.start)} ~ ${DateFormat('yyyy-MM-dd').format(filterDateRange!.end)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '筛选',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const Spacer(),
              TextButton(onPressed: onClear, child: const Text('重置')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: filterType == null,
                onSelected: (_) => onTypeChanged(null),
              ),
              ChoiceChip(
                label: const Text('支出'),
                selected: filterType == BillType.expense,
                onSelected: (_) => onTypeChanged(BillType.expense),
              ),
              ChoiceChip(
                label: const Text('收入'),
                selected: filterType == BillType.income,
                onSelected: (_) => onTypeChanged(BillType.income),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: filterCategory ?? '',
                  decoration: const InputDecoration(
                    labelText: '分类',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部分类')),
                    ...categoryOptions.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: (v) =>
                      onCategoryChanged((v == null || v.isEmpty) ? null : v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: filterPayMethod ?? '',
                  decoration: const InputDecoration(
                    labelText: '支付方式',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部方式')),
                    ...AppConstants.payMethods.map(
                      (p) => DropdownMenuItem(value: p, child: Text(p)),
                    ),
                  ],
                  onChanged: (v) =>
                      onPayMethodChanged((v == null || v.isEmpty) ? null : v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: noteController,
                  onChanged: onNoteChanged,
                  decoration: const InputDecoration(
                    labelText: '备注关键词（可选）',
                    hintText: '输入关键词筛选备注',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: onPickDateRange,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 14,
                    ),
                  ),
                  icon: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text(
                    rangeText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyFilteredHint extends StatelessWidget {
  final VoidCallback onClearFilters;

  const _EmptyFilteredHint({required this.onClearFilters});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.filter_alt_off_rounded, color: Colors.grey[600], size: 30),
          const SizedBox(height: 8),
          Text('当前筛选条件下没有记录', style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onClearFilters,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('清空筛选'),
          ),
        ],
      ),
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
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 48,
            color: Colors.orange[300],
          ),
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
                    WalletSheet.show(
                      context,
                      pp.balance,
                      () => pp.syncFromServer(),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                  ),
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
  final bool reminderEnabled;
  final String? nextReminderTime;

  const _PointsAndReminderCard({
    required this.balance,
    required this.onPointsTap,
    required this.onReminderTap,
    required this.isDark,
    required this.reminderEnabled,
    required this.nextReminderTime,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;
    final shadow = isDark
        ? AppColors.cardShadowDark
        : AppColors.cardShadowLight;
    final dividerColor = (isDark ? Colors.white : Colors.black).withOpacity(0.08);
    final reminderText = reminderEnabled
        ? (nextReminderTime == null || nextReminderTime!.isEmpty
              ? '已开启'
              : '下次 $nextReminderTime')
        : '已关闭';
    final reminderTextColor = reminderEnabled
        ? AppColors.primaryGreen
        : (isDark ? Colors.white70 : Colors.black54);

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
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.notifications_active_rounded,
                          color: AppColors.primaryGreen,
                          size: 22,
                        ),
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
                                color: (isDark ? Colors.white : Colors.black87)
                                    .withOpacity(0.8),
                              ),
                            ),
                            Text(
                              reminderText,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: reminderTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey[400],
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(width: 1, height: 40, color: dividerColor),
            Expanded(
              child: InkWell(
                onTap: onPointsTap,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.pointsGold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          color: AppColors.pointsGold,
                          size: 22,
                        ),
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
                                color: (isDark ? Colors.white : Colors.black87)
                                    .withOpacity(0.8),
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
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey[400],
                        size: 18,
                      ),
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
    final shadow = isDark
        ? AppColors.cardShadowDark
        : AppColors.cardShadowLight;
    final accentColor = isPrimary
        ? AppColors.primaryGreen
        : AppColors.pointsGold;
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
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
    final shadow = isDark
        ? AppColors.cardShadowDark
        : AppColors.cardShadowLight;
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
                  color: (isDark ? Colors.white : Colors.black).withOpacity(
                    0.08,
                  ),
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
            Text(
              label,
              style: TextStyle(fontSize: 13, color: AppColors.neutralGrey),
            ),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BillTile({
    required this.bill,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        key: ValueKey('bill-$id'),
        startActionPane: ActionPane(
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
                            ? '${bill.payMethod} · ${DateFormat('yyyy-MM-dd').format(bill.date)}'
                            : '${bill.note} · ${bill.payMethod} · ${DateFormat('yyyy-MM-dd').format(bill.date)}',
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
    final shadow = isDark
        ? AppColors.cardShadowDark
        : AppColors.cardShadowLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Container(
        width: double.infinity,
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
              child: Icon(
                Icons.savings_rounded,
                size: 56,
                color: AppColors.primaryGreen.withOpacity(0.8),
              ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

