import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/notification_service.dart';

/// 通知提醒设置 BottomSheet
class ReminderSettingsSheet extends StatefulWidget {
  const ReminderSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const ReminderSettingsSheet(),
    );
  }

  @override
  State<ReminderSettingsSheet> createState() => _ReminderSettingsSheetState();
}

class _ReminderSettingsSheetState extends State<ReminderSettingsSheet> {
  bool _enabled = true;
  List<String> _times = ['13:00', '20:00'];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await NotificationService.isEnabled();
    final times = await NotificationService.getReminderTimes();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _times = List.from(times);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await NotificationService.setEnabled(_enabled);
    await NotificationService.setReminderTimes(_times);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提醒设置已保存')),
      );
    }
  }

  Future<void> _pickTime(int index) async {
    final parts = _times[index].split(':');
    final hour = int.tryParse(parts[0]) ?? 13;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked != null && mounted) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      setState(() {
        while (_times.length <= index) {
          _times.add('13:00');
        }
        _times[index] = '$h:$m';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('通知提醒', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
                    Icon(Icons.notifications_outlined, color: AppColors.primaryGreen),
                    const SizedBox(width: 12),
                    const Text(
                      '通知提醒',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '到时间提醒你记账，避免遗漏',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 24),
                // 开关
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('开启提醒'),
                    Switch(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                      activeTrackColor: AppColors.primaryGreen.withOpacity(0.5),
                      activeThumbColor: AppColors.primaryGreen,
                    ),
                  ],
                ),
                if (_enabled) ...[
                  const SizedBox(height: 16),
                  const Text('提醒时间', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  ...List.generate(_times.length.clamp(0, 2), (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => _pickTime(i),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF252B28)
                                : AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.schedule, color: AppColors.primaryGreen, size: 20),
                              const SizedBox(width: 12),
                              Text(_times[i], style: const TextStyle(fontSize: 16)),
                              const Spacer(),
                              Icon(Icons.edit, color: Colors.grey[500], size: 18),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primaryGreen),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('保存'),
                ),
              ],
            ),
    );
  }
}
