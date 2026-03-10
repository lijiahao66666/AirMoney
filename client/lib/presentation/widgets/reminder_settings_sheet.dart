import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/notification_service.dart';

/// 通知提醒设置 BottomSheet
class ReminderSettingsSheet extends StatefulWidget {
  const ReminderSettingsSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const ReminderSettingsSheet(),
    );
    return result ?? false;
  }

  @override
  State<ReminderSettingsSheet> createState() => _ReminderSettingsSheetState();
}

class _ReminderSettingsSheetState extends State<ReminderSettingsSheet> {
  List<ReminderEntry> _entries = const <ReminderEntry>[];
  bool _loading = true;
  bool _saving = false;

  bool get _hasEnabledEntry => _entries.any((entry) => entry.enabled);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await NotificationService.getReminderEntries();
    if (!mounted) return;
    setState(() {
      _entries = List<ReminderEntry>.from(entries);
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      if (_hasEnabledEntry) {
        final granted = await NotificationService.requestPermissionIfNeeded();
        if (!granted) {
          throw Exception('未授予通知权限，请先在系统设置中允许通知');
        }
      }

      await NotificationService.setReminderEntries(_entries);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$msg')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _suggestNextTime() {
    if (_entries.isEmpty) return '13:00';
    final last = _entries.last.time.split(':');
    final hour = last.isNotEmpty ? int.tryParse(last[0]) ?? 13 : 13;
    final minute = last.length > 1 ? int.tryParse(last[1]) ?? 0 : 0;
    final nextHour = (hour + 1) % 24;
    return '${nextHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  void _addEntry() {
    if (_entries.length >= 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多添加 12 个提醒时间')),
      );
      return;
    }
    setState(() {
      _entries = List<ReminderEntry>.from(_entries)
        ..add(ReminderEntry(time: _suggestNextTime(), enabled: false));
    });
  }

  void _removeEntry(int index) {
    setState(() {
      final next = List<ReminderEntry>.from(_entries);
      next.removeAt(index);
      _entries = next;
    });
  }

  void _toggleEntry(int index, bool enabled) {
    setState(() {
      final next = List<ReminderEntry>.from(_entries);
      next[index] = next[index].copyWith(enabled: enabled);
      _entries = next;
    });
  }

  Future<void> _pickTime(int index) async {
    final parts = _entries[index].time.split(':');
    final hour = int.tryParse(parts[0]) ?? 13;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked == null || !mounted) return;

    final h = picked.hour.toString().padLeft(2, '0');
    final m = picked.minute.toString().padLeft(2, '0');
    setState(() {
      final next = List<ReminderEntry>.from(_entries);
      next[index] = next[index].copyWith(time: '$h:$m');
      _entries = next;
    });
  }

  Widget _buildEntryItem(int index) {
    final entry = _entries[index];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xFF252B28) : AppColors.primaryLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _pickTime(index),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      color: AppColors.primaryGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      entry.time,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.edit, color: Colors.grey[500], size: 17),
                  ],
                ),
              ),
            ),
          ),
          Switch(
            value: entry.enabled,
            onChanged: (v) => _toggleEntry(index, v),
            activeTrackColor: AppColors.primaryGreen.withValues(alpha: 0.5),
            activeThumbColor: AppColors.primaryGreen,
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _removeEntry(index),
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '通知提醒',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              'Web 平台暂不支持本地通知提醒，请在手机端使用',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewPadding.bottom + 24,
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_outlined,
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '通知提醒',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '每个提醒时间可单独开关，新增时间默认关闭',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 18),
                if (_entries.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF252B28)
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '还没有提醒时间，点击下方“新增提醒时间”添加',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  )
                else
                  ...List<Widget>.generate(_entries.length, _buildEntryItem),
                const SizedBox(height: 2),
                OutlinedButton.icon(
                  onPressed: _addEntry,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增提醒时间'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('保存'),
                ),
              ],
            ),
    );
  }
}
