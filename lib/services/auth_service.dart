import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  static const _kToken = 'auth_token';
  static const _kUserId = 'auth_user_id';
  static const _kPhone = 'auth_phone';
  static const _kLoggedIn = 'auth_logged_in';

  static String _token = '';
  static String _userId = '';
  static String _phone = '';
  static bool _loggedIn = false;

  static bool get isLoggedIn => _loggedIn;
  static String get token => _token;
  static String get userId => _userId;
  static String get phone => _phone;

  static VoidCallback? onAuthStateChanged;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = (prefs.getString(_kToken) ?? '').trim();
    _userId = (prefs.getString(_kUserId) ?? '').trim();
    _phone = (prefs.getString(_kPhone) ?? '').trim();
    _loggedIn = prefs.getBool(_kLoggedIn) ?? false;
    debugPrint('[Auth] init: loggedIn=$_loggedIn');
  }

  static Future<AuthResult> sendSmsCode(String phone) async {
    final baseUrl = ApiService.proxyUrl.trim();
    if (baseUrl.isEmpty) return AuthResult(success: false, error: '服务未配置');
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/auth/sms/send'),
        headers: ApiService.headers(),
        body: jsonEncode({'phone': phone}),
      ).timeout(const Duration(seconds: 15));
      final json = jsonDecode(resp.body);
      if (resp.statusCode == 200 && json['success'] == true) {
        return AuthResult(success: true);
      }
      return AuthResult(
        success: false,
        error: json['message'] ?? json['error'] ?? '发送失败',
      );
    } catch (e) {
      debugPrint('[Auth] sendSmsCode: $e');
      return AuthResult(success: false, error: '网络错误');
    }
  }

  static Future<AuthResult> loginWithSmsCode(String phone, String code) async {
    final baseUrl = ApiService.proxyUrl.trim();
    if (baseUrl.isEmpty) return AuthResult(success: false, error: '服务未配置');
    try {
      final headers = Map<String, String>.from(ApiService.headers());
      headers['X-Device-Id'] = ApiService.deviceId;
      final resp = await http.post(
        Uri.parse('$baseUrl/auth/sms/verify'),
        headers: headers,
        body: jsonEncode({'phone': phone, 'code': code}),
      ).timeout(const Duration(seconds: 15));
      final json = jsonDecode(resp.body);
      if (resp.statusCode == 200 && json['token'] != null) {
        _token = json['token'];
        _userId = json['userId'] ?? '';
        _phone = json['phone'] ?? phone;
        _loggedIn = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kToken, _token);
        await prefs.setString(_kUserId, _userId);
        await prefs.setString(_kPhone, _phone);
        await prefs.setBool(_kLoggedIn, true);
        onAuthStateChanged?.call();
        return AuthResult(
          success: true,
          balance: (json['balance'] as num?)?.toInt(),
          initialGrantedThisTime: json['initialGrantedThisTime'] == true,
          initialGrantPoints: (json['initialGrantPoints'] as num?)?.toInt(),
        );
      }
      return AuthResult(
        success: false,
        error: json['message'] ?? json['error'] ?? '登录失败',
      );
    } catch (e) {
      debugPrint('[Auth] login: $e');
      return AuthResult(success: false, error: '网络错误');
    }
  }

  static Future<void> logout() async {
    final baseUrl = ApiService.proxyUrl.trim();
    if (baseUrl.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: ApiService.headers(authToken: _token),
          body: jsonEncode({}),
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _token = '';
    _userId = '';
    _phone = '';
    _loggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kPhone);
    await prefs.setBool(_kLoggedIn, false);
    onAuthStateChanged?.call();
  }
}

class AuthResult {
  final bool success;
  final String? error;
  final int? balance;
  AuthResult({required this.success, this.error, this.balance});
}
