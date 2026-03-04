import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants.dart';
import '../../../data/models/bill.dart';
import '../../providers/bill_provider.dart';

class AddBillPage extends StatefulWidget {
  const AddBillPage({super.key});

  @override
  State<AddBillPage> createState() => _AddBillPageState();
}

class _AddBillPageState extends State<AddBillPage> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  BillType _type = BillType.expense;
  late String _category;
  String _payMethod = AppConstants.payMethods.first;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _category = AppConstants.expenseCategories.first;
  }

  List<String> get _categories =>
      _type == BillType.expense ? AppConstants.expenseCategories : AppConstants.incomeCategories;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效金额')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final bill = Bill(
        amount: amount,
        category: _category,
        note: _noteController.text.trim(),
        payMethod: _payMethod,
        date: _date,
        type: _type,
      );
      await context.read<BillProvider>().addBill(bill);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onTypeChanged(BillType t) {
    setState(() {
      _type = t;
      _category = _categories.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记一笔'),
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
            const Text('类型', style: TextStyle(fontSize: 14, color: AppColors.neutralGrey)),
            const SizedBox(height: 8),
            SegmentedButton<BillType>(
              segments: const [
                ButtonSegment(
                  value: BillType.expense,
                  label: Text('支出'),
                  icon: Icon(Icons.trending_down, size: 18),
                ),
                ButtonSegment(
                  value: BillType.income,
                  label: Text('收入'),
                  icon: Icon(Icons.trending_up, size: 18),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => _onTypeChanged(s.first),
            ),
            const SizedBox(height: 24),
            const Text('金额', style: TextStyle(fontSize: 14, color: AppColors.neutralGrey)),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '0',
                prefixText: '¥ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('分类', style: TextStyle(fontSize: 14, color: AppColors.neutralGrey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((c) {
                final selected = _category == c;
                return ChoiceChip(
                  label: Text(c),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = c),
                  selectedColor: AppColors.primaryLight,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            const Text('备注', style: TextStyle(fontSize: 14, color: AppColors.neutralGrey)),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                hintText: '选填',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('支付方式', style: TextStyle(fontSize: 14, color: AppColors.neutralGrey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _payMethod,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: AppConstants.payMethods.map((p) {
                return DropdownMenuItem(value: p, child: Text(p));
              }).toList(),
              onChanged: (v) => setState(() => _payMethod = v ?? _payMethod),
            ),
            const SizedBox(height: 24),
            const Text('日期', style: TextStyle(fontSize: 14, color: AppColors.neutralGrey)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(DateFormat('yyyy-MM-dd').format(_date)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
