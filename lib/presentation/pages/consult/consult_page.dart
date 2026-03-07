import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/bill.dart';
import '../../../data/models/consult_session.dart'
    show ConsultMessage, ConsultSession, AgentStep;
import '../../../services/api_service.dart';
import '../../../services/consult_service.dart';
import '../../../services/consult_session_storage.dart';
import '../../providers/bill_provider.dart';
import '../../providers/points_provider.dart';
import '../../widgets/wallet_sheet.dart';

const List<String> _assistantMetaMarkers = <String>[
  '追问',
  '细节',
  '幽默',
  '理解',
  '认同',
  '共情',
  '过渡',
  '回应',
  '反应',
  '标签',
  '动作',
  '策略',
  '意图',
  '分析',
  '总结',
  '建议',
  '提问',
];

String _stripAssistantMetaTags(String text) {
  if (text.isEmpty) return text;
  final pattern = RegExp(r'[（(]\s*([^（）()]{1,24})\s*[)）]');
  final cleaned = text.replaceAllMapped(pattern, (m) {
    final inside = (m.group(1) ?? '').replaceAll(RegExp(r'\s+'), '');
    final isMetaTag = _assistantMetaMarkers.any(inside.contains);
    return isMetaTag ? '' : (m.group(0) ?? '');
  });
  return cleaned
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trimRight();
}

class _IntentAnalysisDecision {
  final bool shouldAnalyze;
  final String? category;

  const _IntentAnalysisDecision({required this.shouldAnalyze, this.category});
}

class ConsultPage extends StatefulWidget {
  const ConsultPage({super.key});

  @override
  State<ConsultPage> createState() => _ConsultPageState();
}

