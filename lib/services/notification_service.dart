import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// 通知提醒服务：到时间提醒用户记账
class NotificationService {
  NotificationService._();

  static const _kEnabled = 'reminder_enabled';
  static const _kTimes = 'reminder_times'; // JSON array of "HH:mm"
  static const _channelId = 'airmoney_reminder';
  static const _channelName = '记账提醒';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static final List<int> _notificationIds = [1001, 1002]; // 支持最多 2 个时间点

  /// 是否启用
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? true;
  }

  /// 设置启用状态
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    if (enabled) {
      await _scheduleAll();
    } else {
      await cancelAll();
    }
  }

  /// 获取提醒时间列表，格式 ["13:00", "20:00"]
  static Future<List<String>> getReminderTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kTimes);
    if (json == null || json.isEmpty) {
      return ['13:00', '20:00'];
    }
    try {
      final list = (json.split(',')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (list.isEmpty) return ['13:00', '20:00'];
      return list;
    } catch (_) {
      return ['13:00', '20:00'];
    }
  }

  /// 设置提醒时间
  static Future<void> setReminderTimes(List<String> times) async {
    if (times.isEmpty) times = ['13:00', '20:00'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTimes, times.join(','));
    if (await isEnabled()) {
      await _scheduleAll();
    }
  }

  /// 初始化（在 main 中调用）
  static Future<void> init() async {
    if (kIsWeb) return;

    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      // 忽略时区设置失败
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }

    if (await isEnabled()) {
      await _scheduleAll();
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // 用户点击通知可打开应用，由系统处理
  }

  /// 取消所有已调度的提醒
  static Future<void> cancelAll() async {
    for (final id in _notificationIds) {
      await _plugin.cancel(id);
    }
  }

  static Future<void> _scheduleAll() async {
    await cancelAll();

    final times = await getReminderTimes();
    for (var i = 0; i < times.length && i < _notificationIds.length; i++) {
      final timeStr = times[i];
      final parts = timeStr.split(':');
      if (parts.length < 2) continue;
      final hour = int.tryParse(parts[0]) ?? 13;
      final minute = int.tryParse(parts[1]) ?? 0;

      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '到时间提醒你记账',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
        ),
      );

      try {
        await _plugin.zonedSchedule(
          _notificationIds[i],
          '哎呀，钱！',
          '该记账啦～别忘了记一笔',
          scheduled,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        debugPrint('[NotificationService] schedule error: $e');
      }
    }
  }
}
