import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/bill.dart';
import '../../../data/models/consult_session.dart'
    show AgentStep, ConsultMessage, ConsultSession;
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
  'intent',
  'meta',
];

String _stripAssistantMetaTags(String text) {
  if (text.isEmpty) return text;
  final pattern = RegExp(
    r'[\(（]\s*([^\(\)（）]{1,24})\s*[\)）]',
  );
  final cleaned = text.replaceAllMapped(pattern, (m) {
    final inside = (m.group(1) ?? '').replaceAll(RegExp(r'\s+'), '');
    final isMeta = _assistantMetaMarkers.any(
      (k) => inside.toLowerCase().contains(k),
    );
    return isMeta ? '' : (m.group(0) ?? '');
  });
  return cleaned
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trimRight();
}

class _IntentAnalysisDecision {
  const _IntentAnalysisDecision({required this.shouldAnalyze, this.category});
  final bool shouldAnalyze;
  final String? category;
}

class _ActiveConsultStreamState {
  _ActiveConsultStreamState({required this.sessionId});
  final String sessionId;
  final Completer<void> stopSignal = Completer<void>();
  Future<void>? runner;
  bool isRunning = true;
  bool stopRequested = false;
  String rawContent = '';
  String content = '';
  String? reasoning;
  List<AgentStep> agentSteps = <AgentStep>[];
  int? pointsBalance;
  String? errorMessage;
  int revision = 0;
  void markChanged() => revision += 1;
  void requestStop() {
    stopRequested = true;
    if (!stopSignal.isCompleted) stopSignal.complete();
    markChanged();
  }
}

final Map<String, _ActiveConsultStreamState> _activeConsultStreams =
    <String, _ActiveConsultStreamState>{};

class ConsultPage extends StatefulWidget {
  const ConsultPage({super.key});
  @override
  State<ConsultPage> createState() => _ConsultPageState();
}

