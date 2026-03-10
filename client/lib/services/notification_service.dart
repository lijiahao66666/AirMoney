import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

String _normalizeReminderTime(String value) {
  final parts = value.split(':');
  final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 13 : 13;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final safeHour = hour.clamp(0, 23);
  final safeMinute = minute.clamp(0, 59);
  return '${safeHour.toString().padLeft(2, '0')}:${safeMinute.toString().padLeft(2, '0')}';
}

class ReminderEntry {
  const ReminderEntry({required this.time, required this.enabled});

  final String time;
  final bool enabled;

  ReminderEntry copyWith({String? time, bool? enabled}) {
    return ReminderEntry(
      time: time ?? this.time,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'time': _normalizeReminderTime(time),
      'enabled': enabled,
    };
  }

  factory ReminderEntry.fromJson(Map<String, dynamic> json) {
    final rawEnabled = json['enabled'];
    final parsedEnabled = rawEnabled is bool
        ? rawEnabled
        : rawEnabled?.toString().toLowerCase() == 'true';
    return ReminderEntry(
      time: _normalizeReminderTime(json['time']?.toString() ?? '13:00'),
      enabled: parsedEnabled,
    );
  }
}

class NotificationService {
  NotificationService._();

  static const _kEntries = 'reminder_entries';
  static const _kLegacyEnabled = 'reminder_enabled';
  static const _kLegacyTimes = 'reminder_times';

  static const _channelId = 'airmoney_reminder_v3';
  static const _channelName = '记账提醒';
  static const _notificationIcon = 'ic_stat_airmoney';
  static const _notificationIdBase = 1000;
  static const _maxReminderCount = 12;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static Future<void>? _initializing;

  static List<ReminderEntry> _defaultEntries() {
    return const <ReminderEntry>[
      ReminderEntry(time: '13:00', enabled: false),
      ReminderEntry(time: '20:00', enabled: false),
    ];
  }

  static List<ReminderEntry> _sanitizeEntries(List<ReminderEntry> entries) {
    return entries
        .take(24)
        .map(
          (entry) => ReminderEntry(
            time: _normalizeReminderTime(entry.time),
            enabled: entry.enabled,
          ),
        )
        .toList();
  }

  static Future<List<ReminderEntry>> _readEntries(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_kEntries);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final parsed = <ReminderEntry>[];
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              parsed.add(ReminderEntry.fromJson(item));
            } else if (item is Map) {
              parsed.add(
                ReminderEntry.fromJson(item.cast<String, dynamic>()),
              );
            }
          }
          final sanitized = _sanitizeEntries(parsed);
          return sanitized;
        }
      } catch (_) {
        // Ignore malformed payload and fallback.
      }
    }

    final legacyCsv = prefs.getString(_kLegacyTimes);
    final legacyTimes = legacyCsv == null || legacyCsv.trim().isEmpty
        ? <String>[]
        : legacyCsv
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();

    final migrated = (legacyTimes.isEmpty
            ? _defaultEntries().map((entry) => entry.time).toList()
            : legacyTimes)
        .map((time) => ReminderEntry(time: time, enabled: false))
        .toList();

    final sanitized = _sanitizeEntries(migrated);
    await prefs.setString(
      _kEntries,
      jsonEncode(sanitized.map((entry) => entry.toJson()).toList()),
    );
    await prefs.remove(_kLegacyEnabled);
    await prefs.remove(_kLegacyTimes);
    return sanitized;
  }

  static Future<void> _writeEntries(List<ReminderEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final sanitized = _sanitizeEntries(entries);
    await prefs.setString(
      _kEntries,
      jsonEncode(sanitized.map((entry) => entry.toJson()).toList()),
    );
  }

  static Future<List<ReminderEntry>> getReminderEntries() async {
    final prefs = await SharedPreferences.getInstance();
    return _readEntries(prefs);
  }

  static Future<void> setReminderEntries(List<ReminderEntry> entries) async {
    await _writeEntries(entries);
    if (kIsWeb) return;
    await _ensureInitialized();
    await _scheduleAll();
  }

  // Legacy compatibility.
  static Future<bool> isEnabled() async {
    final entries = await getReminderEntries();
    return entries.any((entry) => entry.enabled);
  }

  // Legacy compatibility.
  static Future<void> setEnabled(bool enabled) async {
    final existing = await getReminderEntries();
    final source = existing.isEmpty ? _defaultEntries() : existing;
    final updated = source
        .map((entry) => entry.copyWith(enabled: enabled))
        .toList();
    await setReminderEntries(updated);
  }

  // Legacy compatibility.
  static Future<List<String>> getReminderTimes() async {
    final entries = await getReminderEntries();
    return entries.map((entry) => entry.time).toList();
  }

  // Legacy compatibility.
  static Future<void> setReminderTimes(List<String> times) async {
    final normalizedTimes = (times.isEmpty
            ? _defaultEntries().map((entry) => entry.time).toList()
            : times)
        .map(_normalizeReminderTime)
        .toList();
    final existing = await getReminderEntries();
    final updated = <ReminderEntry>[];
    for (var i = 0; i < normalizedTimes.length; i++) {
      final enabled = i < existing.length ? existing[i].enabled : false;
      updated.add(ReminderEntry(time: normalizedTimes[i], enabled: enabled));
    }
    await setReminderEntries(updated);
  }

  static Future<bool> requestPermissionIfNeeded() async {
    if (kIsWeb) return false;
    await _ensureInitialized();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: false,
      );
      return granted ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final macPlugin = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final granted = await macPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: false,
      );
      return granted ?? false;
    }

    return true;
  }

  static Future<void> init() async {
    if (kIsWeb) return;
    await _ensureInitialized();
    await _scheduleAll();
  }

  static Future<void> _ensureInitialized() async {
    if (kIsWeb || _initialized) return;
    if (_initializing != null) {
      await _initializing;
      return;
    }

    _initializing = () async {
      tz_data.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
      } catch (_) {
        // Ignore timezone fallback.
      }

      const android = AndroidInitializationSettings(_notificationIcon);
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: true,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );

      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      _initialized = true;
    }();

    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // Open app from system notification.
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _ensureInitialized();
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('[NotificationService] cancelAll error: $e');
    }
  }

  static tz.TZDateTime _nextOccurrence(String time) {
    final normalized = _normalizeReminderTime(time);
    final parts = normalized.split(':');
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
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static Future<void> _scheduleAll() async {
    if (kIsWeb) return;
    await _ensureInitialized();

    await cancelAll();

    final entries = await getReminderEntries();
    final enabledEntries = entries
        .where((entry) => entry.enabled)
        .take(_maxReminderCount)
        .toList();
    if (enabledEntries.isEmpty) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final notificationsEnabled = await androidPlugin?.areNotificationsEnabled();
      if (notificationsEnabled == false) {
        debugPrint(
          '[NotificationService] notifications disabled by system permission',
        );
        return;
      }
    }

    for (var i = 0; i < enabledEntries.length; i++) {
      final entry = enabledEntries[i];
      final scheduledDate = _nextOccurrence(entry.time);

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '到时间提醒你记账',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: _notificationIcon,
          channelShowBadge: true,
          number: i + 1,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          badgeNumber: i + 1,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          badgeNumber: i + 1,
        ),
      );

      try {
        await _plugin.zonedSchedule(
          id: _notificationIdBase + i,
          title: '哎呀，钱！',
          body: '该记账啦～别忘了记一笔',
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e, st) {
        debugPrint('[NotificationService] schedule[$i] error: $e');
        debugPrint('$st');
      }
    }
  }
}
