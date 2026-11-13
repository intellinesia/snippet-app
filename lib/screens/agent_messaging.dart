import 'package:snippet/ambient/hold.dart';
import 'package:snippet/ambient/live_caption.dart';
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import '../motion_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../chat/chat_info.dart' show showAgentInfo;
import '../glass.dart';
import '../api.dart';
import '../clock.dart';
import '../chat/chat_style.dart';
import '../composer/attachment_preview.dart';
import '../composer/attachment_tile.dart';
import '../composer/composer_card.dart';
import '../composer_strip.dart';
import '../media_views.dart';
import '../message_reactions.dart';
import '../motion.dart';
import '../desktop_pick.dart';
import '../models.dart';
import '../presence.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../swr.dart';
import '../pull_refresh.dart';
import 'agent_questions_card.dart';
import 'agent_records.dart';
import 'agent_thread_cards.dart';
import 'agent_view_switcher.dart';
import 'tasks/tasks_panel.dart';

/// Pick one agent from the directory, as an anchored DROPDOWN.
///
/// Returns null when dismissed. Shared by the composer's recipient picker and
/// the message sheet so both offer the same list, in the same order.
///
/// Mission Control is NOT offered. It is the coordinator, reached by opening its
/// own session, so listing it as a recipient elsewhere would be a second path to
/// the same place — and would let a message meant for a worker land on the
/// coordinator. Agents reach Mission Control through their own tools, not here.
Future<CoordinationAgent?> pickAgentId(
  BuildContext context,
  DaemonClient client, {
  String title = 'Select an agent',
  Set<String> exclude = const {},
  String? currentAgentId,
  BuildContext? anchor,
  BuildContext? verticalAnchor,
}) async {
  List<CoordinationAgent> agents;
  try {
    agents = await client.coordinationAgents();
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
    return null;
  }
  final candidates = agents
      .where((a) =>
          !exclude.contains(a.id) &&
          // Mission Control is reached through its own chat, not picked here.
          // Offering it would let a message aimed at a worker land on the
          // coordinator.
          !a.isMissionControl)
      .toList();
  if (!context.mounted) return null;
  if (candidates.isEmpty) {
    toast(context, 'No agents available');
    return null;
  }
  candidates.sort((a, b) => a.displayName.compareTo(b.displayName));

  // A dropdown, the SAME control as the approval and inference pickers: an
  // anchored popover on desktop, a bottom sheet on mobile. A centered dialog
  // for a short list of destinations was heavier than the thing it replaced.
  final picked = await showAppMenu<String>(
    context,
    anchor: anchor ?? context,
    verticalAnchor: verticalAnchor,
    minWidth: 260,
    maxWidth: 360,
    items: [
      appMenuHeading<String>(title),
      for (final a in candidates)
        appMenuRow<String>(
          value: a.id,
          icon: 'agent',
          label: a.displayName.trim().isEmpty ? a.id : a.displayName,
          description: '@${a.handle} · ${a.status}',
          selected: a.id == currentAgentId,
        ),
    ],
  );
  if (picked == null) return null;
  for (final a in candidates) {
    if (a.id == picked) return a;
  }
  return null;
}

/// Message one agent from one session.
///
/// The sheet collects only what a human can decide — who, and what to say. It
/// sends a DIRECT MESSAGE carrying this session as its origin, so the agent
/// knows which session to reply in and which session to request dispatch on.
/// Nothing here creates work: dispatching belongs to Mission Control.
class AgentWorkSheet extends StatefulWidget {
  const AgentWorkSheet({
    super.key,
    required this.client,
    required this.sessionId,
    this.initialAgentId,
    this.workspaceLabel,
  });

  final DaemonClient client;

  /// The durable session the work lands in.
  final String sessionId;

  /// Pre-selected agent, when the sheet was opened from that agent's row.
  final String? initialAgentId;

  /// Shown as read-only context so the user can confirm the target workspace.
  final String? workspaceLabel;

  @override
  State<AgentWorkSheet> createState() => _AgentWorkSheetState();
}

class _AgentWorkSheetState extends State<AgentWorkSheet> {
  final _message = TextEditingController();

  String? _agentId;
  String? _agentName;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _agentId = widget.initialAgentId;
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final agents = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Resolve a display name for a pre-selected agent; leave the choice
        // open otherwise.
        for (final a in agents) {
          if (a.id == _agentId) {
            _agentName = a.displayName.trim().isEmpty ? a.id : a.displayName;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _chooseAgent(BuildContext anchor) async {
    final picked = await pickAgentId(context, widget.client, anchor: anchor);
    if (picked == null || !mounted) return;
    setState(() {
      _agentId = picked.id;
      _agentName =
          picked.displayName.trim().isEmpty ? picked.id : picked.displayName;
    });
  }

  Future<void> _submit() async {
    final agentId = _agentId;
    if (agentId == null) {
      setState(() => _error = 'Choose an agent');
      return;
    }
    final message = _message.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Write a message');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.client.sendAgentMessage(
        toAgentId: agentId,
        body: message,
        // Ask FROM this session. The agent then knows which session to reply in
        // AND which session to request dispatch on — the whole reason this is a
        // message rather than a dispatch.
        originSession: widget.sessionId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // Keep the sheet and its input: a failed send must not cost the user what
      // they just typed.
      setState(() {
        _sending = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: PageLoader(),
      );
    }
    final workspace = widget.workspaceLabel?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (workspace.isNotEmpty) ...[
          Text('workspace', style: mono(10, color: AppColors.fg3)),
          const SizedBox(height: 4),
          Text(workspace,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg2)),
          const SizedBox(height: 14),
        ],
        Text('agent', style: mono(10, color: AppColors.fg3)),
        const SizedBox(height: 4),
        Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
          child: Builder(
            builder: (ctx) => InkWell(
              onTap: _sending ? null : () => _chooseAgent(ctx),
              borderRadius: BorderRadius.circular(R.sm),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                child: Row(children: [
                  AppIcon('agent', size: 15, color: AppColors.fg3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_agentName ?? 'Choose an agent',
                        style: sans(13,
                            color: _agentName == null
                                ? AppColors.fg4
                                : AppColors.fg1)),
                  ),
                  AppIcon('chevron-down', size: 13, color: AppColors.fg4),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppField(
          label: 'message',
          controller: _message,
          hint: 'What should this agent do?',
          minLines: 3,
          maxLines: 7,
          enabled: !_sending,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: sans(12, color: AppColors.danger)),
        ],
        const SizedBox(height: 18),
        Row(children: [
          if (!kMobile) ...[
            Expanded(
              child: Btn('Cancel',
                  variant: BtnVariant.ghost,
                  full: true,
                  disabled: _sending,
                  onTap: () => Navigator.of(context).pop(false)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Btn(_sending ? 'Sending…' : 'Send',
                full: true, disabled: _sending, onTap: _submit),
          ),
        ]),
      ],
    );
  }
}

/// A direct conversation with one agent.
///
/// This is conversation, not work control: it shows what was said and lets the
/// user reply. A message never authorises a workspace change, so a chat cannot
/// silently start work.
class AgentThreadScreen extends StatefulWidget {
  const AgentThreadScreen({
    super.key,
    required this.client,
    required this.agentId,
    required this.agentName,
    this.subtitle,
    this.onClose,
    this.embedded = false,
    this.tabHeader = false,
    this.showBack = true,
    this.deskTrailing,
    this.onDeskInfo,
  });

  final DaemonClient client;
  final String agentId;
  final String agentName;

  /// Identity line under the name (`@handle · status`). Supplied by the
  /// caller, which owns the agent record.
  final String? subtitle;

  final VoidCallback? onClose;

  /// Nested under a host that already draws `NavBackRow`.
  final bool embedded;

  /// Desktop shell tab: embedded, but keeps the centred header from v5.
  final bool tabHeader;

  final bool showBack;
  final Widget? deskTrailing;

  /// Desktop shell: the title opens the docked info panel instead of a dialog.
  final VoidCallback? onDeskInfo;

  @override
  State<AgentThreadScreen> createState() => _AgentThreadScreenState();
}

class _AgentThreadScreenState extends State<AgentThreadScreen> {
  void _closePage() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  String? _fetchedLine;
  bool _fetchedPaused = false;
  String? _fetchedProfile;
  String? _profileProvider;
  int? _openTaskCount;
  final GlobalKey _headerKey = GlobalKey();

  void _loadLine() {
    widget.client.coordinationAgents().then((all) {
      final a = all.where((x) => x.id == widget.agentId).firstOrNull;
      if (a == null || !mounted) return;
      final line = [
        if (!a.available) 'Paused',
        if (a.profile != null) a.profile!,
      ].join(' \u00b7 ');
      final openTasks = a.taskCounts == null
          ? null
          : a.tasksIn({'todo', 'in_progress', 'in_review', 'blocked'});
      setState(() {
        _fetchedLine = line;
        _fetchedPaused = !a.available;
        _fetchedProfile = a.profile;
        _openTaskCount = openTasks;
      });
      final name = a.profile;
      if (name == null) return;
      widget.client.getConfig().then((cfg) {
        final p = cfg.profiles.where((x) => x.name == name).firstOrNull;
        if (p != null && mounted) setState(() => _profileProvider = p.provider);
      }).catchError((_) {});
    }).catchError((_) {});
  }

  AgentView _view = AgentView.thread;
  String? _filter;
  int _unread = 0;

  void _loadUnread() => agentInboxUnread(widget.client, widget.agentId)
      .then((n) {
        if (mounted) setState(() => _unread = n);
      })
      .catchError((_) {});

  void _setView(AgentView v) {
    final leftInbox = _view == AgentView.inbox;
    setState(() {
      _view = v;
      _filter = null;
      if (leftInbox) _unread = 0;
    });
    if (leftInbox) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _loadUnread();
      });
    }
  }