class _ConsultPageState extends State<ConsultPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ConsultMessage> _messages = <ConsultMessage>[];
  String _streamingRawContent = '';
  String _streamingContent = '';
  String? _streamingReasoning;
  List<AgentStep> _agentSteps = <AgentStep>[];
  bool _loading = false;
  ConsultSession? _currentSession;
  List<ConsultSession> _sessions = <ConsultSession>[];
  bool _loadingSessions = true;
  String? _lastIntentCategory;
  Timer? _streamSyncTimer;
  int _lastObservedStreamRevision = -1;
  String? _observedStreamSessionId;
  bool _syncingCompletedStream = false;

  @override
  void initState() {
    super.initState();
    ApiService.onPointsBalanceChanged = _onPointsBalanceChanged;
    _loadSessionsAndMessages();
    _streamSyncTimer = Timer.periodic(
      const Duration(milliseconds: 160),
      (_) => _syncStreamingState(),
    );
  }

  @override
  void dispose() {
    ApiService.onPointsBalanceChanged = null;
    _streamSyncTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onPointsBalanceChanged(int balance) {
    if (!mounted) return;
    context.read<PointsProvider>().setBalance(balance);
  }

  Future<void> _loadSessionsAndMessages() async {
    await ConsultSessionStorage.load();
    if (!mounted) return;
    final cur = await ConsultSessionStorage.ensureCurrentSession();
    if (!mounted) return;
    setState(() {
      _sessions = ConsultSessionStorage.sessions;
      _currentSession = cur;
      _messages = List<ConsultMessage>.from(cur.messages);
      _lastIntentCategory = _extractLastIntentCategory(_messages);
      _loadingSessions = false;
    });
    await _syncStreamingState(force: true);
    _scrollToBottom();
  }

  Future<void> _switchSession(ConsultSession session) async {
    final s = await ConsultSessionStorage.switchToSession(session.id);
    if (!mounted || s == null) return;
    setState(() {
      _currentSession = s;
      _messages = List<ConsultMessage>.from(s.messages);
      _lastIntentCategory = _extractLastIntentCategory(_messages);
      _loading = false;
      _streamingRawContent = '';
      _streamingContent = '';
      _streamingReasoning = null;
      _agentSteps = <AgentStep>[];
      _observedStreamSessionId = null;
      _lastObservedStreamRevision = -1;
    });
    await _syncStreamingState(force: true);
    _scrollToBottom();
  }

  Future<void> _createNewSession() async {
    if (_messages.isEmpty && _streamingContent.isEmpty) return;
    final s = await ConsultSessionStorage.createNewSession();
    if (!mounted) return;
    setState(() {
      _currentSession = s;
      _sessions = ConsultSessionStorage.sessions;
      _messages = <ConsultMessage>[];
      _lastIntentCategory = null;
      _loading = false;
      _streamingRawContent = '';
      _streamingContent = '';
      _streamingReasoning = null;
      _agentSteps = <AgentStep>[];
      _observedStreamSessionId = null;
      _lastObservedStreamRevision = -1;
    });
    await _syncStreamingState(force: true);
  }

  String? _normalizeIntentCategory(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;
    text = text
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('→', '->')
        .split('(')
        .first
        .split('->')
        .last
        .replaceAll(RegExp(r'[\s,.:;!?]'), '');
    for (final c in AppConstants.expenseCategories) {
      if (text == c || text.contains(c)) return c;
    }
    return null;
  }

  String? _extractLastIntentCategory(List<ConsultMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final steps = messages[i].agentSteps;
      if (messages[i].role != 'assistant' || steps == null || steps.isEmpty) {
        continue;
      }
      for (var j = steps.length - 1; j >= 0; j--) {
        final cat = _normalizeIntentCategory(steps[j].result);
        if (cat != null) return cat;
      }
    }
    return null;
  }

  bool _hasTopicSwitchCue(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return false;
    const cues = <String>[
      '换一个',
      '换个',
      '改买',
      '改成',
      '不买了',
      '先不买',
      '另外',
      '另一个',
      '现在想买',
      '还是买',
      'switch',
      'change',
      'different',
      'instead',
      'another',
    ];
    return cues.any(t.contains);
  }

  Future<_IntentAnalysisDecision> _decideIntentAnalysis(String userText) async {
    final hasAssistant = _messages.any((m) => m.role == 'assistant');
    final category = await classifyPurchaseIntentByAi(userText);
    if (!hasAssistant) {
      return _IntentAnalysisDecision(shouldAnalyze: true, category: category);
    }
    final prevCat = _lastIntentCategory;
    final shouldAnalyze =
        _hasTopicSwitchCue(userText) ||
        (category != null && prevCat != null && category != prevCat);
    return _IntentAnalysisDecision(
      shouldAnalyze: shouldAnalyze,
      category: category,
    );
  }

  Map<String, double> _sanitizeCategoryTotals(Map<String, double> totals) {
    final cleaned = <String, double>{};
    for (final e in totals.entries) {
      final key = e.key.trim();
      if (key.isEmpty || e.value <= 0) continue;
      cleaned[key] = (cleaned[key] ?? 0) + e.value;
    }
    return cleaned;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading || _currentSession == null) return;

    final pointsProvider = context.read<PointsProvider>();
    if (pointsProvider.balance <= 0) {
      WalletSheet.show(
        context,
        pointsProvider.balance,
        () => context.read<PointsProvider>().syncFromServer(),
      );
      return;
    }

    final sessionId = _currentSession!.id;
    _controller.clear();
    setState(() {
      _messages.add(ConsultMessage(role: 'user', content: text));
      _loading = true;
      _streamingRawContent = '';
      _streamingContent = '';
      _streamingReasoning = null;
      _agentSteps = <AgentStep>[];
    });
    await ConsultSessionStorage.appendMessage(sessionId, 'user', text);
    if (mounted) {
      setState(() => _sessions = ConsultSessionStorage.sessions);
    }
    _scrollToBottom();

    final analysisDecision = await _decideIntentAnalysis(text);
    if (!mounted) return;

    Map<String, double>? recentSpending;
    if (analysisDecision.shouldAnalyze) {
      try {
        final now = DateTime.now();
        final end = DateTime(now.year, now.month, now.day);
        final start = end.subtract(const Duration(days: 29));
        final totals = await context
            .read<BillProvider>()
            .getCategoryTotalsInRange(start, end, type: BillType.expense);
        final cleaned = _sanitizeCategoryTotals(totals);
        if (cleaned.isNotEmpty) recentSpending = cleaned;
      } catch (_) {}
    }

    final history = _messages
        .map((m) => <String, String>{'role': m.role, 'content': m.content})
        .toList();

    final state = _ActiveConsultStreamState(sessionId: sessionId);
    _activeConsultStreams[sessionId] = state;
    _observedStreamSessionId = null;
    _lastObservedStreamRevision = -1;

    state.runner = _runSessionStream(
      state,
      conversationHistory: history,
      recentCategorySpending: recentSpending,
      enableAgentSteps: analysisDecision.shouldAnalyze,
      intentAnalysisTargetText: text,
      preclassifiedIntentCategory: analysisDecision.category,
    );
    unawaited(state.runner);
    await _syncStreamingState(force: true);
  }

  static Future<void> _runSessionStream(
    _ActiveConsultStreamState state, {
    required List<Map<String, String>> conversationHistory,
    required Map<String, double>? recentCategorySpending,
    required bool enableAgentSteps,
    required String intentAnalysisTargetText,
    required String? preclassifiedIntentCategory,
  }) async {
    final done = Completer<void>();
    late final StreamSubscription<ConsultStreamChunk> sub;

    void finishOnce() {
      if (!done.isCompleted) done.complete();
    }

    sub =
        consultStream(
          conversationHistory: conversationHistory,
          recentCategorySpending: recentCategorySpending,
          enableAgentSteps: enableAgentSteps,
          intentAnalysisTargetText: intentAnalysisTargetText,
          preclassifiedIntentCategory: preclassifiedIntentCategory,
        ).listen(
          (chunk) {
            if (state.stopRequested) return;
            if (chunk.pointsBalance != null) {
              state.pointsBalance = chunk.pointsBalance;
            }
            if (chunk.agentSteps != null && chunk.agentSteps!.isNotEmpty) {
              state.agentSteps = List<AgentStep>.from(chunk.agentSteps!);
            }
            if (chunk.reasoningContent != null &&
                chunk.reasoningContent!.isNotEmpty) {
              state.reasoning =
                  (state.reasoning ?? '') + chunk.reasoningContent!;
            }
            if (chunk.content.isNotEmpty) {
              state.rawContent += chunk.content;
              state.content = _stripAssistantMetaTags(state.rawContent);
            }
            state.markChanged();
            if (chunk.isComplete) finishOnce();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!state.stopRequested) {
              state.errorMessage =
                  '出错了：${error.toString().replaceAll('Exception:', '').trim()}';
              state.markChanged();
            }
            finishOnce();
          },
          onDone: finishOnce,
          cancelOnError: false,
        );

    state.stopSignal.future.then((_) async {
      try {
        await sub.cancel();
      } catch (_) {}
      finishOnce();
    });

    try {
      await done.future;
      try {
        await sub.cancel();
      } catch (_) {}

      final finalizedSteps = state.agentSteps.isEmpty
          ? null
          : List<AgentStep>.from(state.agentSteps);
      if (!state.stopRequested && state.errorMessage != null) {
        await ConsultSessionStorage.appendMessage(
          state.sessionId,
          'assistant',
          state.errorMessage!,
          reasoning: state.reasoning,
          agentSteps: finalizedSteps,
        );
      } else if (state.content.trim().isNotEmpty) {
        await ConsultSessionStorage.appendMessage(
          state.sessionId,
          'assistant',
          state.content.trim(),
          reasoning: state.reasoning,
          agentSteps: finalizedSteps,
        );
      }
    } finally {
      state.isRunning = false;
      state.markChanged();
    }
  }

  Future<void> _stopCurrentStreaming() async {
    final sessionId = _currentSession?.id;
    if (sessionId == null) return;
    final active = _activeConsultStreams[sessionId];
    if (active == null) {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
      return;
    }
    active.requestStop();
    await active.runner;
    await _syncStreamingState(force: true);
  }

  Future<void> _reloadSessionFromStorage(String sessionId) async {
    await ConsultSessionStorage.load();
    if (!mounted) return;
    if (_currentSession?.id != sessionId) return;

    final sessions = ConsultSessionStorage.sessions;
    ConsultSession? current;
    for (final s in sessions) {
      if (s.id == sessionId) {
        current = s;
        break;
      }
    }
    final resolvedCurrent =
        current ?? await ConsultSessionStorage.ensureCurrentSession();
    if (!mounted) return;
    if (_currentSession?.id != sessionId && resolvedCurrent.id != sessionId) {
      return;
    }

    setState(() {
      _sessions = ConsultSessionStorage.sessions;
      _currentSession = resolvedCurrent;
      _messages = List<ConsultMessage>.from(resolvedCurrent.messages);
      _lastIntentCategory = _extractLastIntentCategory(_messages);
      _loading = false;
      _streamingRawContent = '';
      _streamingContent = '';
      _streamingReasoning = null;
      _agentSteps = <AgentStep>[];
    });
    _scrollToBottom();
  }

  Future<void> _syncStreamingState({bool force = false}) async {
    if (!mounted) return;
    final sessionId = _currentSession?.id;
    if (sessionId == null) return;

    final active = _activeConsultStreams[sessionId];
    if (active == null) {
      if (force &&
          (_loading ||
              _streamingContent.isNotEmpty ||
              _streamingRawContent.isNotEmpty ||
              _agentSteps.isNotEmpty ||
              (_streamingReasoning?.isNotEmpty ?? false))) {
        setState(() {
          _loading = false;
          _streamingRawContent = '';
          _streamingContent = '';
          _streamingReasoning = null;
          _agentSteps = <AgentStep>[];
        });
      }
      return;
    }

    final changed =
        force ||
        _observedStreamSessionId != sessionId ||
        _lastObservedStreamRevision != active.revision;
    if (changed && mounted) {
      setState(() {
        _observedStreamSessionId = sessionId;
        _lastObservedStreamRevision = active.revision;
        _loading = active.isRunning;
        _streamingRawContent = active.rawContent;
        _streamingContent = active.content;
        _streamingReasoning = active.reasoning;
        _agentSteps = List<AgentStep>.from(active.agentSteps);
      });
      if (active.pointsBalance != null) {
        context.read<PointsProvider>().setBalance(active.pointsBalance!);
      }
      _scrollToBottom();
    }

    if (!active.isRunning && !_syncingCompletedStream) {
      _syncingCompletedStream = true;
      _activeConsultStreams.remove(sessionId);
      try {
        await _reloadSessionFromStorage(sessionId);
        if (mounted) context.read<PointsProvider>().syncFromServer();
      } finally {
        _syncingCompletedStream = false;
        _observedStreamSessionId = null;
        _lastObservedStreamRevision = -1;
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSessionList() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) => _SessionListSheet(
        sessions: _sessions,
        currentId: _currentSession?.id,
        onSelect: (ConsultSession session) {
          Navigator.pop(ctx);
          _switchSession(session);
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
    final showStreamingItem =
        _loading ||
        _streamingContent.isNotEmpty ||
        _streamingRawContent.isNotEmpty ||
        _agentSteps.isNotEmpty ||
        (_streamingReasoning?.isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('该不该花？'),
        actions: <Widget>[
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
              children: <Widget>[
                Expanded(
                  child: _messages.isEmpty && !showStreamingItem
                      ? const _EmptyHint()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount:
                              _messages.length + (showStreamingItem ? 1 : 0),
                          itemBuilder: (BuildContext context, int index) {
                            if (index == _messages.length) {
                              return _MessageBubble(
                                isUser: false,
                                content: _streamingContent,
                                reasoning: _streamingReasoning,
                                steps: _agentSteps,
                                loading: _loading && _streamingContent.isEmpty,
                              );
                            }
                            final msg = _messages[index];
                            return _MessageBubble(
                              isUser: msg.role == 'user',
                              content: msg.content,
                              reasoning: msg.reasoning,
                              steps: msg.agentSteps ?? const <AgentStep>[],
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            minLines: 1,
                            maxLines: 6,
                            decoration: InputDecoration(
                              hintText: '我想…',
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
                          onPressed: _loading ? _stopCurrentStreaming : _send,
                          icon: Icon(_loading ? Icons.stop : Icons.send),
                          style: IconButton.styleFrom(
                            backgroundColor: _loading
                                ? Colors.redAccent
                                : AppColors.primaryGreen,
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
  const _SessionListSheet({
    required this.sessions,
    required this.currentId,
    required this.onSelect,
    required this.onNew,
  });

  final List<ConsultSession> sessions;
  final String? currentId;
  final void Function(ConsultSession) onSelect;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) =>
          Column(
            children: <Widget>[
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
                  children: <Widget>[
                    const Text(
                      '会话列表',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onNew,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新对话'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: sessions.length,
                  itemBuilder: (BuildContext context, int index) {
                    final session = sessions[index];
                    final isCurrent = session.id == currentId;
                    return ListTile(
                      leading: Icon(
                        isCurrent
                            ? Icons.chat_bubble
                            : Icons.chat_bubble_outline,
                        color: isCurrent ? AppColors.primaryGreen : null,
                      ),
                      title: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${session.messages.length} 条消息',
                      ),
                      onTap: () => onSelect(session),
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.isUser,
    required this.content,
    this.reasoning,
    this.steps = const <AgentStep>[],
    this.loading = false,
  });

  final bool isUser;
  final String content;
  final String? reasoning;
  final List<AgentStep> steps;
  final bool loading;

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
                agentSteps: steps,
                loading: loading,
              ),
      ),
    );
  }
}

class _AssistantBubbleContent extends StatefulWidget {
  const _AssistantBubbleContent({
    required this.content,
    this.reasoning,
    this.agentSteps = const <AgentStep>[],
    this.loading = false,
  });

  final String content;
  final String? reasoning;
  final List<AgentStep> agentSteps;
  final bool loading;

  @override
  State<_AssistantBubbleContent> createState() =>
      _AssistantBubbleContentState();
}

class _AssistantBubbleContentState extends State<_AssistantBubbleContent> {
  static const double _thinkingMaxHeight = 96;
  final ScrollController _thinkingScrollController = ScrollController();
  bool _reasoningExpanded = false;
  bool _lastLoading = false;

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
  void dispose() {
    _thinkingScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasReasoning =
        widget.reasoning != null && widget.reasoning!.trim().isNotEmpty;
    final displayContent = _stripAssistantMetaTags(widget.content);
    final isThinkingActive = widget.loading && hasReasoning;
    final thinkingTitle = hasReasoning
        ? (widget.loading
              ? '思考中'
              : '已完成思考')
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
      children: <Widget>[
        if (widget.agentSteps.isNotEmpty) ...<Widget>[
          ...widget.agentSteps.map(
            (AgentStep step) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    step.result != null
                        ? Icons.check_circle
                        : Icons.hourglass_empty,
                    size: 14,
                    color: step.result != null
                        ? AppColors.primaryGreen
                        : Colors.grey[500],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    step.result != null
                        ? '${step.label} -> ${step.result}'
                        : '${step.label}...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ),
          if (hasReasoning ||
              displayContent.isNotEmpty ||
              widget.loading) ...<Widget>[
            const SizedBox(height: 8),
            CustomPaint(
              size: const Size(double.infinity, 8),
              painter: _CurvedDividerPainter(),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (hasReasoning) ...<Widget>[
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
            onTap: () {
              setState(() => _reasoningExpanded = !_reasoningExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _reasoningExpanded
                    ? '收起'
                    : '展开全部',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
          ),
          if (displayContent.isNotEmpty || widget.loading) ...<Widget>[
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
            children: <Widget>[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                '思考中...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          )
        else
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
  const _EmptyHint();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '一定要花这笔钱吗？不花行不行？',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '输入你想买的东西，我会一起帮你判断值不值得买。',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '例：我想买一把机械键盘',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}
