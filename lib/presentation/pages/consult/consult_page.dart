import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/consult_service.dart';
import '../../providers/bill_provider.dart';
import '../../providers/points_provider.dart';
import '../../widgets/wallet_sheet.dart';

class ConsultPage extends StatefulWidget {
  const ConsultPage({super.key});

  @override
  State<ConsultPage> createState() => _ConsultPageState();
}

class _ConsultPageState extends State<ConsultPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    final points = context.read<PointsProvider>().balance;
    if (points <= 0) {
      WalletSheet.show(
        context,
        points,
        () => context.read<PointsProvider>().syncFromServer(),
      );
      return;
    }
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _loading = true;
    });
    _scrollToBottom();
    try {
      final history = _messages.map((m) => {
        'role': m.role,
        'content': m.content,
      }).toList();
      Map<String, double>? recentSpending;
      final bp = context.read<BillProvider>();
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 30));
      recentSpending = await bp.getCategoryTotalsInRange(start, now);
      if (recentSpending.isEmpty) recentSpending = null;
      final reply = await consult(
        conversationHistory: history,
        recentCategorySpending: recentSpending,
      );
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(role: 'assistant', content: reply));
          _loading = false;
        });
        _scrollToBottom();
        context.read<PointsProvider>().syncFromServer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(
            role: 'assistant',
            content: '出错了：${e.toString().replaceAll('Exception:', '')}',
          ));
          _loading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('不花行不行？'),
        actions: [
          Consumer<PointsProvider>(
            builder: (_, pp, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Center(
                child: Text(
                  '积分 ${pp.balance}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _EmptyHint()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('思考中...'),
                            ],
                          ),
                        );
                      }
                      final m = _messages[i];
                      return _ChatBubble(
                        isUser: m.role == 'user',
                        content: m.content,
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: '我想买……',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : _send,
                    icon: const Icon(Icons.send),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String role;
  final String content;
  _ChatMessage({required this.role, required this.content});
}

class _ChatBubble extends StatelessWidget {
  final bool isUser;
  final String content;

  const _ChatBubble({required this.isUser, required this.content});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.primaryGreen
              : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          content,
          style: TextStyle(
            fontSize: 15,
            color: isUser ? Colors.white : null,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '一定要花这个钱吗？不花行不行？',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '输入想买的东西，我来帮你冷静一下',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '例：我想买一个机械键盘',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}