  void _openInfo() => unawaited(showAgentInfo(
        context,
        client: widget.client,
        agentId: widget.agentId,
        name: widget.agentName,
        onOpenTasks: _openTasks,
        onOpenInbox: () => _setView(AgentView.inbox),
        onOpenBoard: () => _setView(AgentView.board),
        onOpenDesk: () => openAgentDesk(
            context, widget.client, widget.agentId, widget.agentName),
      ));

  void _openTasks() {
    openTasksPage(context, widget.client, agentIds: {widget.agentId});
  }

  Future<void> _openSwitcherMenu(BuildContext anchor) async {
    final picked = await showAppMenu<AgentView>(
      context,
      anchor: anchor,
      below: true,
      alignEnd: true,
      minWidth: 180,
      items: [
        for (final (v, icon, label) in const [
          (AgentView.thread, 'message', 'Thread'),
          (AgentView.inbox, 'inbox', 'Inbox'),
          (AgentView.board, 'clipboard', 'Board'),
        ])
          appMenuRow<AgentView>(
            value: v,
            icon: icon,
            label: label,
            trailing: v == AgentView.inbox && _unread > 0 ? '$_unread' : null,
            selected: v == _view,
          ),
      ],
    );
    if (picked != null && picked != _view && mounted) _setView(picked);
  }

