import 'package:snippet/ambient/hold.dart';
import 'package:snippet/ambient/live_caption.dart';
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../api.dart';
import '../composer/attachment_preview.dart';
import '../composer/attachment_tile.dart';
import '../composer/composer_card.dart';
import '../composer_strip.dart';
import '../media_views.dart';
import '../motion.dart';
import '../desktop_pick.dart';
import '../models.dart';
import '../panel.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../swr.dart';
import '../pull_refresh.dart';
import 'agent_records.dart';
import 'agent_view_switcher.dart';
import 'mobile_chrome.dart';
import '../mochi.dart';

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
    this.showBack = true,
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

  final bool showBack;

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

  void _loadLine() {
    widget.client.coordinationAgents().then((all) {
      final a = all.where((x) => x.id == widget.agentId).firstOrNull;
      if (a == null || !mounted) return;
      final line = [
        if (!a.available) 'Paused',
        if (a.profile != null) a.profile!,
      ].join(' \u00b7 ');
      setState(() {
        _fetchedLine = line;
        _fetchedPaused = !a.available;
        _fetchedProfile = a.profile;
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

  Widget _switcher() => AgentViewSwitcher(
      value: _view, unread: _unread, onChanged: _setView);

  Widget _viewBody() {
    final child = switch (_view) {
      AgentView.thread => KeyedSubtree(
          key: const ValueKey(AgentView.thread), child: _body()),
      _ => KeyedSubtree(
          key: ValueKey(_view),
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

  /// The phone title menu: the views, the open view's filters, and the rest
  /// of the agent behind More actions.
  Future<void> _openViewMenu() async {
    final picked = await showAppMenu<String>(
      context,
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
  final _scroll = ScrollController();
  List<CoordinationEvent> _events = const [];
  bool _agentBusy = false;
  Timer? _busyCap;
  static const _busyMax = Duration(minutes: 10);
  bool _loading = true;
  final bool _sending = false;
  String? _error;
  late final Swr<List<CoordinationEvent>> _thread;

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
    _thread = Swr<List<CoordinationEvent>>(
      client: widget.client,
      key: 'agent-thread:${widget.agentId}',
      fetch: () => widget.client.agentThread(peerId: widget.agentId),
      revalidateOn: Swr.coordination,
      onChange: _sync,
    );
    _events = _thread.data ?? const [];
    _updateBusy();
    _loading = _thread.data == null;
    if (_events.isNotEmpty) _jumpToBottom();
  }

  @override
  void dispose() {
    _busyCap?.cancel();
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
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) => _thread.refresh();

  // Sent but not yet in a fetched list; merged back so a refetch can't hide them.
  final List<CoordinationEvent> _unechoed = [];

  static bool _isAck(CoordinationEvent e) => e.payload['auto'] == 'ack';

  void _updateBusy() {
    _busyCap?.cancel();
    _busyCap = null;
    CoordinationEvent? last;
    for (final e in _events.reversed) {
      if (!_isAck(e)) {
        last = e;
        break;
      }
    }
    if (last == null || last.actorKind != 'human') {
      _agentBusy = false;
      return;
    }
    final sent = DateTime.tryParse(last.createdAt)?.toLocal() ?? DateTime.now();
    final left = _busyMax - DateTime.now().difference(sent);
    if (left <= Duration.zero) {
      _agentBusy = false;
      return;
    }
    _agentBusy = true;
    _busyCap = Timer(left, () {
      if (mounted) setState(() => _agentBusy = false);
    });
  }

  void _sync() {
    if (!mounted) return;
    final next = _thread.data;
    if (next != null) {
      final keys = {for (final e in next) e.idempotencyKey};
      final bodies = {
        for (final e in next)
          if (e.actorKind == 'human') e.payload['body']
      };
      _unechoed.removeWhere((p) =>
          keys.contains(p.idempotencyKey) || bodies.contains(p.payload['body']));
    }
    final merged = next == null ? null : [...next, ..._unechoed];
    final hadNew = merged != null && merged.length > _events.length;
    final first = _events.isEmpty;
    setState(() {
      if (merged != null) _events = merged;
      _updateBusy();
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
    final key = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final pending = CoordinationEvent.fromJson({
      'event_id': key,
      'event_type': 'direct_message.sent',
      'actor_kind': 'human',
      'actor_id': 'local',
      'payload': {'body': body},
      'idempotency_key': key,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    _input.clear();
    _attachmentGeneration++;
    _attachments.clear();
    _discardRecording();
    _unechoed.add(pending);
    setState(() => _events = [..._events, pending]);
    _jumpToBottom(animated: true);
    try {
      await widget.client.sendAgentMessage(
        toAgentId: widget.agentId,
        body: body,
        idempotencyKey: key,
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
      if (_input.text.isEmpty) _input.text = typed;
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wrapped in Material because presentScreen's non-rounded frames are plain
    // Containers — no Material ancestor — while a TextField and the icon buttons
    // here require one.
    final hideChrome = widget.embedded;
    return Material(
      color: readingBg,
      child: SafeArea(
        top: !hideChrome,
        bottom: false,
        child: Column(
          children: [
            if (!hideChrome) _header(),
            Expanded(child: _viewBody()),
            if (_view == AgentView.thread) _composer(),
          ],
        ),
      ),
    );
  }

  Widget _desktopStatusLine(String subtitle) {
    final logo = widget.subtitle == null && _profileProvider != null;
    if (!logo) {
      return Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TS.meta(AppColors.fg3));
    }
    return Row(children: [
      if (_fetchedPaused)
        Flexible(
          child: Text('Paused \u00b7 ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TS.meta(AppColors.fg3)),
        ),
      Tooltip(
          message: _fetchedProfile ?? '',
          child: ProviderLogo(_profileProvider, size: 13)),
    ]);
  }

  Widget _header() {
    final subtitle = (widget.subtitle ?? _fetchedLine ?? '').trim();
    if (kMobile) {
      // Back is the system gesture (iOS gets it from the Cupertino route).
      return MobileStackedTitleBar(
        title: widget.agentName,
        subtitle: _viewLine,
        onTap: _openViewMenu,
        tapHint: 'Switch view',
      );
    }
    final canGoBack = !widget.embedded &&
        widget.showBack &&
        (widget.onClose != null || Navigator.of(context).canPop());
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (canGoBack)
            IconBtn(
              'chevron-left',
              size: 28,
              iconSize: 16,
              tooltip: 'Back',
              onTap: _closePage,
            ),
          const SizedBox(width: 4),
          AgentMochi(widget.agentId, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.agentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.rowTitle(AppColors.fg1)),
                if (subtitle.isNotEmpty) _desktopStatusLine(subtitle),
              ],
            ),
          ),
          _switcher(),
          if (!widget.embedded && widget.onClose != null)
            IconBtn(
              'x',
              size: 28,
              iconSize: 16,
              tooltip: 'Close',
              onTap: widget.onClose!,
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: Spinner(size: 24),
      );
    }
    if (_error != null) {
      return Center(
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
      );
    }
    if (_events.isEmpty) {
      return PullToRefresh(
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
    return PullToRefresh(
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _events.length + (_agentBusy ? 1 : 0),
        itemBuilder: (_, i) => _wideCap(
            i == _events.length ? _workingRow() : _bubble(_events[i])),
      ),
    );
  }

  Widget _workingRow() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: AppColors.fg3),
            ),
            const SizedBox(width: 8),
            Text('Working...', style: sans(12, color: AppColors.fg3)),
          ],
        ),
      );

  Widget _bubble(CoordinationEvent e) {
    if (_isAck(e)) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text(e.body, style: sans(12, color: AppColors.fg3)),
      );
    }
    // The local human is the only `human` actor, so everything else is the peer.
    final mine = e.actorKind == 'human';
    if (mine) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Bubble(mine: true, text: e.body, client: widget.client),
      );
    }
    final origin = e.payload['origin_session'];
    final aboutTask = e.payload['about_task'];
    final fromTask = origin is String &&
        origin.isNotEmpty &&
        origin != 'inbox-${widget.agentId}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fromTask)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                  aboutTask is String && aboutTask.isNotEmpty
                      ? 'from task $aboutTask'
                      : 'from a work session',
                  style: sans(12, color: AppColors.fg3)),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AgentMochi(widget.agentId, size: 15),
                const SizedBox(width: 5),
                Text(
                  widget.agentName,
                  style: sans(11, weight: W.label, color: AppColors.accent),
                ),
              ],
            ),
          ),
          Bubble(mine: false, text: e.body),
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
    Widget roundBtn(String icon, String tip, VoidCallback onTap,
            {Color? fill, Color? ink}) =>
        Tooltip(
          message: tip,
          child: Material(
            color: fill ?? AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: SizedBox.square(
                dimension: 46,
                child: Center(
                    child:
                        AppIcon(icon, size: 19, color: ink ?? AppColors.fg1)),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        if (reviewing) ...[
          roundBtn('trash', 'Discard', () => unawaited(_discardRecording()),
              ink: AppColors.fg3),
          const SizedBox(width: 10),
          roundBtn(
              _isPlayingRecording ? 'pause' : 'play',
              _isPlayingRecording ? 'Pause' : 'Play',
              () => unawaited(_toggleRecordingPlayback())),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (!reviewing) ...[
                  StatusDot(
                      status: 'running', size: 8, color: AppColors.danger),
                  const SizedBox(width: 6),
                ],
                Text(reviewing ? 'Voice note' : 'Recording',
                    style: sans(13, color: AppColors.fg2)),
                const Spacer(),
                Text(time,
                    style: sans(13,
                        tabular: true,
                        color: reviewing ? AppColors.fg3 : AppColors.danger)),
              ]),
              const SizedBox(height: 6),
              SizedBox(
                height: 30,
                width: double.infinity,
                child: LiveRecordingWave(
                    buffer: _waveform, live: _isRecording, progress: progress),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (_isRecording)
          roundBtn('stop', 'Stop', () => unawaited(_stopRecording()),
              fill: AppColors.surface3)
        else ...[
          if (_attachments.length < _maxAttachments - 1) ...[
            roundBtn('mic', 'Record more', () => unawaited(_recordMore())),
            const SizedBox(width: 10),
          ],
          roundBtn('arrow-up', 'Send voice note', () => unawaited(_send()),
              fill: AppColors.accentFill, ink: AppColors.accentFg),
        ],
      ]),
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
          kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
          8,
          kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
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
    Navigator.of(context).push<void>(
        defaultTargetPlatform == TargetPlatform.iOS
            ? CupertinoPageRoute(builder: page)
            : MaterialPageRoute(builder: page));
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