class _ConsultPageState extends State<ConsultPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<ConsultMessage> _messages = [];
  String _streamingRawContent = '';
  String _streamingContent = '';
  String? _streamingReasoning;
  List<AgentStep> _agentSteps = [];
  bool _loading = false;
  ConsultSession? _currentSession;
  List<ConsultSession> _sessions = [];
  bool _loadingSessions = true;
  String? _lastIntentCategory;
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
      setState(() {
        _messages = List.from(_currentSession!.messages);
        _lastIntentCategory = _extractLastIntentCategory(_messages);
      });
    }
  }

  Future<void> _switchSession(ConsultSession session) async {
    final s = await ConsultSessionStorage.switchToSession(session.id);
    if (s != null && mounted) {
      setState(() {
        _currentSession = s;
        _messages = List.from(s.messages);
        _lastIntentCategory = _extractLastIntentCategory(_messages);
        _streamingRawContent = '';
        _streamingContent = '';
        _streamingReasoning = null;
        _agentSteps = [];
        _loading = false;
      });
    }
  }

  Future<void> _createNewSession() async {
    // 当前对话为空时不开新会话，避免历史里一堆空对话
    if (_messages.isEmpty && _streamingContent.isEmpty) return;
    final s = await ConsultSessionStorage.createNewSession();
    if (mounted) {
      setState(() {
        _currentSession = s;
        _sessions = ConsultSessionStorage.sessions;
        _messages = [];
        _lastIntentCategory = null;
        _streamingRawContent = '';
        _streamingContent = '';
        _streamingReasoning = null;
        _agentSteps = [];
        _loading = false;
      });
    }
  }

  String? _normalizeIntentCategory(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;
    text = text
        .split('（')
        .first
        .split('(')
        .first
        .split('→')
        .last
        .replaceAll(RegExp(r'[，。,.、\s]'), '');
    if (AppConstants.expenseCategories.contains(text)) return text;
    return null;
  }

  String? _extractLastIntentCategory(List<ConsultMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      final steps = m.agentSteps;
      if (m.role != 'assistant' || steps == null || steps.isEmpty) continue;
      for (var j = steps.length - 1; j >= 0; j--) {
        final step = steps[j];
        if (!step.label.contains('分析购买意图')) continue;
        final cat = _normalizeIntentCategory(step.result);
        if (cat != null) return cat;
      }
    }
    return null;
  }

  bool _hasTopicSwitchCue(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return false;
    const cues = [
      '换一个',
      '换个',
      '换成',
      '改买',
      '改成',
      '不买了',
      '不考虑了',
      '先不买',
      '另外',
      '另一个',
      '另个',
      '现在想买',
      '改为',
      '还是买',
      '转而',
    ];
    return cues.any(t.contains);
  }

  Future<_IntentAnalysisDecision> _decideIntentAnalysis(String userText) async {
    final hasAssistant = _messages.any((m) => m.role == 'assistant');
    final cat = await classifyPurchaseIntentByAi(userText);
    if (!hasAssistant) {
      return _IntentAnalysisDecision(shouldAnalyze: true, category: cat);
    }
    final prevCat = _lastIntentCategory;
    final cue = _hasTopicSwitchCue(userText);
    final changedCategory = cat != null && prevCat != null && cat != prevCat;
    final should = cue || changedCategory;
    return _IntentAnalysisDecision(shouldAnalyze: should, category: cat);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading || _currentSession == null) return;
    final pp = context.read<PointsProvider>();
    final points = pp.balance;
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
      _streamingRawContent = '';
      _streamingContent = '';
      _streamingReasoning = null;
      _agentSteps = [];
    });
    await ConsultSessionStorage.appendMessage(
      _currentSession!.id,
      'user',
      text,
    );
    _scrollToBottom();

    final analysisDecision = await _decideIntentAnalysis(text);
    if (!mounted) return;
    final shouldRunIntentAnalysis = analysisDecision.shouldAnalyze;
    final bp = context.read<BillProvider>();
    Map<String, double>? recentSpending;
    if (shouldRunIntentAnalysis) {
      try {
        final now = DateTime.now();
        final start = now.subtract(const Duration(days: 30));
        recentSpending = await bp.getCategoryTotalsInRange(
          start,
          now,
          type: BillType.expense,
        );
        if (recentSpending.isEmpty) recentSpending = null;
      } catch (_) {}
    }

    final history = _messages
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    try {
      await for (final chunk in consultStream(
        conversationHistory: history,
        recentCategorySpending: recentSpending,
        enableAgentSteps: shouldRunIntentAnalysis,
        intentAnalysisTargetText: text,
        preclassifiedIntentCategory: analysisDecision.category,
      )) {
        if (!mounted) return;
        if (chunk.pointsBalance != null) {
          pp.setBalance(chunk.pointsBalance!);
        }
        setState(() {
          if (chunk.agentSteps != null && chunk.agentSteps!.isNotEmpty) {
            _agentSteps = List<AgentStep>.from(chunk.agentSteps!);
          }
          if (chunk.reasoningContent != null &&
              chunk.reasoningContent!.isNotEmpty) {
            _streamingReasoning =
                (_streamingReasoning ?? '') + chunk.reasoningContent!;
          }
          if (chunk.content.isNotEmpty) {
            _streamingRawContent += chunk.content;
            _streamingContent = _stripAssistantMetaTags(_streamingRawContent);
          }
          if (chunk.isComplete) {
            _loading = false;
            if (_streamingContent.isNotEmpty) {
              final List<AgentStep>? finalizedSteps = _agentSteps.isNotEmpty
                  ? List<AgentStep>.from(_agentSteps)
                  : null;
              _messages.add(
                ConsultMessage(
                  role: 'assistant',
                  content: _streamingContent,
                  reasoning: _streamingReasoning,
                  agentSteps: finalizedSteps,
                ),
              );
              _lastIntentCategory = _extractLastIntentCategory(_messages);
              ConsultSessionStorage.appendMessage(
                _currentSession!.id,
                'assistant',
                _streamingContent,
                reasoning: _streamingReasoning,
                agentSteps: finalizedSteps,
              );
            }
            _streamingRawContent = '';
            _streamingContent = '';
            _streamingReasoning = null;
            _agentSteps = [];
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            ConsultMessage(
              role: 'assistant',
              content:
                  '出错了：${e.toString().replaceAll('Exception:', '').trim()}',
            ),
          );
          _loading = false;
          _streamingRawContent = '';
          _streamingContent = '';
          _streamingReasoning = null;
          _agentSteps = [];
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
        title: const Text('不花行不行？'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: _loading || _loadingSessions ? null : _createNewSession,
            tooltip: '开启新对话',
            style: IconButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _loadingSessions ? null : _showSessionList,
            tooltip: '历史对话',
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
                          itemCount:
                              _messages.length +
                              (_loading ||
                                      _streamingContent.isNotEmpty ||
                                      _agentSteps.isNotEmpty
                                  ? 1
                                  : 0),
                          itemBuilder: (_, i) {
                            if (i == _messages.length) {
                              return _StreamingBubble(
                                content: _streamingContent,
                                reasoning: _streamingReasoning,
                                agentSteps: _agentSteps,
                                loading: _loading && _streamingContent.isEmpty,
                              );
                            }
                            final m = _messages[i];
                            return _ChatBubble(
                              isUser: m.role == 'user',
                              content: m.content,
                              reasoning: m.reasoning,
                              agentSteps: m.agentSteps,
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
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            minLines: 1,
                            maxLines: 6,
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
                const Text(
                  '会话列表',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
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
  final String? reasoning;
  final List<AgentStep>? agentSteps;

  const _ChatBubble({
    required this.isUser,
    required this.content,
    this.reasoning,
    this.agentSteps,
  });

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
          color: isUser ? AppColors.primaryGreen : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isUser
            ? Text(
                content,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.white,
                  height: 1.5,
                ),
              )
            : _AssistantBubbleContent(
                content: content,
                reasoning: reasoning,
                agentSteps: agentSteps,
              ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  final String content;
  final String? reasoning;
  final List<AgentStep> agentSteps;
  final bool loading;

  const _StreamingBubble({
    required this.content,
    this.reasoning,
    this.agentSteps = const [],
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: _AssistantBubbleContent(
          content: content,
          reasoning: reasoning,
          agentSteps: agentSteps.isNotEmpty ? agentSteps : null,
          loading: loading,
        ),
      ),
    );
  }
}

/// 豆包式：智能体步骤 + 思考内容 + 回复
class _AssistantBubbleContent extends StatefulWidget {
  final String content;
  final String? reasoning;
  final List<AgentStep>? agentSteps;
  final bool loading;

  const _AssistantBubbleContent({
    required this.content,
    this.reasoning,
    this.agentSteps,
    this.loading = false,
  });

  @override
  State<_AssistantBubbleContent> createState() =>
      _AssistantBubbleContentState();
}

class _AssistantBubbleContentState extends State<_AssistantBubbleContent> {
  static const double _thinkingMaxHeight = 96;
  final _thinkingScrollController = ScrollController();
  bool _reasoningExpanded = false;
  bool _lastLoading = false;

  @override
  void dispose() {
    _thinkingScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _lastLoading = widget.loading;
  }

  @override
  void didUpdateWidget(covariant _AssistantBubbleContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reasoning != null && widget.reasoning!.isNotEmpty) {
      if (widget.loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_thinkingScrollController.hasClients) {
            _thinkingScrollController.jumpTo(
              _thinkingScrollController.position.maxScrollExtent,
            );
          }
        });
      } else if (_lastLoading && !widget.loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_thinkingScrollController.hasClients) {
            _thinkingScrollController.jumpTo(0);
          }
        });
      }
    }
    _lastLoading = widget.loading;
  }

  @override
  Widget build(BuildContext context) {
    final hasReasoning =
        widget.reasoning != null && widget.reasoning!.trim().isNotEmpty;
    final displayContent = _stripAssistantMetaTags(widget.content);
    final isThinkingActive = widget.loading && hasReasoning;
    final thinkingTitle = hasReasoning
        ? (widget.loading ? '思考中' : '已完成思考')
        : null;

    if (isThinkingActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_thinkingScrollController.hasClients) {
          _thinkingScrollController.jumpTo(
            _thinkingScrollController.position.maxScrollExtent,
          );
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.agentSteps != null && widget.agentSteps!.isNotEmpty) ...[
          ...widget.agentSteps!.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    s.result != null
                        ? Icons.check_circle
                        : Icons.hourglass_empty,
                    size: 14,
                    color: s.result != null
                        ? AppColors.primaryGreen
                        : Colors.grey[500],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.result != null
                        ? '${s.label} → ${s.result}'
                        : '${s.label}...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ),
          if (hasReasoning || displayContent.isNotEmpty || widget.loading) ...[
            const SizedBox(height: 8),
            CustomPaint(
              size: const Size(double.infinity, 8),
              painter: _CurvedDividerPainter(),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (hasReasoning) ...[
          if (thinkingTitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                thinkingTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: _reasoningExpanded
                  ? double.infinity
                  : _thinkingMaxHeight,
            ),
            child: SingleChildScrollView(
              controller: _thinkingScrollController,
              physics: isThinkingActive || _reasoningExpanded
                  ? const AlwaysScrollableScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: Text(
                widget.reasoning!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () =>
                setState(() => _reasoningExpanded = !_reasoningExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _reasoningExpanded ? '收起' : '展开全部',
                style: TextStyle(fontSize: 12, color: AppColors.primaryGreen),
              ),
            ),
          ),
          if (displayContent.isNotEmpty || widget.loading) ...[
            const SizedBox(height: 10),
            CustomPaint(
              size: const Size(double.infinity, 12),
              painter: _CurvedDividerPainter(),
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (displayContent.isNotEmpty)
          Text(
            displayContent,
            style: const TextStyle(fontSize: 15, height: 1.5),
          )
        else if (widget.loading)
          Row(
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
        else if (!hasReasoning)
          const SizedBox.shrink(),
      ],
    );
  }
}

class _CurvedDividerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final path = Path();
    final midY = size.height * 0.5;
    path.moveTo(0, midY);
    var i = 0.0;
    while (i < size.width) {
      final seg = (i / 12).floor();
      final x2 = (i + 12).clamp(0.0, size.width);
      path.quadraticBezierTo(
        i + 6,
        midY + (seg % 2 == 0 ? 3.0 : -3.0),
        x2,
        midY,
      );
      i += 12;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
            Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
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
