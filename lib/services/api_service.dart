import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

/// 流式输出块（含思考内容、正文、积分）
class ChatStreamChunk {
  final String content;
  final String? reasoningContent;
  final bool isReasoning;
  final bool isComplete;
  final int? pointsBalance;

  ChatStreamChunk({
    required this.content,
    this.reasoningContent,
    this.isReasoning = false,
    this.isComplete = false,
    this.pointsBalance,
  });
}

/// 与后端 API 交互（混元代理、积分、登录）
/// 后端可与 AirRead 共用，或使用 AirMoney 独立 server
class ApiService {
  static const _prefDeviceId = 'device_id';

  static String get proxyUrl => const String.fromEnvironment(
        'AIRMONEY_API_PROXY_URL',
        defaultValue: 'http://localhost:9001',
      );

  static String get apiKey => const String.fromEnvironment(
        'AIRMONEY_API_KEY',
        defaultValue: '',
      );

  static String _deviceId = '';

  static String get deviceId => _deviceId;

  static Future<void> initDeviceId() async {
    if (_deviceId.isNotEmpty) return;
    if (!kIsWeb) {
      try {
        final info = DeviceInfoPlugin();
        if (defaultTargetPlatform == TargetPlatform.android) {
          final android = await info.androidInfo;
          _deviceId = android.id.isNotEmpty ? android.id : android.fingerprint;
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          final ios = await info.iosInfo;
          _deviceId = ios.identifierForVendor ?? '';
        }
      } catch (e) {
        debugPrint('[ApiService] device_info error: $e');
      }
    }
    if (_deviceId.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final stored = (prefs.getString(_prefDeviceId) ?? '').trim();
      if (stored.isNotEmpty) {
        _deviceId = stored;
      } else {
        _deviceId = const Uuid().v4();
        await prefs.setString(_prefDeviceId, _deviceId);
      }
    }
  }

