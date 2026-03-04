import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/consult_session.dart';

const _kSessions = 'consult_sessions';
const _kCurrentSessionId = 'consult_current_session_id';
const _kMaxSessions = 50;

class ConsultSessionStorage {
  static List<ConsultSession> _sessions = [];
  static String? _currentSessionId;

  static List<ConsultSession> get sessions => List.unmodifiable(_sessions);

  static String? get currentSessionId => _currentSessionId;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final listStr = prefs.getString(_kSessions);
    if (listStr != null && listStr.isNotEmpty) {
      try {
        final list = jsonDecode(listStr) as List<dynamic>?;
        _sessions = list
            ?.map((e) => ConsultSession.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
            [];
        _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } catch (_) {
        _sessions = [];
      }
    } else {
      _sessions = [];
    }
    _currentSessionId = prefs.getString(_kCurrentSessionId);
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _sessions.map((s) => s.toJson()).toList();
    await prefs.setString(_kSessions, jsonEncode(list));
    final cid = _currentSessionId;
    if (cid != null) {
      await prefs.setString(_kCurrentSessionId, cid);
    } else {
      await prefs.remove(_kCurrentSessionId);
    }
  }

  static Future<void> setCurrentSession(String? id) async {
    _currentSessionId = id;
    await save();
  }

  static ConsultSession? getCurrentSession() {
    if (_currentSessionId == null) return null;
    try {
      return _sessions.firstWhere((s) => s.id == _currentSessionId);
    } catch (_) {
      return null;
    }
  }

  /// 获取或创建当前会话，进入页面时调用（需先 await load()）
  static Future<ConsultSession> ensureCurrentSession() async {
    final cur = getCurrentSession();
    if (cur != null) return cur;
    return createNewSession();
  }

  /// 新建会话
  static Future<ConsultSession> createNewSession() async {
    final newOne = ConsultSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: '新对话',
      messages: [],
      updatedAt: DateTime.now(),
    );
    _sessions.insert(0, newOne);
    if (_sessions.length > _kMaxSessions) {
      _sessions = _sessions.take(_kMaxSessions).toList();
    }
    _currentSessionId = newOne.id;
    await save();
    return newOne;
  }

  /// 切换会话
  static Future<ConsultSession?> switchToSession(String id) async {
    try {
      final s = _sessions.firstWhere((s) => s.id == id);
      _currentSessionId = id;
      await save();
      return s;
    } catch (_) {
      return null;
    }
  }

  /// 追加消息并保存
  static Future<void> appendMessage(String sessionId, String role, String content, {String? reasoning}) async {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];
    final updated = s.copyWith(
      messages: [...s.messages, ConsultMessage(role: role, content: content, reasoning: reasoning)],
      updatedAt: DateTime.now(),
      title: role == 'user' && s.title == '新对话'
          ? (content.length > 20 ? '${content.substring(0, 20)}...' : content)
          : s.title,
    );
    _sessions[idx] = updated;
    _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await save();
  }

  /// 更新会话中的最后一条 assistant 消息（流式追加时）
  static Future<void> updateLastAssistantMessage(String sessionId, String content) async {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    final s = _sessions[idx];
    final msgs = List<ConsultMessage>.from(s.messages);
    if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
      msgs[msgs.length - 1] = ConsultMessage(role: 'assistant', content: content);
    } else {
      msgs.add(ConsultMessage(role: 'assistant', content: content));
    }
    _sessions[idx] = s.copyWith(messages: msgs, updatedAt: DateTime.now());
    await save();
  }

  /// 删除会话
  static Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    if (_currentSessionId == id) {
      _currentSessionId = _sessions.isNotEmpty ? _sessions.first.id : null;
    }
    await save();
  }
}
