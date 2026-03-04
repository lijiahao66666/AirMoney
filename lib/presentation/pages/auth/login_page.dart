import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/auth_service.dart';
import '../../providers/points_provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _sending = false;
  bool _logging = false;
  int _countdown = 0;
  Timer? _timer;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  bool get _phoneValid =>
      _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '').length == 11;

  bool get _codeValid => _codeController.text.trim().length >= 4;

  Future<void> _sendCode() async {
    if (!_phoneValid || _sending || _countdown > 0) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final result = await AuthService.sendSmsCode(_phoneController.text.trim());
    if (!mounted) return;
    setState(() => _sending = false);
    if (result.success) {
      setState(() => _countdown = 60);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          _countdown--;
          if (_countdown <= 0) t.cancel();
        });
      });
    } else {
      setState(() => _error = result.error ?? '发送失败');
    }
  }

  Future<void> _login() async {
    if (!_phoneValid || !_codeValid || _logging) return;
    setState(() {
      _logging = true;
      _error = null;
    });
    final result = await AuthService.loginWithSmsCode(
      _phoneController.text.trim(),
      _codeController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _logging = false);
    if (result.success) {
      context.read<PointsProvider>().setBalance(result.balance ?? 0);
      context.read<PointsProvider>().syncFromServer();
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() => _error = result.error ?? '登录失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            const Text(
              '手机号验证码登录',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '登录可获赠积分，积分跨设备同步',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '手机号',
                hintText: '请输入11位手机号',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      hintText: '请输入验证码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: FilledButton(
                    onPressed: (_phoneValid && !_sending && _countdown == 0)
                        ? _sendCode
                        : null,
                    child: Text(_countdown > 0 ? '${_countdown}s' : '获取验证码'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: (_phoneValid && _codeValid && !_logging) ? _login : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _logging
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}