  static Map<String, String> headers({String? authToken}) {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'X-Device-Id': _deviceId,
    };
    if (apiKey.trim().isNotEmpty) h['X-Api-Key'] = apiKey;
    if (authToken != null && authToken.isNotEmpty) {
      h['X-Auth-Token'] = authToken;
    }
    return h;
  }

  /// 调用混元 ChatCompletions（非流式）
  static Future<String> chatCompletions({
    required List<Map<String, String>> messages,
    String? authToken,
  }) async {
    final url = Uri.parse('$proxyUrl/');
    final payload = {
      'host': 'hunyuan.tencentcloudapi.com',
      'service': 'hunyuan',
      'action': 'ChatCompletions',
      'version': '2023-09-01',
      'region': 'ap-guangzhou',
      'stream': false,
      'payload': {
        'Model': 'hunyuan-2.0-instruct-20251111',
        'Stream': false,
        'Messages': messages.map((m) => {
              'Role': m['role']!,
              'Content': m['content'] ?? '',
            }).toList(),
      },
    };
    final resp = await http
        .post(
          url,
          headers: headers(authToken: authToken),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      try {
        final err = jsonDecode(resp.body);
        final msg = err['message'] ?? err['error'] ?? resp.body;
        throw ApiException(msg.toString());
      } catch (e) {
        if (e is ApiException) rethrow;
        throw ApiException('请求失败: ${resp.statusCode}');
      }
    }
    final decoded = jsonDecode(resp.body);
    final choices = decoded['Choices'] ?? decoded['Response']?['Choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final msg = first['Message'] ?? first;
        final content = msg is Map ? msg['Content'] : null;
        if (content != null) return content.toString();
      }
    }
    return '';
  }

  /// 流式输出块
  static void Function(int)? onPointsBalanceChanged;

  /// 调用混元 ChatCompletions（流式，思考模型 + 搜索增强）
  static Stream<ChatStreamChunk> chatCompletionsStream({
    required List<Map<String, String>> messages,
    String? authToken,
    String model = 'hunyuan-2.0-thinking-20251109',
  }) async* {
    final url = Uri.parse('$proxyUrl/');
    final payload = {
      'host': 'hunyuan.tencentcloudapi.com',
      'service': 'hunyuan',
      'action': 'ChatCompletions',
      'version': '2023-09-01',
      'region': 'ap-guangzhou',
      'stream': true,
      'payload': {
        'Model': model,
        'Stream': true,
        'Messages': messages.map((m) => {
              'Role': m['role']!,
              'Content': m['content'] ?? '',
            }).toList(),
        'EnableEnhancement': true,
        'ForceSearchEnhancement': true,
      },
    };
    final request = http.Request('POST', url);
    request.headers.addAll(headers(authToken: authToken));
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode(payload);

    final client = http.Client();
    late http.StreamedResponse streamedResp;
    try {
      streamedResp = await client.send(request).timeout(const Duration(seconds: 120));
    } catch (e) {
      client.close();
      rethrow;
    }

    if (streamedResp.statusCode < 200 || streamedResp.statusCode >= 300) {
      client.close();
      final body = await streamedResp.stream.toBytes();
      final str = utf8.decode(body);
      try {
        final err = jsonDecode(str);
        final msg = err['message'] ?? err['error'] ?? str;
        throw ApiException(msg.toString());
      } catch (e) {
        if (e is ApiException) rethrow;
        throw ApiException('请求失败: ${streamedResp.statusCode}');
      }
    }

    final transformer = utf8.decoder;
    String buffer = '';
    try {
      await for (final chunk in streamedResp.stream.transform(transformer)) {
        buffer += chunk;
        while (true) {
          final idx = buffer.indexOf('\n');
          if (idx == -1) break;
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (line.isEmpty) continue;
          final yielded = _processSseLine(line);
          for (final c in yielded) {
            if (c.pointsBalance != null) {
              onPointsBalanceChanged?.call(c.pointsBalance!);
            }
            yield c;
          }
        }
      }
      if (buffer.trim().isNotEmpty) {
        for (final c in _processSseLine(buffer.trim())) {
          if (c.pointsBalance != null) onPointsBalanceChanged?.call(c.pointsBalance!);
          yield c;
        }
      }
      yield ChatStreamChunk(content: '', isComplete: true);
    } finally {
      client.close();
    }
  }

  static Iterable<ChatStreamChunk> _processSseLine(String line) sync* {
    String jsonStr;
    if (line.startsWith('data: ')) {
      jsonStr = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      jsonStr = line.substring(5).trim();
    } else {
      return;
    }
    if (jsonStr == '[DONE]') {
      yield ChatStreamChunk(content: '', isComplete: true);
      return;
    }
    try {
      final json = jsonDecode(jsonStr);
      if (json is! Map) return;

      final pointsBalance = json['PointsBalance'];
      if (pointsBalance != null) {
        final b = (pointsBalance is num) ? pointsBalance.toInt() : int.tryParse(pointsBalance.toString());
        if (b != null) {
          yield ChatStreamChunk(content: '', pointsBalance: b);
        }
      }

      final choices = json['Choices'];
      if (choices is! List || choices.isEmpty) return;

      final choice = choices.first;
      if (choice is! Map) return;

      final delta = choice['Delta'];
      if (delta is! Map) return;

      final reasoningContent = delta['ReasoningContent'];
      if (reasoningContent != null && reasoningContent.toString().isNotEmpty) {
        yield ChatStreamChunk(
          content: '',
          reasoningContent: reasoningContent.toString(),
          isReasoning: true,
          isComplete: false,
        );
      }

      final content = delta['Content'];
      if (content != null && content.toString().isNotEmpty) {
        yield ChatStreamChunk(
          content: content.toString(),
          isReasoning: false,
          isComplete: false,
        );
      }

      final finishReason = choice['FinishReason'];
      if (finishReason != null && finishReason.toString().isNotEmpty && finishReason.toString() != 'null') {
        yield ChatStreamChunk(content: '', isComplete: true);
      }
    } catch (_) {}
  }

  /// 积分初始化（返回余额）
  static Future<int> initPoints({String? authToken}) async {
    final url = Uri.parse('$proxyUrl/points/init');
    final resp = await http.post(
      url,
      headers: headers(authToken: authToken),
      body: jsonEncode({}),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return 0;
    final j = jsonDecode(resp.body);
    final b = j['balance'];
    return (b is num) ? b.toInt() : 0;
  }

  /// 获取积分余额
  static Future<int> getPointsBalance({String? authToken}) async {
    final url = Uri.parse('$proxyUrl/points/balance');
    final resp = await http.post(
      url,
      headers: headers(authToken: authToken),
      body: jsonEncode({}),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return 0;
    final j = jsonDecode(resp.body);
    final b = j['balance'];
    return (b is num) ? b.toInt() : 0;
  }

  /// 签到
  static Future<CheckinResult> checkin({String? authToken}) async {
    final url = Uri.parse('$proxyUrl/checkin');
    final resp = await http.post(
      url,
      headers: headers(authToken: authToken),
      body: jsonEncode({}),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      String msg = '签到失败';
      try {
        final j = jsonDecode(resp.body);
        msg = j['message'] ?? j['error'] ?? msg;
      } catch (_) {}
      if (resp.statusCode == 401) {
        throw ApiException('未授权：请先登录，或检查 API 配置');
      }
      throw ApiException(msg);
    }
    final j = jsonDecode(resp.body);
    return CheckinResult(
      points: (j['points'] as num?)?.toInt() ?? 0,
      alreadyDone: j['alreadyDone'] == true,
      balance: (j['balance'] as num?)?.toInt(),
    );
  }

  /// 签到状态
  static Future<bool> getCheckinStatus({String? authToken}) async {
    final url = Uri.parse('$proxyUrl/checkin/status');
    final resp = await http.post(
      url,
      headers: headers(authToken: authToken),
      body: jsonEncode({}),
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return false;
    final j = jsonDecode(resp.body);
    return j['checkedInToday'] == true;
  }

  /// 获取远程配置（签到积分、初始赠送等）
  static Future<Map<String, dynamic>> getConfig() async {
    final base = proxyUrl.trim().endsWith('/') ? proxyUrl : '$proxyUrl/';
    final url = Uri.parse('${base}config');
    final resp = await http.get(url, headers: headers()).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(resp.body));
    } catch (_) {
      return {};
    }
  }

  static bool get hasProxyUrl => proxyUrl.trim().isNotEmpty;
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class CheckinResult {
  final int points;
  final bool alreadyDone;
  final int? balance;
  CheckinResult({
    required this.points,
    required this.alreadyDone,
    this.balance,
  });
}
