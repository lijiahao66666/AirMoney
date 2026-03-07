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
  '\u8ffd\u95ee',
  '\u7ec6\u8282',
  '\u5e7d\u9ed8',
  '\u7406\u89e3',
  '\u8ba4\u540c',
  '\u5171\u60c5',
  '\u8fc7\u6e21',
  '\u56de\u5e94',
  '\u53cd\u5e94',
  '\u6807\u7b7e',
  '\u52a8\u4f5c',
  '\u7b56\u7565',
  '\u610f\u56fe',
  '\u5206\u6790',
  '\u603b\u7ed3',
  '\u5efa\u8bae',
  '\u63d0\u95ee',
  'intent',
  'reasoning',
  'meta',
];

String _stripAssistantMetaTags(String text) {
  if (text.isEmpty) return text;

  final pattern = RegExp(r'[锛?]\s*([^锛堬級()]{1,24})\s*[锛?]');
  final cleaned = text.replaceAllMapped(pattern, (Match match) {
    final inside = (match.group(1) ?? '').replaceAll(RegExp(r'\s+'), '');
    final isMeta = _assistantMetaMarkers.any(
      (String marker) => inside.toLowerCase().contains(marker.toLowerCase()),
    );
    return isMeta ? '' : (match.group(0) ?? '');
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

  void markChanged() {
    revision += 1;
  }

  void requestStop() {
    stopRequested = true;
    if (!stopSignal.isCompleted) {
      stopSignal.complete();
    }
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

    final ConsultSession cur = await ConsultSessionStorage.ensureCurrentSession();
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
    final ConsultSession? switched = await ConsultSessionStorage.switchToSession(
      session.id,
    );
    if (!mounted || switched == null) return;

    setState(() {
      _currentSession = switched;
      _messages = List<ConsultMessage>.from(switched.messages);
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

    final ConsultSession next = await ConsultSessionStorage.createNewSession();
    if (!mounted) return;

    setState(() {
      _currentSession = next;
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
        .replaceAll('\uFF08', '(')
        .replaceAll('\uFF09', ')')
        .replaceAll('\u2192', '->')
        .split('(')
        .first
        .split('->')
        .last
        .replaceAll(RegExp(r'[\s,.:;!?]'), '');

    for (final String category in AppConstants.expenseCategories) {
      if (text == category || text.contains(category)) return category;
    }
    return null;
  }

  String? _extractLastIntentCategory(List<ConsultMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final ConsultMessage msg = messages[i];
      final List<AgentStep>? steps = msg.agentSteps;
      if (msg.role != 'assistant' || steps == null || steps.isEmpty) continue;

      for (var j = steps.length - 1; j >= 0; j--) {
        final String? category = _normalizeIntentCategory(steps[j].result);
        if (category != null) return category;
      }
    }
    return null;
  }

  bool _hasTopicSwitchCue(String text) {
    final String t = text.trim().toLowerCase();
    if (t.isEmpty) return false;

    const List<String> cues = <String>[
      '\u6362\u4e00\u4e2a',
      '\u6362\u4e2a',
      '\u6539\u4e70',
      '\u6539\u6210',
      '\u4e0d\u4e70\u4e86',
      '\u5148\u4e0d\u4e70',
      '\u53e6\u5916',
      '\u53e6\u4e00\u4e2a',
      '\u73b0\u5728\u60f3\u4e70',
      '\u8fd8\u662f\u4e70',
      'instead',
      'another',
      'switch',
      'change',
      'different',
    ];

    return cues.any(t.contains);
  }

  Future<_IntentAnalysisDecision> _decideIntentAnalysis(String userText) async {
    final bool hasAssistant = _messages.any((ConsultMessage m) => m.role == 'assistant');
    final String? category = await classifyPurchaseIntentByAi(userText);

    if (!hasAssistant) {
      return _IntentAnalysisDecision(shouldAnalyze: true, category: category);
    }

    final String? previousCategory = _lastIntentCategory;
    final bool hasSwitchCue = _hasTopicSwitchCue(userText);
    final bool changedCategory =
        category != null && previousCategory != null && category != previousCategory;

    return _IntentAnalysisDecision(
      shouldAnalyze: hasSwitchCue || changedCategory,
      category: category,
    );
  }

  Map<String, double> _sanitizeCategoryTotals(Map<String, double> totals) {
    final Map<String, double> cleaned = <String, double>{};
    for (final MapEntry<String, double> entry in totals.entries) {
      final String key = entry.key.trim();
      final double value = entry.value;
      if (key.isEmpty || value <= 0) continue;
      cleaned[key] = (cleaned[key] ?? 0) + value;
    }
    return cleaned;
  }

  Future<void> _send() async {
    final String text = _controller.text.trim();
    if (text.isEmpty || _loading || _currentSession == null) return;

    final PointsProvider pointsProvider = context.read<PointsProvider>();
    final int points = pointsProvider.balance;
    if (points <= 0) {
      WalletSheet.show(
        context,
        points,
        () => context.read<PointsProvider>().syncFromServer(),
      );
      return;
    }

    final String sessionId = _currentSession!.id;
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
      setState(() {
        _sessions = ConsultSessionStorage.sessions;
      });
    }

    _scrollToBottom();

    final _IntentAnalysisDecision analysisDecision =
        await _decideIntentAnalysis(text);
    if (!mounted) return;

    Map<String, double>? recentSpending;
    if (analysisDecision.shouldAnalyze) {
      try {
        final DateTime now = DateTime.now();
        final DateTime end = DateTime(now.year, now.month, now.day);
        final DateTime start = end.subtract(const Duration(days: 29));

        final Map<String, double> totals =
            await context.read<BillProvider>().getCategoryTotalsInRange(
                  start,
                  end,
                  type: BillType.expense,
                );

        final Map<String, double> sanitized = _sanitizeCategoryTotals(totals);
        if (sanitized.isNotEmpty) {
          recentSpending = sanitized;
        }
      } catch (_) {}
    }

    final List<Map<String, String>> history = _messages
        .map(
          (ConsultMessage m) => <String, String>{
            'role': m.role,
            'content': m.content,
          },
        )
        .toList();

    final _ActiveConsultStreamState state = _ActiveConsultStreamState(
      sessionId: sessionId,
    );
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
    final Completer<void> done = Completer<void>();
    late final StreamSubscription<ConsultStreamChunk> sub;

    void finishOnce() {
      if (!done.isCompleted) done.complete();
    }

    sub = consultStream(
      conversationHistory: conversationHistory,
      recentCategorySpending: recentCategorySpending,
      enableAgentSteps: enableAgentSteps,
      intentAnalysisTargetText: intentAnalysisTargetText,
      preclassifiedIntentCategory: preclassifiedIntentCategory,
    ).listen(
      (ConsultStreamChunk chunk) {
        if (state.stopRequested) return;

        if (chunk.pointsBalance != null) {
          state.pointsBalance = chunk.pointsBalance;
        }
        if (chunk.agentSteps != null && chunk.agentSteps!.isNotEmpty) {
          state.agentSteps = List<AgentStep>.from(chunk.agentSteps!);
        }
        if (chunk.reasoningContent != null && chunk.reasoningContent!.isNotEmpty) {
          state.reasoning = (state.reasoning ?? '') + chunk.reasoningContent!;
        }
        if (chunk.content.isNotEmpty) {
          state.rawContent += chunk.content;
          state.content = _stripAssistantMetaTags(state.rawContent);
        }

        state.markChanged();
        if (chunk.isComplete) {
          finishOnce();
        }
      },
      onError: (Object e, StackTrace st) {
        if (!state.stopRequested) {
          state.errorMessage =
              '\u51fa\u9519\u4e86\uff1a${e.toString().replaceAll('Exception:', '').trim()}';
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

      final List<AgentStep>? finalizedSteps =
          state.agentSteps.isEmpty ? null : List<AgentStep>.from(state.agentSteps);

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
    final String? sessionId = _currentSession?.id;
    if (sessionId == null) return;

    final _ActiveConsultStreamState? active = _activeConsultStreams[sessionId];
    if (active == null) {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
        });
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

    final List<ConsultSession> sessions = ConsultSessionStorage.sessions;
    ConsultSession? current;
    for (final ConsultSession s in sessions) {
      if (s.id == sessionId) {
        current = s;
        break;
      }
    }

    final ConsultSession resolved =
        current ?? await ConsultSessionStorage.ensureCurrentSession();
    if (!mounted) return;
    if (_currentSession?.id != sessionId && resolved.id != sessionId) return;

    setState(() {
      _sessions = ConsultSessionStorage.sessions;
      _currentSession = resolved;
      _messages = List<ConsultMessage>.from(resolved.messages);
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
    final String? sessionId = _currentSession?.id;
    if (sessionId == null) return;

    final _ActiveConsultStreamState? active = _activeConsultStreams[sessionId];
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

    final bool changed =
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
        if (mounted) {
          context.read<PointsProvider>().syncFromServer();
        }
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
        duration: const Duration(milliseconds: 220),
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
        onSelect: (ConsultSession s) {
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
    final bool showStreamingItem =
        _loading ||
        _streamingContent.isNotEmpty ||
        _streamingRawContent.isNotEmpty ||
        _agentSteps.isNotEmpty ||
        (_streamingReasoning?.isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u8be5\u4e0d\u8be5\u82b1\uff1f'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: _loading || _loadingSessions ? null : _createNewSession,
            tooltip: '\u65b0\u5bf9\u8bdd',
            style: IconButton.styleFrom(foregroundColor: AppColors.primaryGreen),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _loadingSessions ? null : _showSessionList,
            tooltip: '\u5386\u53f2\u5bf9\u8bdd',
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
                          itemCount: _messages.length + (showStreamingItem ? 1 : 0),
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

                            final ConsultMessage msg = _messages[index];
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
                              hintText: '\u6211\u60f3\u2026',
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
                            backgroundColor:
                                _loading ? Colors.redAccent : AppColors.primaryGreen,
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
      builder: (BuildContext context, ScrollController sc) {
        return Column(
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
                    '\u4f1a\u8bdd\u5217\u8868',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  TextButton.icon(
                    onPressed: onNew,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('\u65b0\u5bf9\u8bdd'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: sessions.length,
                itemBuilder: (BuildContext context, int index) {
                  final ConsultSession s = sessions[index];
                  final bool isCurrent = s.id == currentId;
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
                    subtitle: Text('\${s.messages.length} \u6761\u6d88\u606f'),
                    onTap: () => onSelect(s),
                  );
                },
              ),
            ),
          ],
        );
      },
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
    final Color bg = isUser ? AppColors.primaryGreen : AppColors.primaryLight;
    final Color textColor = isUser ? Colors.white : Colors.black87;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: isUser
            ? Text(content, style: TextStyle(color: textColor, height: 1.5))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (steps.isNotEmpty)
                    ...steps.map(
                      (AgentStep step) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          step.result == null || step.result!.isEmpty
                              ? '\${step.label}...'
                              : '\${step.label}: \${step.result}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ),
                    ),
                  if ((reasoning?.isNotEmpty ?? false))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        reasoning!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.4),
                      ),
                    ),
                  if (content.isNotEmpty)
                    Text(
                      _stripAssistantMetaTags(content),
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    )
                  else if (loading)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '\u601d\u8003\u4e2d...',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                ],
              ),
      ),
    );
  }
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
            Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '\u4e00\u5b9a\u8981\u82b1\u8fd9\u7b14\u94b1\u5417\uff1f\u4e0d\u82b1\u884c\u4e0d\u884c\uff1f',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '\u8f93\u5165\u4f60\u60f3\u4e70\u7684\u4e1c\u897f\uff0c\u6211\u4f1a\u4e00\u8d77\u5e2e\u4f60\u5224\u65ad\u662f\u5426\u503c\u5f97\u8d2d\u4e70\u3002',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '\u4f8b\uff1a\u6211\u60f3\u4e70\u4e00\u628a\u673a\u68b0\u952e\u76d8',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}