  Widget _viewBody() {
    final recordsTop = _noChrome ? 0.0 : ChatHeader.overlap;
    final child = switch (_view) {
      AgentView.thread => KeyedSubtree(
          key: const ValueKey(AgentView.thread), child: _body()),
      _ => KeyedSubtree(
          key: ValueKey(_view),
          child: Padding(
            padding: EdgeInsets.only(top: recordsTop),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: agentRecordsBody(
                    widget.client, widget.agentId, widget.agentName,
                    board: _view == AgentView.board,
                    filter: _filter,
                    filterChips: !kMobile),
              ),
            ),
          )),
    };
    return AnimatedSwitcher(
      duration: reduceMotion(context) ? Duration.zero : Motion.base,
      switchInCurve: Motion.exit,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }

  void _openActions() => openAgentActions(context,
      client: widget.client,
      agentId: widget.agentId,
      agentName: widget.agentName,
      views: false,
      onDeleted: _closePage);

  List<(String, String?)> get _filters => switch (_view) {
        AgentView.inbox => agentInboxFilters,
        AgentView.board => agentBoardFilters,
        AgentView.thread => const [],
      };

  String get _viewLine {
    final view = switch (_view) {
      AgentView.thread => 'Chat',
      AgentView.inbox => 'Inbox',
      AgentView.board => 'Board',
    };
    final f = _filters.where((f) => f.$2 != null && f.$2 == _filter);
    return f.isEmpty ? view : '$view \u00b7 ${f.first.$1}';
  }

  /// The title menu: the views, the open view's filters, and the rest
  /// of the agent behind More actions.
  Future<void> _openViewMenu({BuildContext? anchor}) async {
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor,
      below: anchor != null,
      minWidth: 240,
      items: [
        for (final (v, icon, label) in const [
          (AgentView.thread, 'message', 'Chat'),
          (AgentView.inbox, 'inbox', 'Inbox'),
          (AgentView.board, 'clipboard', 'Board'),
        ])
          appMenuRow<String>(
            value: 'view:${v.name}',
            icon: icon,
            label: label,
            trailing: v == AgentView.inbox && _unread > 0 ? '$_unread' : null,
            selected: v == _view,
          ),
        appMenuRow<String>(
            value: 'desk', icon: 'terminal', label: 'Desk session'),
        if (_filters.isNotEmpty) ...[
          const PopupMenuDivider(),
          appMenuHeading<String>('Show'),
          for (final (label, value) in _filters)
            appMenuRow<String>(
              value: 'filter:${value ?? ''}',
              icon: switch (value) {
                'offer' || 'dispatched' => 'send',
                'message' => 'message',
                'room' => 'users',
                'by-task' => 'clipboard',
                'by-folder' => 'folder',
                'waiting' => 'clock',
                'reported' => 'check-circle',
                'progress' => 'activity',
                'noted' => 'edit',
                _ => 'list',
              },
              label: label,
              selected: value == _filter,
            ),
        ],
        appMenuRow<String>(
          value: 'actions',
          icon: 'more-horizontal',
          label: 'More actions',
          trailingWidget:
              AppIcon('chevron-right', size: 14, color: AppColors.fg3),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == 'actions') return _openActions();
    if (picked == 'desk') {
      return openAgentDesk(
          context, widget.client, widget.agentId, widget.agentName);
    }
    if (picked.startsWith('view:')) {
      final v = AgentView.values.byName(picked.substring(5));
      if (v != _view) _setView(v);
      return;
    }
    if (picked.startsWith('filter:')) {
      final f = picked.substring(7);
      setState(() => _filter = f.isEmpty ? null : f);
    }
  }
  static const _maxAttachments = 10;
  Duration _maxRecordingDuration = const Duration(minutes: 3);

  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  CoordinationEvent? _replyTo;
  List<CoordinationEvent> _events = const [];
  Map<String, MessageDelivery> _deliveries = const {};
  bool _loading = true;
  final bool _sending = false;
  String? _error;
  late final Swr<DirectThreadPage> _thread;

  final List<_AgentAttachment> _attachments = [];

  @visibleForTesting
  void debugSeedAttachment(String name) => setState(() => _attachments
      .add(_AgentAttachment(name: name, isImage: false, isAudio: false)
        ..uploading = false));
  int _attachmentGeneration = 0;

  final AudioRecorder _recorder = HeldRecorder();
  AudioPlayer? _player;

  AudioPlayer get _audioPlayer {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _playerStateSub = player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlayingRecording = state == PlayerState.playing);
    });
    _positionSub = player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _playbackPosition = position);
    });
    _durationSub = player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _playbackDuration = duration);
    });
    return _player = player;
  }

  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _recordingTimer;

  bool _isRecording = false;
  String? _recordingPath;
  Uint8List? _recordingBytes;
  Duration _recordingElapsed = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  bool _isPlayingRecording = false;
  final WaveBuffer _waveform = WaveBuffer();

  @override
  void initState() {
    super.initState();
    _loadLine();
    _loadUnread();
    _thread = Swr<DirectThreadPage>(
      client: widget.client,
      key: 'agent-thread:${widget.agentId}',
      fetch: () => widget.client.agentThreadPage(peerId: widget.agentId),
      revalidateOn: Swr.coordination,
      onChange: _sync,
    );
    _events = _thread.data?.events ?? const [];
    _deliveries = _thread.data?.deliveries ?? const {};
    _loading = _thread.data == null;
    if (_events.isNotEmpty) _jumpToBottom();
  }

  @override
  void dispose() {
    _thread.dispose();
    _amplitudeSub?.cancel();
    _recordingTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    if (_isRecording) {
      unawaited(_recorder.cancel());
    }
    if (kCanRecord) {
      unawaited(_recorder.dispose());
    }
    final player = _player;
    if (player != null) unawaited(player.dispose());
    final pendingPath = _recordingPath;
    if (pendingPath != null) {
      try {
        final f = File(pendingPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) => _thread.refresh();

  // Sent but not yet in a fetched list; merged back so a refetch can't hide them.
  final List<CoordinationEvent> _unechoed = [];

  static bool _isAck(CoordinationEvent e) => e.payload['auto'] == 'ack';

  bool get _typing {
    CoordinationEvent? last;
    for (final e in _events.reversed) {
      if (!_isAck(e) && !isReactionEvent(e)) {
        last = e;
        break;
      }
    }
    if (last == null || last.actorKind != 'human') return false;
    if (_deliveries[last.eventId]?.readAt == null) return false;
    final p = widget.client.presence.presenceForAgentId(widget.agentId);
    return p?.state == 'running' || p?.state == 'tool';
  }

  void _sync() {
    if (!mounted) return;
    final next = _thread.data;
    if (next != null) {
      final keys = {for (final e in next.events) e.idempotencyKey};
      final bodies = {
        for (final e in next.events)
          if (e.actorKind == 'human' && !isReactionEvent(e)) e.payload['body']
      };
      _unechoed.removeWhere((p) =>
          keys.contains(p.idempotencyKey) ||
          (!isReactionEvent(p) && bodies.contains(p.payload['body'])));
    }
    final merged = next == null ? null : [...next.events, ..._unechoed];
    final hadNew = merged != null && merged.length > _events.length;
    final first = _events.isEmpty;
    setState(() {
      if (merged != null) _events = merged;
      if (next != null) _deliveries = next.deliveries;
      _loading = _thread.loading;
      _error =
          next == null && _thread.error != null ? '${_thread.error}' : null;
    });
    if (hadNew) {
      unawaitedMarkRead();
      _jumpToBottom(animated: !first);
    }
  }

  void unawaitedMarkRead() {
    widget.client
        .markAgentThreadRead(peerId: widget.agentId)
        .catchError((_) {});
  }

  void _jumpToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        if (animated) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: Motion.fast,
            curve: Motion.enter,
          );
        } else {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _onMicTap() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!kCanRecord) return;
    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingElapsed = Duration.zero;
        _waveform
          ..clear()
          ..add(0.08);
      });
    }
    final granted = kMobile
        ? (await Permission.microphone.request()).isGranted
        : await _recorder.hasPermission();
    if (!granted) {
      if (mounted) setState(() => _isRecording = false);
      if (mounted) {
        toast(
          context,
          kMobile
              ? 'Microphone permission is required.'
              : 'Microphone permission is required by macOS.',
          danger: true,
        );
        if (kMobile) {
          final status = await Permission.microphone.status;
          if (status.isPermanentlyDenied) await openAppSettings();
        }
      }
      return;
    }
    try {
      final voice = (await widget.client
              .getConfig()
              .timeout(const Duration(seconds: 3)))
          .voice;
      if (!voice.enabled) {
        if (mounted) {
          setState(() => _isRecording = false);
          toast(context, 'Voice notes are turned off in Settings → Voice.');
        }
        return;
      }
      _maxRecordingDuration = Duration(seconds: voice.maxSeconds);
    } catch (_) {
    }
    try {
      if (_recordingPath != null || _recordingBytes != null) {
        await _discardRecording();
      }
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/snippet-agent-voice-${DateTime.now().microsecondsSinceEpoch}.$voiceNoteExtension';
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: kMobile ? 16000 : 44100,
          numChannels: 1,
          androidConfig: const AndroidRecordConfig(manageBluetooth: false),
        ),
        path: path,
      );
      if (!await _recorder.isRecording()) {
        await _recorder.cancel();
        if (mounted) setState(() => _isRecording = false);
        if (mounted) toast(context, 'Could not start recording.', danger: true);
        return;
      }
      _amplitudeSub?.cancel();
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
        final level = ((a.current + 60) / 60).clamp(0.04, 1.0).toDouble();
        if (!mounted) return;
        _waveform.add(level);
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _recordingElapsed + const Duration(seconds: 1);
        if (next >= _maxRecordingDuration) {
          setState(() => _recordingElapsed = _maxRecordingDuration);
          unawaited(_stopRecording());
          final d = _maxRecordingDuration;
          toast(context,
              'Recording stopped at the ${d.inSeconds % 60 == 0 ? '${d.inMinutes}-minute' : '${d.inSeconds}-second'} limit.');
        } else {
          setState(() => _recordingElapsed = next);
        }
      });
      if (mounted) setState(() => _recordingPath = path);
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
      if (mounted) {
        toast(context, 'Could not start recording: $e', danger: true);
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    if (mounted) setState(() => _isRecording = false);
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final stoppedPath = await _recorder.stop();
      final path = stoppedPath ?? _recordingPath;
      if (path == null) {
        if (mounted) toast(context, 'No recording was captured.');
        return;
      }
      final bytes = await _waitForRecordingFile(path);
      if (bytes == null || bytes.isEmpty) {
        await _discardRecording();
        if (mounted) toast(context, 'The recording was empty.');
        return;
      }
      if (mounted) {
        setState(() {
          _recordingPath = path;
          _recordingBytes = bytes;
        });
      } else {
        _recordingPath = path;
        _recordingBytes = bytes;
      }
    } catch (e) {
      await _discardRecording();
      if (mounted) {
        toast(context, 'Could not finish recording: $e', danger: true);
      }
    }
  }

  Future<Uint8List?> _waitForRecordingFile(String path) async {
    final file = File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path);
    const attempts = 120;
    for (var i = 0; i < attempts; i++) {
      try {
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  Future<void> _discardRecording() async {
    final path = _recordingPath;
    if (_isRecording) {
      try {
        await _recorder.cancel();
      } catch (_) {}
    }
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      await _player?.stop();
    } catch (_) {}
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingBytes = null;
        _recordingElapsed = Duration.zero;
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
        _waveform.clear();
        _isPlayingRecording = false;
      });
    }
  }

  Future<void> _recordMore() async {
    if (await _confirmRecording()) await _startRecording();
  }

  Future<bool> _confirmRecording() async {
    final path = _recordingPath;
    final bytes = _recordingBytes;
    if (path == null && bytes == null) return false;
    try {
      if (bytes == null || bytes.isEmpty) {
        await _discardRecording();
        if (mounted) toast(context, 'The recording was empty.');
        return false;
      }
      await _ingest([
        (
          name: 'voice-${DateTime.now().microsecondsSinceEpoch}.$voiceNoteExtension',
          localPath: null,
          readBytes: () async => bytes,
        )
      ]);
      await _player?.stop();
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingPath = null;
          _recordingBytes = null;
          _recordingElapsed = Duration.zero;
          _waveform.clear();
          _playbackPosition = Duration.zero;
          _playbackDuration = Duration.zero;
          _isPlayingRecording = false;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        toast(context, 'Could not attach recording: $e', danger: true);
      }
      return false;
    }
  }

  Future<void> _toggleRecordingPlayback() async {
    final path = _recordingPath;
    if (path == null || _isRecording) return;
    try {
      if (_isPlayingRecording) {
        await _audioPlayer.pause();
      } else if (_audioPlayer.state == PlayerState.paused) {
        await _audioPlayer.resume();
      } else {
        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not play preview: $e', danger: true);
    }
  }

  String _audioTime(Duration d) {
    final seconds = d.inSeconds.clamp(0, 5999);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  bool _isImageName(String n) {
    final l = n.toLowerCase();
    return const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.heic',
      '.heif'
    ].any(l.endsWith);
  }

  Future<void> _onAttachTap() async {
    if (!kMobile) {
      await _pickFiles();
      return;
    }
    final choice = await showAppSheet<String>(
      context,
      title: 'Attach',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            _attachOption('camera', 'Camera', 'camera'),
            const SizedBox(width: 10),
            _attachOption('image', 'Photos', 'photos'),
            const SizedBox(width: 10),
            _attachOption('file', 'Files', 'files'),
          ],
        ),
      ),
    );
    if (choice == 'camera') {
      await _pickCamera();
    } else if (choice == 'photos') {
      await _pickPhotos();
    } else if (choice == 'files') {
      await _pickFiles();
    }
  }

  Widget _attachOption(String icon, String label, String value) {
    return Expanded(
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: () => Navigator.pop(context, value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: 22, color: AppColors.fg2),
                const SizedBox(height: 8),
                Text(label, style: sans(12, color: AppColors.fg1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhotos() async {
    final xs =
        await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2200);
    if (xs.isEmpty) return;
    await _ingest(xs
        .map((x) => (name: x.name, localPath: x.path, readBytes: x.readAsBytes))
        .toList());
  }

  Future<void> _pickCamera() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
    if (x == null) return;
    await _ingest(
        [(name: x.name, localPath: x.path, readBytes: x.readAsBytes)]);
  }

  Future<void> _pickFiles() async {
    List<PickedLocalFile> files;
    try {
      files = await pickLocalFiles();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
      return;
    }
    if (files.isEmpty) return;
    await _ingest(files
        .map((f) => (
              name: f.name,
              localPath: f.path,
              readBytes: f.readAsBytes,
            ))
        .toList());
  }

  Future<void> _ingest(
      List<
              ({
                String name,
                String? localPath,
                Future<Uint8List> Function() readBytes
              })>
          picked) async {
    final remaining = _maxAttachments - _attachments.length;
    if (remaining <= 0) {
      toast(context, 'Max $_maxAttachments attachments reached.');
      return;
    }
    var items = picked;
    if (items.length > remaining) {
      items = items.take(remaining).toList();
      toast(context, 'Added $remaining (max $_maxAttachments).');
    }
    final entries = items
        .map((p) => _AgentAttachment(
              name: p.name,
              isImage: _isImageName(p.name),
              isAudio: isAudioAttachmentPath(p.name),
              localPath: p.localPath,
            ))
        .toList();
    if (entries.isEmpty) return;
    setState(() => _attachments.addAll(entries));
    final generation = _attachmentGeneration;
    for (var i = 0; i < entries.length; i++) {
      final p = items[i];
      final a = entries[i];
      try {
        final bytes = await p.readBytes();
        final path = await widget.client.uploadFile(bytes, name: p.name);
        if (!mounted || generation != _attachmentGeneration) return;
        setState(() {
          a.remotePath = path;
          a.uploading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _attachments.remove(a));
        toast(context, 'Upload failed: ${p.name}', danger: true);
      }
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_isRecording) {
      await _stopRecording();
    }
    if (_recordingPath != null) {
      final ok = await _confirmRecording();
      if (!ok) return;
    }
    if (_attachments.any((a) => a.uploading)) {
      if (!mounted) return;
      toast(context, 'Please wait for attachments to upload');
      return;
    }
    final ready = _attachments.where((a) => a.remotePath != null).toList();
    final markers = ready
        .map((a) => a.isImage
            ? '[attached image — call view_image on this exact path to see it: ${a.remotePath}]'
            : '[attached file — read it at this exact path: ${a.remotePath}]')
        .toList();
    var body = _input.text.trim();
    if (markers.isNotEmpty) {
      body = body.isEmpty
          ? markers.join('\n\n')
          : '$body\n\n${markers.join('\n\n')}';
    }
    if (body.isEmpty) return;
    final typed = _input.text;
    final replyTarget = _replyTo;
    final replyToId = replyTarget?.eventId;
    final key = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final pending = CoordinationEvent.fromJson({
      'event_id': key,
      'event_type': 'direct_message.sent',
      'actor_kind': 'human',
      'actor_id': 'local',
      'payload': {
        'body': body,
        if (replyToId != null && replyToId.isNotEmpty) 'reply_to': replyToId,
      },
      'idempotency_key': key,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    _input.clear();
    _attachmentGeneration++;
    _attachments.clear();
    _discardRecording();
    _unechoed.add(pending);
    setState(() {
      _replyTo = null;
      _events = [..._events, pending];
    });
    _jumpToBottom(animated: true);
    try {
      await widget.client.sendAgentMessage(
        toAgentId: widget.agentId,
        body: body,
        idempotencyKey: key,
        replyTo: replyToId,
      );
      if (!mounted) return;
      await _load(silent: true);
    } catch (e) {
      _unechoed.removeWhere((p) => p.eventId == key);
      if (!mounted) return;
      setState(() {
        _replyTo ??= replyTarget;
        _events = [
          for (final ev in _events)
            if (ev.eventId != key) ev
        ];
      });
      if (_input.text.isEmpty) _input.text = typed;
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _sendReaction(CoordinationEvent target, String reaction) async {
    if (target.eventId.isEmpty) return;
    final already = _events.any((e) =>
        e.actorKind == 'human' &&
        e.replyTo == target.eventId &&
        e.reaction == reaction);
    if (already) return;
    final key = 'local-react-${DateTime.now().microsecondsSinceEpoch}';
    final pending = CoordinationEvent.fromJson({
      'event_id': key,
      'event_type': 'direct_message.sent',
      'actor_kind': 'human',
      'actor_id': 'local',
      'payload': {
        'body': '',
        'kind': 'reaction',
        'reply_to': target.eventId,
        'reaction': reaction,
      },
      'idempotency_key': key,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    _unechoed.add(pending);
    setState(() => _events = [..._events, pending]);
    try {
      await widget.client.sendAgentMessage(
        toAgentId: widget.agentId,
        body: '',
        idempotencyKey: key,
        replyTo: target.eventId,
        reaction: reaction,
      );
      if (!mounted) return;
      await _load(silent: true);
    } catch (e) {
      _unechoed.removeWhere((p) => p.eventId == key);
      if (!mounted) return;
      setState(() => _events = [
            for (final ev in _events)
              if (ev.eventId != key) ev
          ]);
      toast(context, '$e', danger: true);
    }
  }

  void _startReply(CoordinationEvent target) {
    setState(() => _replyTo = target);
    _inputFocus.requestFocus();
  }

  GlobalKey _keyForEvent(String eventId) =>
      _messageKeys.putIfAbsent(eventId, GlobalKey.new);

  void _scrollToMessage(String eventId) {
    final visible = [
      for (final e in _events)
        if (!isReactionEvent(e)) e
    ];
    final ctx = _messageKeys[eventId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: reduceMotion(context) ? Duration.zero : Motion.fast,
        curve: Motion.enter,
      );
      return;
    }
    if (!_scroll.hasClients || visible.isEmpty) return;
    final idx = visible.indexWhere((e) => e.eventId == eventId);
    if (idx < 0) return;
    final fraction = (idx / visible.length).clamp(0.0, 1.0);
    _scroll.jumpTo(_scroll.position.maxScrollExtent * fraction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final after = _messageKeys[eventId]?.currentContext;
      if (after != null) {
        Scrollable.ensureVisible(after, alignment: 0.3);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Wrapped in Material because presentScreen's non-rounded frames are plain
    // Containers — no Material ancestor — while a TextField and the icon buttons
    // here require one.
    final hideChrome = _noChrome;
    return Material(
      color: kMobile ? readingBg : Colors.transparent,
      child: SafeArea(
        top: !hideChrome,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                      child: kMobile || hideChrome
                          ? _viewBody()
                          : TopFadeMask(
                              clear: ChatHeader.overlap - 24,
                              child: _viewBody())),
                  if (!hideChrome)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: _header(),
                    ),
                ],
              ),
            ),
            if (_view == AgentView.thread) _composer(),
          ],
        ),
      ),
    );
  }

  Widget _headerStatus(String subtitle) {
    final store = widget.client.presence;
    return ListenableBuilder(
      listenable: store,
      builder: (_, __) {
        final p = store.presenceForAgentId(widget.agentId);
        if (p == null) return _plainHeaderStatus(subtitle);
        final status = _typing ? 'typing…' : PresenceStore.chatWord(p);
        final dots = p.state == 'thinking' || p.state == 'typing';
        if (status.isEmpty && !dots) return _plainHeaderStatus(subtitle);
        final cut = subtitle.indexOf(' \u00b7 ');
        final head = cut < 0 ? '' : subtitle.substring(0, cut);
        final text = status.isEmpty
            ? subtitle
            : head.isEmpty
                ? status
                : '$head \u00b7 $status';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: ChatHeader.statusText(text)),
            if (dots) ...[
              const SizedBox(width: 4),
              WorkingDots(color: ChatColors.meta, size: 4),
            ],
          ],
        );
      },
    );
  }

  Widget _plainHeaderStatus(String subtitle) {
    final logo = widget.subtitle == null && _profileProvider != null;
    if (!logo) {
      return subtitle.isEmpty
          ? const SizedBox.shrink()
          : ChatHeader.statusText(subtitle);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_fetchedPaused)
          Flexible(child: ChatHeader.statusText('Paused \u00b7 ')),
        Tooltip(
            message: _fetchedProfile ?? '',
            child: ProviderLogo(_profileProvider, size: 13)),
      ],
    );
  }

  bool get _noChrome => widget.embedded && !widget.tabHeader;

  Widget _header() {
    final subtitle = (widget.subtitle ?? _fetchedLine ?? '').trim();
    final canPop = !widget.embedded &&
        widget.showBack &&
        (kMobile
            ? (widget.onClose != null || Navigator.of(context).canPop())
            : Navigator.of(context).canPop());
    final Widget? trailing;
    if (widget.tabHeader) {
      trailing = widget.deskTrailing;
    } else if (kMobile) {
      trailing = ChatGlassButton(
        icon: 'task',
        tooltip: 'Tasks',
        badge: (_openTaskCount ?? 0) > 0 ? _openTaskCount : null,
        onTap: _openTasks,
      );
    } else {
      final switcher = Builder(
        builder: (btnCtx) => ChatGlassButton(
          icon: 'layers',
          tooltip: 'Switch view',
          badge: _unread > 0 ? _unread : null,
          onTap: () => _openSwitcherMenu(btnCtx),
        ),
      );
      trailing = !widget.embedded && widget.onClose != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                switcher,
                const SizedBox(width: 6),
                ChatGlassButton(
                  icon: 'x',
                  tooltip: 'Close',
                  onTap: widget.onClose!,
                ),
              ],
            )
          : switcher;
    }
    return ChatHeader(
      key: _headerKey,
      agentIds: [widget.agentId],
      title: widget.agentName,
      status: _view == AgentView.thread
          ? _headerStatus(subtitle)
          : ChatHeader.statusText(_viewLine),
      onTitleTap: _view == AgentView.thread
          ? (widget.onDeskInfo ?? _openInfo)
          : () => _openViewMenu(
              anchor: kMobile ? null : _headerKey.currentContext),
      titleHint: _view == AgentView.thread ? 'Info' : 'Switch view',
      onBack: canPop ? _closePage : null,
      trailing: trailing,
    );
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static DateTime? _eventTime(CoordinationEvent e) =>
      DateTime.tryParse(e.createdAt)?.toLocal();

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _clockLabel(DateTime t) => clock12(t);

  static String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days > 1 && days < 7) return _weekdays[t.weekday - 1];
    final date = '${t.day} ${_months[t.month - 1]}';
    return t.year == now.year ? date : '$date ${t.year}';
  }

  bool _hasTaskOrigin(CoordinationEvent e) {
    if (e.actorKind == 'human') return false;
    final origin = e.payload['origin_session'];
    // Mission Control's session is its own inbox.
    return origin is String &&
        origin.isNotEmpty &&
        origin != 'inbox-${widget.agentId}' &&
        origin != widget.agentId;
  }

  String? _deliveryLine(CoordinationEvent e) {
    final delivery = _deliveries[e.eventId];
    final readAt = delivery?.readAt;
    if (readAt != null) return 'Read ${_clockLabel(readAt.toLocal())}';
    if (delivery?.deliveredAt != null) return 'Delivered';
    return null;
  }

  Widget _body() {
    final topPad = _noChrome ? 12.0 : ChatHeader.overlap;
    if (_loading) {
      return Padding(
        padding: EdgeInsets.only(top: _noChrome ? 0 : ChatHeader.overlap),
        child: const Center(
          child: Spinner(size: 24),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: EdgeInsets.only(top: _noChrome ? 0 : ChatHeader.overlap),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon('alert-circle', size: 24, color: AppColors.danger),
                const SizedBox(height: 10),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: sans(13, color: AppColors.danger)),
                const SizedBox(height: 14),
                Btn('Retry', small: true, onTap: () => _load(silent: false)),
              ],
            ),
          ),
        ),
      );
    }
    final visible = [
      for (final e in _events)
        if (!isReactionEvent(e) && !_isAck(e)) e
    ];
    if (visible.isEmpty) {
      return PullToRefresh(
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: _noChrome ? 0 : ChatHeader.overlap),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: Center(
                child: EmptyState(
                  icon: 'message',
                  title: 'Chat with ${widget.agentName}',
                  body:
                      'Send a message to discuss tasks or coordinate work directly.',
                ),
              ),
            ),
          ],
        ),
      );
    }
    final byId = {
      for (final e in visible)
        if (e.eventId.isNotEmpty) e.eventId: e
    };
    final cards = Map<CoordinationEvent, Widget>.identity();
    for (final e in visible) {
      if (e.actorKind == 'human') continue;
      final card = agentThreadEventCard(
        e,
        client: widget.client,
        agentId: widget.agentId,
        events: _events,
      );
      if (card != null) cards[e] = card;
    }
    final rawRuns = chatRuns<CoordinationEvent>(
      visible,
      sender: (e) => '${e.actorKind}/${e.actorId}',
      at: _eventTime,
      breaks: cards.containsKey,
    );
    final stamps = List<bool>.filled(visible.length, false);
    final origins = List<bool>.filled(visible.length, false);
    final splitBefore = List<bool>.filled(visible.length, false);
    var lastHumanIdx = -1;
    DateTime? prevAt;
    for (var i = 0; i < visible.length; i++) {
      final ev = visible[i];
      if (ev.actorKind == 'human') lastHumanIdx = i;
      final at = _eventTime(ev);
      final isStamp = at != null &&
          (i == 0 ||
              prevAt == null ||
              !_sameDay(prevAt, at) ||
              at.difference(prevAt).abs() >= const Duration(minutes: 15));
      stamps[i] = isStamp;
      origins[i] = _hasTaskOrigin(ev);
      splitBefore[i] = i == 0 || rawRuns[i].first || isStamp || origins[i];
      if (at != null) prevAt = at;
    }
    final reactionsByTarget = groupMessageReactions(_events);
    return PullToRefresh(
      onRefresh: () => _load(silent: true),
      child: ListenableBuilder(
        listenable: widget.client.presence,
        builder: (_, __) {
          final typing = _typing;
          return ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, topPad, 16, 16),
            itemCount: visible.length + (typing ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == visible.length) {
                return Padding(
                  padding: EdgeInsets.only(top: ChatColors.groupGap),
                  child: _wideCap(_typingRow()),
                );
              }
              final ev = visible[i];
              final first = splitBefore[i];
              final last = i == visible.length - 1 || splitBefore[i + 1];
              final topGap = i == 0
                  ? 0.0
                  : (first ? ChatColors.groupGap : ChatColors.runGap);
              return Padding(
                padding: EdgeInsets.only(top: topGap),
                child: _wideCap(
                  _messageRow(
                    ev,
                    card: cards[ev],
                    byId: byId,
                    reactions: reactionsByTarget[ev.eventId] ?? const [],
                    tail: last,
                    showStamp: stamps[i],
                    showOrigin: origins[i],
                    showDelivery: i == lastHumanIdx,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _typingRow() => ChatBubbleRow(
        key: const Key('agentTypingRow'),
        mine: false,
        child: ChatBubble(
          mine: false,
          tail: true,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: _TypingDots(key: Key('agentTypingDots')),
          ),
        ),
      );

  Widget _bubbleBody(CoordinationEvent e, {required bool mine}) {
    final (pasted, body) = splitPastedBlocks(e.body);
    final transcripts = audioTranscriptItems(body);
    final shown = hideAttachmentMarkers(body);
    final attachments =
        mine ? parseSentAttachments(e.body) : const <SentAttachment>[];
    final images = [
      for (final a in attachments)
        if (a.kind == MediaKind.image) a.path
    ];
    final audio = [
      for (final a in attachments)
        if (a.kind == MediaKind.audio) a.path
    ];
    final files = [
      for (final a in attachments)
        if (a.kind != MediaKind.image && a.kind != MediaKind.audio) a.path
    ];
    final textWidget = shown.isNotEmpty
        ? MarkdownBody(
            data: unwrapCodedLinks(shown),
            selectable: false,
            extensionSet: md.ExtensionSet.gitHubFlavored,
            styleSheet: chatMarkdownStyle(context, mine: mine),
            builders: {'pre': PreBlockBuilder()},
            onTapLink: (txt, href, title) =>
                openMarkdownLink(href, context, txt),
          )
        : null;
    final styledText = textWidget == null
        ? null
        : (kMobile ? textWidget : MessageSelectionArea(child: textWidget));
    final hasExtras = images.isNotEmpty ||
        files.isNotEmpty ||
        audio.isNotEmpty ||
        pasted.isNotEmpty;
    if (!hasExtras) return styledText ?? const SizedBox.shrink();
    final maxWidth =
        (MediaQuery.sizeOf(context).width - 32).clamp(160.0, 280.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty) ...[
          ImageGallery(client: widget.client, paths: images, maxWidth: maxWidth),
          if (styledText != null ||
              files.isNotEmpty ||
              audio.isNotEmpty ||
              pasted.isNotEmpty)
            const SizedBox(height: 6),
        ],
        if (files.isNotEmpty) ...[
          for (var i = 0; i < files.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            FileChip(client: widget.client, path: files[i]),
          ],
          if (styledText != null || audio.isNotEmpty || pasted.isNotEmpty)
            const SizedBox(height: 6),
        ],
        for (var i = 0; i < audio.length; i++) ...[
          VoiceNote(
            client: widget.client,
            path: audio[i],
            ink: mine ? ChatColors.sentText : ChatColors.receivedText,
            transcript: i < transcripts.length
                ? AudioTranscriptCard(items: [transcripts[i]])
                : (transcripts.isEmpty
                    ? Text('Transcribing…', style: chatText(mine: mine))
                    : null),
          ),
          if (styledText != null || pasted.isNotEmpty || i < audio.length - 1)
            const SizedBox(height: 6),
        ],
        if (styledText != null) styledText,
        for (final block in pasted) ...[
          const SizedBox(height: 6),
          PastedTextCard(text: block),
        ],
      ],
    );
  }

  /// iMessage tapback: the reactions ride the bubble's top corner, on the
  /// right of a received bubble and the left of a sent one.
  Widget _withTapback(Widget bubble, Widget? chips, {required bool mine}) {
    if (chips == null) return bubble;
    return Padding(
      padding: const EdgeInsets.only(top: MessageReactionChips.rise),
      child: Stack(clipBehavior: Clip.none, children: [
        bubble,
        Positioned(
          top: -MessageReactionChips.rise,
          left: mine ? -MessageReactionChips.overhang : null,
          right: mine ? null : -MessageReactionChips.overhang,
          child: chips,
        ),
      ]),
    );
  }

  Widget _messageRow(
    CoordinationEvent e, {
    Widget? card,
    Map<String, CoordinationEvent> byId = const {},
    List<ReactionGroup> reactions = const [],
    required bool tail,
    required bool showStamp,
    required bool showOrigin,
    required bool showDelivery,
  }) {
    // The local human is the only `human` actor, so everything else is the peer.
    final mine = e.actorKind == 'human';
    final at = _eventTime(e);
    final answerLine = questionAnswerSystemLine(e);
    if (answerLine != null) {
      return KeyedSubtree(
        key: e.eventId.isEmpty ? null : _keyForEvent(e.eventId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showStamp && at != null)
              ChatSystemLine(_clockLabel(at), bold: _dayLabel(at)),
            ChatSystemLine(answerLine),
          ],
        ),
      );
    }
    final replyToId = e.replyTo;
    final quotedTarget = replyToId == null ? null : byId[replyToId];
    final quotedLine = replyToId == null
        ? null
        : QuotedReplyLine(
            text: quotedTarget != null
                ? quotePreviewText(quotedTarget.body)
                : replyToId,
            mine: mine,
            onTap: quotedTarget != null
                ? () => _scrollToMessage(quotedTarget.eventId)
                : null,
          );
    final chips = reactions.isEmpty
        ? null
        : MessageReactionChips(
            reactions: reactions,
            mine: mine,
            onReact: (name) => unawaited(_sendReaction(e, name)),
          );
    final aboutTask = e.payload['about_task'];
    final delivery = showDelivery ? _deliveryLine(e) : null;
    final rowKey = e.eventId.isEmpty ? null : _keyForEvent(e.eventId);

    final Widget content = MessageBubbleInteractive(
      text: e.body,
      mine: mine,
      onReply: () => _startReply(e),
      onReact: (name) => unawaited(_sendReaction(e, name)),
      focusBuilder: (_) =>
          card ??
          ChatBubble(
            mine: mine,
            tail: tail,
            child: _bubbleBody(e, mine: mine),
          ),
      builder: (_, __, bubbleKey) {
        if (card != null) {
          final keyedCard = KeyedSubtree(key: bubbleKey, child: card);
          final cappedCard = kMobile
              ? ChatBubbleRow(mine: false, child: keyedCard)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: keyedCard,
                  ),
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (quotedLine != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: quotedLine,
                ),
              _withTapback(cappedCard, chips, mine: false),
            ],
          );
        }
        return ChatBubbleRow(
          mine: mine,
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (quotedLine != null)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: 2, left: mine ? 0 : 4, right: mine ? 4 : 0),
                  child: quotedLine,
                ),
              _withTapback(
                KeyedSubtree(
                  key: bubbleKey,
                  child: ChatBubble(
                    mine: mine,
                    tail: tail,
                    child: _bubbleBody(e, mine: mine),
                  ),
                ),
                chips,
                mine: mine,
              ),
            ],
          ),
        );
      },
    );

    return KeyedSubtree(
      key: rowKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showStamp && at != null)
            ChatSystemLine(_clockLabel(at), bold: _dayLabel(at)),
          if (showOrigin)
            ChatSystemLine(
              aboutTask is String && aboutTask.isNotEmpty
                  ? 'from task $aboutTask'
                  : 'from a work session',
              align: Alignment.centerLeft,
            ),
          content,
          if (delivery != null)
            ChatSystemLine(delivery, align: Alignment.centerRight),
        ],
      ),
    );
  }

  Widget _mobileRecorder() {
    final reviewing = !_isRecording && _recordingPath != null;
    final total = _playbackDuration > Duration.zero
        ? _playbackDuration
        : _recordingElapsed;
    final time = reviewing
        ? '${_audioTime(_playbackPosition)} / ${_audioTime(total)}'
        : _audioTime(_recordingElapsed);
    final progress = !reviewing || total.inMilliseconds <= 0
        ? null
        : (_playbackPosition.inMilliseconds / total.inMilliseconds)
            .clamp(0.0, 1.0);
    if (!kMobile) {
      return DesktopRecorderStrip(
        recording: _isRecording,
        time: time,
        wave: LiveRecordingWave(
            buffer: _waveform, live: _isRecording, progress: progress),
        playing: _isPlayingRecording,
        onDiscard: () => unawaited(_discardRecording()),
        onPlay: () => unawaited(_toggleRecordingPlayback()),
        onStop: () => unawaited(_stopRecording()),
        onSend: () => unawaited(_send()),
        onMore: reviewing && _attachments.length < _maxAttachments - 1
            ? () => unawaited(_recordMore())
            : null,
      );
    }
    Widget btn(String icon, String tip, VoidCallback onTap, {Color? color}) =>
        Semantics(
            button: true,
            label: tip,
            child: ComposerIconButton(icon,
                tooltip: tip, onTap: onTap, color: color));
    Widget slot(Widget w) => SizedBox(height: 36, child: Center(child: w));
    return Glass(
      radius: BorderRadius.circular(ComposerCard.radius),
      tint: AppColors.surface1.withValues(alpha: 0.78),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(children: [
          if (reviewing) ...[
            slot(btn('trash', 'Discard', () => unawaited(_discardRecording()))),
            slot(btn(
                _isPlayingRecording ? 'pause' : 'play',
                _isPlayingRecording ? 'Pause' : 'Play',
                () => unawaited(_toggleRecordingPlayback()),
                color: AppColors.fg1)),
          ] else
            slot(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: StatusDot(
                  status: 'running', size: 8, color: AppColors.danger),
            )),
          Expanded(
            child: SizedBox(
              height: 28,
              child: LiveRecordingWave(
                  buffer: _waveform, live: _isRecording, progress: progress),
            ),
          ),
          const SizedBox(width: 10),
          Text(time,
              style: sans(13,
                  tabular: true,
                  color: reviewing ? AppColors.fg3 : AppColors.danger)),
          const SizedBox(width: 6),
          if (_isRecording)
            slot(Semantics(
              button: true,
              label: 'Stop',
              child: ComposerSendButton(
                  enabled: true,
                  stop: true,
                  onTap: () => unawaited(_stopRecording())),
            ))
          else ...[
            if (_attachments.length < _maxAttachments - 1)
              slot(btn('mic', 'Record more', () => unawaited(_recordMore()))),
            const SizedBox(width: 4),
            slot(Semantics(
              button: true,
              label: 'Send voice note',
              child: ComposerSendButton(
                  enabled: !_sending,
                  sending: _sending,
                  onTap: _sending ? null : () => unawaited(_send())),
            )),
          ],
        ]),
      ),
    );
  }

  Widget _attachmentBar() => ComposerAttachmentBar(tiles: [
        for (final a in _attachments)
          ComposerAttachmentTile(
            name: a.name,
            isImage: a.isImage,
            isAudio: a.isAudio,
            uploading: a.uploading,
            localPath: a.localPath,
            onOpen: () => _previewAttachment(a),
            onRemove: () => setState(() => _attachments.remove(a)),
          ),
      ]);

  Future<void> _previewAttachment(_AgentAttachment a) {
    final pairs = {
      for (final x in _attachments)
        PreviewAttachment(
          name: x.name,
          isImage: x.isImage,
          isAudio: x.isAudio,
          localPath: x.localPath,
          imageProvider: x.remotePath == null
              ? null
              : widget.client.imageProvider(x.remotePath!),
        ): x
    };
    return showAttachmentPreview(
      context,
      pairs.keys.toList(),
      _attachments.indexOf(a),
      onRemove: (p) => setState(() => _attachments.remove(pairs[p])),
    );
  }

  Widget _wideCap(Widget child) => kMobile
      ? child
      : Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740),
              child: SizedBox(width: double.infinity, child: child)));

  Widget _composerCard() => ComposerCard(
        text: _input,
        banner: _replyTo == null
            ? null
            : PendingReplyBanner(
                author: _replyTo!.actorKind == 'human'
                    ? 'yourself'
                    : widget.agentName,
                text: quotePreviewText(_replyTo!.body),
                onClear: () => setState(() => _replyTo = null),
              ),
        field: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (!kMobile) _send();
            },
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _send,
          },
          child: TextField(
            controller: _input,
            focusNode: _inputFocus,
            minLines: 1,
            maxLines: 8,
            cursorColor: AppColors.accent,
            onSubmitted: (_) {
              if (!kMobile) _send();
            },
            style: TS.body(AppColors.fg1),
            decoration: ComposerCard.decoration('Message ${widget.agentName}…'),
          ),
        ),
        attach:
            ComposerIconButton('plus', tooltip: 'Attach', onTap: _onAttachTap),
        mic: kCanRecord
            ? ComposerIconButton(_isRecording ? 'mic-off' : 'mic',
                tooltip: 'Record',
                onTap: _onMicTap,
                color: _isRecording ? AppColors.danger : null)
            : null,
        send: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _input,
          builder: (_, val, __) {
            final canSend = (val.text.trim().isNotEmpty ||
                    _attachments.isNotEmpty ||
                    _isRecording ||
                    _recordingPath != null) &&
                !_sending;
            return ComposerSendButton(
              enabled: canSend,
              sending: _sending,
              onTap: canSend ? _send : null,
            );
          },
        ),
      );

  Widget _composer() {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final recording = _isRecording || _recordingPath != null;
    return AnimatedPadding(
      duration: Motion.fast,
      curve: Motion.enter,
      padding: EdgeInsets.only(bottom: keyboard),
      child: LiveCaptionAnchor(
        padding: EdgeInsets.fromLTRB(
          M.gutter,
          8,
          M.gutter,
          10 + (keyboard > 0 ? 8 : mq.padding.bottom),
        ),
        child: Swap(
          stateKey: recording ? 'recorder' : 'composer',
          alignment: Alignment.bottomCenter,
          child: _wideCap(recording
              ? _mobileRecorder()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_attachments.isNotEmpty) _attachmentBar(),
                    _composerCard(),
                  ],
                )),
        ),
      ),
    );
  }
}

