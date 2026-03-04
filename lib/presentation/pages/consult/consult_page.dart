import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/bill.dart';
import '../../../data/models/consult_session.dart';
import '../../../services/api_service.dart';
import '../../../services/consult_service.dart';
import '../../../services/consult_session_storage.dart';
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
  List<ConsultMessage> _messages = [];
  String _streamingContent = '';
  String? _streamingReasoning;
  bool _loading = false;
  ConsultSession? _currentSession;
  List<ConsultSession> _sessions = [];
  bool _loadingSessions = true;
  @override
  void initState() {
    super.initState();
    ApiService.onPointsBalanceChanged = _onPointsBalanceChanged;
    _loadSessionsAndMessages();
  }

  void _onPointsBalanceChanged(int balance) {
    if (mounted) {
      context.read<PointsProvider>().setBalance(balance);
    }
  }

  @override
  void dispose() {
    ApiService.onPointsBalanceChanged = null;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionsAndMessages() async {
    await ConsultSessionStorage.load();
    if (!mounted) return;
    final cur = await ConsultSessionStorage.ensureCurrentSession();
    if (!mounted) return;
    setState(() {
      _sessions = ConsultSessionStorage.sessions;
      _currentSession = cur;
      _loadingSessions = false;
    });
    if (_currentSession != null) {
      setState(() => _messages = List.from(_currentSession!.messages));
    }
  }

  Future<void> _switchSession(ConsultSession session) async {
    final s = await ConsultSessionStorage.switchToSession(session.id);
    if (s != null && mounted) {
      setState(() {
        _currentSession = s;
        _messages = List.from(s.messages);
        _streamingContent = '';
        _streamingReasoning = null;
        _loading = false;
      });
    }
  }

  Future<void> _createNewSession() async {
    final s = await ConsultSessionStorage.createNewSession();
    if (mounted) {
      setState(() {
        _currentSession = s;
        _sessions = ConsultSessionStorage.sessions;
        _messages = [];
        _streamingContent = '';
        _streamingReasoning = null;
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading || _currentSession == null) return;
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
      _messages.add(ConsultMessage(role: 'user', content: text));
      _loading = true;
      _streamingContent = '';
      _streamingReasoning = null;
    });
    await ConsultSessionStorage.appendMessage(_currentSession!.id, 'user', text);
    _scrollToBottom();

    Map<String, double>? recentSpending;
    try {
      final bp = context.read<BillProvider>();
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 30));
      recentSpending = await bp.getCategoryTotalsInRange(start, now, type: BillType.expense);
      if (recentSpending.isEmpty) recentSpending = null;
    } catch (_) {}

    final history = _messages.map((m) => {'role': m.role, 'content': m.content}).toList();
    final pp = context.read<PointsProvider>();

    try {
      await for (final chunk in consultStream(
        conversationHistory: history,
        recentCategorySpending: recentSpending,
      )) {
        if (!mounted) return;
        if (chunk.pointsBalance != null) {
          pp.setBalance(chunk.pointsBalance!);
        }
        setState(() {
          if (chunk.reasoningContent != null && chunk.reasoningContent!.isNotEmpty) {
            _streamingReasoning = (_streamingReasoning ?? '') + chunk.reasoningContent!;
          }
          if (chunk.content.isNotEmpty) {
            _streamingContent += chunk.content;
          }
          if (chunk.isComplete) {
            _loading = false;
            if (_streamingContent.isNotEmpty) {
              _messages.add(ConsultMessage(role: 'assistant', content: _streamingContent));
              ConsultSessionStorage.appendMessage(_currentSession!.id, 'assistant', _streamingContent);
            }
            _streamingContent = '';
            _streamingReasoning = null;
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ConsultMessage(
            role: 'assistant',
            content: '出错了：${e.toString().replaceAll('Exception:', '').trim()}',
          ));
          _loading = false;
          _streamingContent = '';
          _streamingReasoning = null;
        });
        ConsultSessionStorage.appendMessage(
          _currentSession!.id,
          'assistant',
          '出错了：${e.toString().replaceAll('Exception:', '').trim()}',
        );
      }
    }
    if (mounted) pp.syncFromServer();
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

  void _showSessionList() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _SessionListSheet(
        sessions: _sessions,
        currentId: _currentSession?.id,
        onSelect: (s) {
          Navigator.pop(ctx);
          _switchSession(s);
        },
        onNew: () {
          Navigator.pop(ctx);
          _createNewSession();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentSession?.title ?? '不花行不行？'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _loadingSessions ? null : _showSessionList,
            tooltip: '会话列表',
          ),
          IconButton(
            icon: const Icon(Icons.add_comment),
            onPressed: _loading || _loadingSessions ? null : _createNewSession,
            tooltip: '新会话',
          ),
          Consumer<PointsProvider>(
            builder: (_, pp, child) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Center(
                child: Text('积分 ${pp.balance}', style: const TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
      body: _loadingSessions
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty && _streamingContent.isEmpty
                      ? _EmptyHint()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length + (_loading || _streamingContent.isNotEmpty ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _messages.length) {
                              return _StreamingBubble(
                                content: _streamingContent,
                                reasoning: _streamingReasoning,
                                loading: _loading && _streamingContent.isEmpty,
                              );
                            }
                            final m = _messages[i];
                            return _ChatBubble(isUser: m.role == 'user', content: m.content);
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
                          style: IconButton.styleFrom(backgroundColor: AppColors.primaryGreen),
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

class _SessionListSheet extends StatelessWidget {
  final List<ConsultSession> sessions;
  final String? currentId;
  final void Function(ConsultSession) onSelect;
  final VoidCallback onNew;

  const _SessionListSheet({
    required this.sessions,
    required this.currentId,
    required this.onSelect,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('会话列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                TextButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新会话'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: sc,
              itemCount: sessions.length,
              itemBuilder: (_, i) {
                final s = sessions[i];
                final isCurrent = s.id == currentId;
                return ListTile(
                  leading: Icon(
                    isCurrent ? Icons.chat_bubble : Icons.chat_bubble_outline,
                    color: isCurrent ? AppColors.primaryGreen : null,
                  ),
                  title: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${s.messages.length} 条消息',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  onTap: () => onSelect(s),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primaryGreen : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          content,
          style: TextStyle(fontSize: 15, color: isUser ? Colors.white : null, height: 1.5),
        ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  final String content;
  final String? reasoning;
  final bool loading;

  const _StreamingBubble({required this.content, this.reasoning, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reasoning != null && reasoning!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    reasoning!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.4),
                  ),
                ),
              ),
            content.isNotEmpty
                ? Text(content, style: const TextStyle(fontSize: 15, height: 1.5))
                : loading
                    ? Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text('思考中...', style: TextStyle(color: Colors.grey[600])),
                        ],
                      )
                    : const SizedBox.shrink(),
          ],
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
              '输入想买的东西，我会一个个问你，帮你冷静一下',
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