/// Open the message sheet for a session, reporting whether anything was sent so
/// the caller can refresh a roster or board.
Future<bool> showAgentWorkSheet(
  BuildContext context, {
  required DaemonClient client,
  required String sessionId,
  String? initialAgentId,
  String? workspaceLabel,
}) async {
  final done = await showAppSheet<bool>(
    context,
    title: 'Message an agent',
    child: AgentWorkSheet(
      client: client,
      sessionId: sessionId,
      initialAgentId: initialAgentId,
      workspaceLabel: workspaceLabel,
    ),
  );
  return done == true;
}

/// Open a direct conversation with one agent.
void openAgentThread(
  BuildContext context, {
  required DaemonClient client,
  required String agentId,
  required String agentName,
}) {
  if (kMobile) {
    Widget page(BuildContext _) => AgentThreadScreen(
          client: client,
          agentId: agentId,
          agentName: agentName,
          onClose: () => Navigator.pop(context),
        );
    Navigator.of(context).push<void>(AppPageRoute<void>(builder: page));
    return;
  }
  presentScreen(
    context,
    style: PanelStyle.drawer,
    purpose: ShellPanelPurpose.conversation,
    panelId: agentId,
    originClient: client,
    maxWidth: 720,
    maxHeight: 720,
    builder: (_, close) => AgentThreadScreen(
      client: client,
      agentId: agentId,
      agentName: agentName,
      onClose: close,
      showBack: false,
    ),
  );
}

class _AgentAttachment {
  final String name;
  final bool isImage;
  final bool isAudio;
  final String? localPath;
  String? remotePath;
  bool uploading;
  _AgentAttachment({
    required this.name,
    required this.isImage,
    required this.isAudio,
    this.localPath,
  }) : uploading = true;
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({super.key});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Typing',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _dot(i, still),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(int i, bool still) {
    final phase = still ? 0.5 : (_c.value + i / 3) % 1;
    final pulse = phase < 0.5 ? phase * 2 : 2 - phase * 2;
    return Transform.translate(
      offset: Offset(0, still ? 0 : -2 * pulse),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ChatColors.meta
              .withValues(alpha: still ? 0.8 : 0.35 + 0.65 * pulse),
        ),
      ),
    );
  }
}
