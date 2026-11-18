part of 'session.dart';

const double kDesktopComposerWidth = 960;

extension _SessionScreenComposerExt on _SessionScreenState {
  void _send(Map<String, dynamic> m, {bool tracked = false}) {
    final kind = m['kind'];
    if (kind == 'user_message' ||
        kind == 'queue' ||
        kind == 'steer_queued' ||
        kind == 'interrupt') {
      unawaited(
          AmbientController.instance.voice.value?.stopNow() ?? Future.value());
    }
    if (kind == 'user_message' && _settled) _setState(() => _settled = false);
    final payload = jsonEncode(m);
    final ch = _channel;
    if (ch == null) {
      if (!tracked) _outbox.add(payload); // untracked messages use outbox
      _ensureConnected();
      return;
    }
    try {
      ch.sink.add(payload);
    } catch (_) {
      if (!tracked) _outbox.add(payload);
      _scheduleReconnect(ch);
    }
  }

  /// [steer] sends into the running turn now instead of queueing after it.
  Future<void> _sendMessage({bool steer = false}) async {
    // The composer can be triggered by both the send button and keyboard submit;
    // serialize the entire async path so a rapid double tap cannot create two
    // distinct nonces and two server turns.
    if (_sendingMessage) return;
    _sendingMessage = true;
    try {
      await _sendMessageOnce(steer: steer);
    } finally {
      _sendingMessage = false;
    }
  }

  Future<void> _sendMessageOnce({bool steer = false}) async {
    // Audio can be sent directly from the composer: stop the live take, upload
    // it through the normal attachment path, then continue with the same send.
    if (_sendingAudio) return;
    if (_isRecording || _recordingPath != null) {
      _sendingAudio = true;
      Diag.crumb('send audio tapped');
      if (mounted) _setState(() {});
      try {
        if (_isRecording) await _stopRecording();
        if (_recordingPath != null && !await _confirmRecording()) return;
      } finally {
        _sendingAudio = false;
        if (mounted) _setState(() {});
      }
    }
    // An upload still in flight would be silently DROPPED (only remotePath'd
    // attachments ship, then the list is cleared). The send button disables via
    // canSend, but keyboard submit bypassed it — guard here, the single choke point.
    if (_anyUploading) return;
    final t = _input.text.trim();
    final ready = _attachments.where((a) => a.ready).toList();
    if (t.isEmpty && ready.isEmpty) return;

    // A selected recipient turns this into a DIRECT MESSAGE to that agent: it
    // goes to the agent's own inbox and never becomes a turn in this session, so
    // the conversation and the work stay separate.
    final recipient = _recipientAgentId;
    if (recipient != null && recipient.isNotEmpty) {
      _sendDirectMessage(recipient, t, ready);
      return;
    }

    final running = _state?.status == 'running';
    if (!running && !await _resolveCold()) return;
    // Reference each upload by its exact path so the agent reads it this turn.
    final markers = ready.map((a) => a.marker).join('\n');
    final msg = markers.isEmpty ? t : (t.isEmpty ? markers : '$t\n\n$markers');
    final nonce = _nextNonce();
    _setState(() {
      if (running && steer) {
        // Steer rides the queue: hold it, then pull it into the turn at once.
        final item = QueuedInput(id: _nextNonce(), text: msg);
        _queueHidden.add(item.id);
        _send({'kind': 'queue', 'value': item, 'nonce': nonce});
        final steerNonce = _nextNonce();
        _trackPending(msg, steerNonce);
        _send({'kind': 'steer_queued', 'value': item.id, 'nonce': steerNonce});
      } else if (running) {
        // Hold on the daemon so TUI/app/desktop all see the same queue.
        final item = QueuedInput(id: _nextNonce(), text: msg);
        _optimisticQueuedBase[item.id] =
            _userEchoCount(_state?.events ?? const []);
        _optimisticQueuedNonce[item.id] = nonce;
        _optimisticQueued.add(item);
        _send({'kind': 'queue', 'value': item, 'nonce': nonce});
      } else {
        _send({'kind': 'user_message', 'value': msg, 'nonce': nonce},
            tracked: true);
        _trackPending(msg, nonce); // faint bubble until daemon echoes it
      }
      _attachments.clear();
    });
    if (!running) widget.onMacStatus?.call(_state, true);
    _input.clear();
    _armAckWatchdog(); // recover if this send silently dies on a dead socket
    // Sending is an explicit action — re-pin and jump to the bottom.
    _stickToBottom = true;
    _scheduleBottom();
  }

  /// A cold session in 'ask' mode needs a resume choice before its next turn;
  /// 'lean'/'full' let the daemon resume, so the send only waits on the check.
  Future<bool> _resolveCold() async {
    if (_cold != null) {
      if (_resumeMode == 'ask') {
        toast(context, 'Choose Lean or Full first.');
        return false;
      }
      return true;
    }
    final seen = _warmSeenAt;
    if (seen != null && DateTime.now().difference(seen).inSeconds < 240) {
      return true;
    }
    await _checkCold();
    if (!mounted) return false;
    if (_resumeMode != 'ask') return true;
    if (_cold != null) {
      toast(context, 'Choose Lean or Full first.');
      return false;
    }
    return true;
  }

  /// Send the composer's text to a selected agent as a direct message.
  ///
  /// Deliberately separate from the session send path: a direct message goes to
  /// the agent's own inbox and must NOT become a turn in this session's
  /// transcript, so nothing here touches the socket. The recipient is cleared
  /// afterwards because the message will not appear in this transcript — leaving
  /// the composer targeted would invite sending the next thought to the wrong
  /// place.
  Future<void> _sendDirectMessage(
    String agentId,
    String text,
    List<_Attachment> ready,
  ) async {
    if (text.isEmpty && ready.isEmpty) return;
    final markers = ready.map((a) => a.marker).join('\n');
    final body =
        markers.isEmpty ? text : (text.isEmpty ? markers : '$text\n\n$markers');
    final name = _recipientAgentName ?? agentId;
    _setState(() {
      _recipientAgentId = null;
      _recipientAgentName = null;
      _attachments.clear();
    });
    _input.clear();
    try {
      await widget.client.sendAgentMessage(
        toAgentId: agentId,
        body: body,
        idempotencyKey: _nextNonce(),
        // Ask FROM this session, so the agent's reply comes back here rather
        // than only into its own inbox. Without it the exchange is one-way from
        // the session's point of view: nothing here records what was asked.
        originSession: widget.sessionId,
      );
      // No optimistic row here: the daemon records the sent message as an
      // `agent_message` event in THIS session, which now renders in the
      // transcript. A local row on top of that would show the same send twice.
      _toast('Sent to $name');
    } catch (e) {
      // Put the text back: a failed send must not cost the user what they wrote.
      _input.text = body;
      _toast('$e');
    }
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

  // `+` tapped: desktop opens a file picker directly; mobile shows a small
  Future<void> _confirmCompact() async {
    if (_state?.compacting == true) {
      _toast('Already compacting');
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Compact history?',
      body:
          'Older conversation history will be summarized into a context table. Recent messages stay. This cannot be undone.',
      confirmLabel: 'Compact',
      danger: false,
    );
    if (!ok || !mounted) return;
    _compactNow();
  }

  void _compactNow() {
    if (_state?.compacting == true) {
      _toast('Already compacting');
      return;
    }
    _send({'kind': 'compact'});
    _toast('Compacting history');
  }

  List<QueuedInput> get _heldQueue {
    final live = _state?.queuedInputs ?? const <QueuedInput>[];
    final extra = <QueuedInput>[];
    for (final item in _optimisticQueued) {
      if (!live.any((liveItem) => liveItem.id == item.id)) extra.add(item);
    }
    final all = extra.isEmpty ? live : [...live, ...extra];
    return _queueHidden.isEmpty
        ? all
        : all.where((item) => !_queueHidden.contains(item.id)).toList();
  }

  void _syncOptimisticQueue(List<QueuedInput> live) {
    _optimisticQueued.removeWhere((item) {
      final seen = live.any((liveItem) => liveItem.id == item.id);
      if (seen) {
        _optimisticQueuedBase.remove(item.id);
        _optimisticQueuedNonce.remove(item.id);
      }
      return seen;
    });
  }

  void _hideQueuedAt(int visible) {
    final held = _heldQueue;
    if (visible >= 0 && visible < held.length) {
      _queueHidden.add(held[visible].id);
    }
  }

  void _cancelQueuedAt(int visible) {
    if (visible < 0 || visible >= _heldQueue.length) return;
    final item = _heldQueue[visible];
    _setState(() => _hideQueuedAt(visible));
    _send({'kind': 'unqueue', 'value': item.id, 'nonce': _nextNonce()});
  }

  void _editQueuedAt(int visible) {
    if (visible < 0 || visible >= _heldQueue.length) return;
    final item = _heldQueue[visible];
    final cleanText = _queuedText(item.text);
    _input.text = cleanText;
    _input.selection = TextSelection.collapsed(offset: cleanText.length);
    _cancelQueuedAt(visible);
    _inputFocus.requestFocus();
  }

  void _steerAllQueued() {
    final items = List<QueuedInput>.from(_heldQueue);
    for (final item in items) {
      final nonce = _nextNonce();
      _setState(() {
        _queueHidden.add(item.id);
        _optimisticQueued.removeWhere((queued) => queued.id == item.id);
        _trackPending(item.text, nonce);
      });
      _send({'kind': 'steer_queued', 'value': item.id, 'nonce': nonce});
    }
    if (items.isNotEmpty) _armAckWatchdog();
  }

  void _cancelAllQueued() {
    _setState(() => _queueHidden.addAll(_heldQueue.map((item) => item.id)));
    _send({'kind': 'drop_queued'});
  }

  void _steerQueuedAt(int visible) {
    final held = _heldQueue;
    if (visible < 0 || visible >= held.length) return;
    final item = held[visible];
    final nonce = _nextNonce();
    _setState(() {
      _queueHidden.add(item.id);
      _optimisticQueued.removeWhere((queued) => queued.id == item.id);
      _trackPending(item.text, nonce);
    });
    _send({'kind': 'steer_queued', 'value': item.id, 'nonce': nonce});
    _armAckWatchdog();
  }

  void _interruptAndSendQueuedAt(int visible) {
    final held = _heldQueue;
    if (visible < 0 || visible >= held.length) return;
    _send({'kind': 'interrupt'});
    _steerQueuedAt(visible);
  }

  Widget _queuedCard() {
    final queue = _heldQueue;
    if (queue.isEmpty) return const SizedBox.shrink();
    if (!kMobile) {
      return DeskQueueCard(
        entries: [
          for (var i = 0; i < queue.length; i++)
            () {
              final e = _queuedEntry(i, queue[i]);
              return DeskQueueEntry(
                label: e.label,
                muted: e.muted,
                lead: e.lead,
                extra: e.extra,
                onSendNow: () => _interruptAndSendQueuedAt(i),
                onEdit: () => _editQueuedAt(i),
                onRemove: () => _cancelQueuedAt(i),
              );
            }(),
        ],
        onClear: _cancelAllQueued,
        onSendAll: _steerAllQueued,
      );
    }
    return ComposerQueueList(
      entries: [
        for (var i = 0; i < queue.length; i++) _queuedEntry(i, queue[i]),
      ],
      onClear: _cancelAllQueued,
      onSendAll: _steerAllQueued,
    );
  }

  ComposerQueueEntry _queuedEntry(int qi, QueuedInput item) {
    final text = _queuedText(item.text);
    final counts = _queuedAttachCounts(item.text);
    final images = _queuedImagePaths(item.text);
    final others = counts.$1 + counts.$3;
    final envelope = queuedEnvelopeLabel(text);
    final label = envelope ??
        (text.isNotEmpty
            ? text.replaceAll('\n', ' ')
            : images.isNotEmpty
                ? (images.length == 1 ? 'Image' : '${images.length} images')
                : 'Attachment');
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget thumb(String path) => Container(
          width: 28,
          height: 28,
          margin: EdgeInsets.only(right: S.s4),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.of(6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image(
            image: ResizeImage(widget.client.imageProvider(path),
                width: (28 * dpr).round()),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                Center(child: AppIcon('image', size: 13, color: AppColors.fg4)),
          ),
        );
    return ComposerQueueEntry(
      label: label,
      muted: text.isEmpty,
      lead: images.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              for (final path in images.take(3)) thumb(path),
              if (images.length > 3)
                Text('+${images.length - 3}',
                    style: sans(12, tabular: true, color: AppColors.fg4)),
            ]),
      extra: others > 0
          ? AttachmentPill(audio: counts.$1, images: 0, files: counts.$3)
          : null,
      onSend: () => _steerQueuedAt(qi),
      onMore: (anchor) => _queuedMore(qi, anchor),
    );
  }

  Future<void> _queuedMore(int qi, BuildContext anchor) async {
    final running = _state?.status == 'running';
    final pick = await showAppMenu<String>(
      context,
      anchor: anchor,
      alignEnd: true,
      items: [
        appMenuItem(value: 'edit', icon: 'edit', label: 'Edit'),
        if (running)
          appMenuItem(
              value: 'interrupt', icon: 'stop', label: 'Interrupt and send'),
        appMenuItem(value: 'remove', icon: 'x', label: 'Remove', danger: true),
      ],
    );
    if (!mounted) return;
    switch (pick) {
      case 'edit':
        _editQueuedAt(qi);
      case 'interrupt':
        _interruptAndSendQueuedAt(qi);
      case 'remove':
        _cancelQueuedAt(qi);
    }
  }

  // Clean text for a held/pending message (markers stripped). Attachments
  // surface as AttachmentPill beside the text — same as a real Bubble.
  String _queuedText(String m) => hideAttachmentMarkers(m);

  // The marker reads "— call view_image on this exact path to see it: <path>".
  List<String> _queuedImagePaths(String m) => [
        for (final x in RegExp(r'\[attached image —([^\]]*)\]').allMatches(m))
          if (_markerPath(x.group(1) ?? '') case final p when p.isNotEmpty) p
      ];

  String _markerPath(String body) {
    final i = body.lastIndexOf(': ');
    return (i < 0 ? body : body.substring(i + 2)).trim();
  }

  (int audio, int images, int files) _queuedAttachCounts(String m) {
    final matches =
        RegExp(r'\[attached (image|file) —([^\]]*)\]').allMatches(m);
    final audio =
        matches.where((x) => isAudioAttachmentPath(x.group(2) ?? '')).length;
    final images = matches.where((x) => x.group(1) == 'image').length;
    return (audio, images, matches.length - images - audio);
  }

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  bool get _canSend =>
      (_isRecording ||
          _recordingPath != null ||
          _input.text.trim().isNotEmpty ||
          _attachments.any((a) => a.ready)) &&
      !_anyUploading &&
      !_sendingAudio;

  bool get _dropsOn =>
      widget.acceptDrops || (mounted && TickerMode.valuesOf(context).enabled);

  Future<void> _ingestDroppedFiles(DropDoneDetails details) async {
    if (!kMacOS || !_dropsOn) return;
    _setState(() => _draggingFiles = false);
    final files = details.files.whereType<DropItemFile>().map((item) {
      final bookmark = item.extraAppleBookmark;
      return (
        name: item.name,
        localPath: item.path,
        readBytes: () async {
          var accessed = false;
          try {
            if (bookmark != null && bookmark.isNotEmpty) {
              accessed = await DesktopDrop.instance
                  .startAccessingSecurityScopedResource(bookmark: bookmark);
            }
            return await item.readAsBytes();
          } finally {
            if (accessed) {
              await DesktopDrop.instance
                  .stopAccessingSecurityScopedResource(bookmark: bookmark!);
            }
          }
        },
      );
    }).toList();
    await _ingest(files);
  }

  /// One composer footer control: icon + label + disclosure chevron.
  /// A composer chip. When [onClear] is set the chip is in a CHOSEN state: it
  /// shows the value, and the trailing affordance clears it instead of opening
  /// the picker — so a selected dispatch is dismissible without a second trip
  /// through the menu.
  Widget _composerChip({
    required String icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onClear,
    bool selected = false,
    bool compact = false,
  }) =>
      ComposerChip(
          compact: compact,
          icon: icon,
          label: label,
          onTap: onTap,
          onClear: onClear,
          selected: selected);

  /// Pick (or clear) the direct-message recipient for the composer.
  Future<void> _pickRecipient(BuildContext anchor) async {
    final current = _recipientAgentId;
    final picked = await pickAgentId(
      context,
      widget.client,
      title: 'Send to',
      // An agent already on this session is not offered again: it is reached by
      // messaging the session itself, so listing it twice would be ambiguous.
      exclude: _sessionAgentIds,
      currentAgentId: current,
      anchor: anchor,
      verticalAnchor: _composerCardKey.currentContext,
    );
    if (picked == null || !mounted) return;
    _setState(() {
      _recipientAgentId = picked.id;
      _recipientAgentName =
          picked.displayName.trim().isEmpty ? picked.id : picked.displayName;
    });
    // Pin it to the session so the composer shows WHO can be reached without
    // walking the directory again next time.
    _pinSessionAgent(picked.id);
    _toast('Sending to $_recipientAgentName');
  }

  void _clearRecipient() {
    _setState(() {
      _recipientAgentId = null;
      _recipientAgentName = null;
    });
    _toast('Back to this chat');
  }

  /// Record that `agentId` belongs to this session's roster.
  ///
  /// Session membership is tracked locally for now: choosing an agent here is
  /// what puts it on this session, and the set is what stops the picker
  /// offering the same agent twice.
  void _pinSessionAgent(String agentId) {
    if (agentId.isEmpty) return;
    _setState(() => _sessionAgentIds.add(agentId));
  }

  /// The composer's status line: where this session runs, and how much context
  /// is left. Sits under the card so the transcript keeps the full width.
  Widget _goalBanner() => Container(
        margin: EdgeInsets.only(bottom: S.of(10)),
        padding: EdgeInsets.fromLTRB(S.of(10), kMobile ? S.s4 : S.s8,
            kMobile ? S.s4 : S.s8, kMobile ? S.s4 : S.s8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(children: [
          AppIcon('goal', size: 14, color: AppColors.accent),
          SizedBox(width: S.s8),
          Expanded(
            child: Text(plainInline(_state!.goal!.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, color: AppColors.fg2)),
          ),
          Text(_state!.goal!.paused ? 'paused' : 'active',
              style: mono(10, color: AppColors.accent)),
          SizedBox(width: S.of(5)),
          kMobile
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _cancelGoal,
                  child: SizedBox(
                      width: 32,
                      height: 28,
                      child: Center(
                          child: AppIcon('x', size: 14, color: AppColors.fg3))))
              : IconBtn('x',
                  size: 26,
                  iconSize: 13,
                  tooltip: 'Cancel goal',
                  onTap: _cancelGoal),
        ]),
      );

  Map<ShortcutActivator, VoidCallback> get _composerShortcuts => {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_mentionMatches.isNotEmpty) {
            _applyMention(_mentionMatches[_mentionIndex]);
          } else if (!kMobile && _canSend) {
            _sendMessage();
          }
        },
        if (_mentionMatches.isNotEmpty) ...{
          const SingleActivator(LogicalKeyboardKey.tab): () =>
              _applyMention(_mentionMatches[_mentionIndex]),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _setState(
              () =>
                  _mentionIndex = (_mentionIndex + 1) % _mentionMatches.length),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _setState(
              () => _mentionIndex =
                  (_mentionIndex - 1 + _mentionMatches.length) %
                      _mentionMatches.length),
        },
        if (_mentionQuery != null)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _setState(() => _mentionQuery = null),
        if (!kMobile)
          SingleActivator(LogicalKeyboardKey.keyV,
              meta: kMacOS, control: !kMacOS): _pasteFromShortcut,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
          if (_canSend) _sendMessage();
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (_canSend) _sendMessage();
        },
      };

  Widget? _recipientChip() {
    if (_isMissionControl || _recipientAgentId == null) return null;
    if (!kMobile) {
      return Builder(
        builder: (ctx) => DeskRecipientChip(
          leading: AgentMochi(_recipientAgentId!, size: 14),
          label: 'Send to ${_recipientAgentName ?? _recipientAgentId!}',
          onTap: () => _pickRecipient(ctx),
          onClear: _clearRecipient,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: S.s4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Builder(
          builder: (ctx) => _composerChip(
            icon: 'agent',
            label: _recipientAgentName ?? _recipientAgentId!,
            selected: true,
            onTap: () => _pickRecipient(ctx),
            onClear: _clearRecipient,
          ),
        ),
      ),
    );
  }

  Widget _modelChip(bool compact) => Builder(
      builder: (chipCtx) => _composerChip(
            icon: _modelProvider == null ? 'cpu' : 'provider:$_modelProvider',
            label: _modelLabel ?? 'Auto',
            compact: compact,
            onTap: () => _switchModel(chipCtx),
          ));

  void _trackMention() {
    if (_isMissionControl) return;
    final v = _input.value;
    final sel = v.selection;
    String? query;
    if (sel.isValid && sel.isCollapsed && sel.baseOffset <= v.text.length) {
      query = RegExp(r'(?:^|\s)@([\w.\-]*)$')
          .firstMatch(v.text.substring(0, sel.baseOffset))
          ?.group(1);
    }
    if (query == _mentionQuery) return;
    _setState(() {
      _mentionQuery = query;
      _mentionIndex = 0;
    });
    if (query != null && _mentionAgents == null && !_mentionLoading) {
      _loadMentionAgents();
    }
  }

  Future<void> _loadMentionAgents() async {
    _mentionLoading = true;
    try {
      final agents = (await widget.client.coordinationAgents())
          .where((a) => !a.isMissionControl)
          .toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      if (mounted) _setState(() => _mentionAgents = agents);
    } catch (_) {
    } finally {
      _mentionLoading = false;
      if (mounted) _setState(() {});
    }
  }

  List<CoordinationAgent> get _mentionMatches {
    final q = _mentionQuery?.toLowerCase();
    if (q == null || _isMissionControl) return const [];
    return (_mentionAgents ?? const <CoordinationAgent>[])
        .where((a) =>
            a.displayName.toLowerCase().contains(q) ||
            a.handle.toLowerCase().contains(q) ||
            a.id.toLowerCase().contains(q))
        .take(6)
        .toList();
  }

  void _applyMention(CoordinationAgent agent) {
    final v = _input.value;
    final cut = v.selection.baseOffset.clamp(0, v.text.length);
    final m = RegExp(r'@([\w.\-]*)$').firstMatch(v.text.substring(0, cut));
    final start = m?.start ?? cut;
    _input.value = TextEditingValue(
      text: v.text.replaceRange(start, cut, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    _setState(() {
      _mentionQuery = null;
      _recipientAgentId = agent.id;
      _recipientAgentName =
          agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    });
    _pinSessionAgent(agent.id);
    _inputFocus.requestFocus();
  }

  Widget _mentionList() {
    final matches = _mentionMatches;
    final loading = _mentionAgents == null && _mentionLoading;
    return Container(
      margin: EdgeInsets.only(bottom: S.s6),
      padding: EdgeInsets.all(S.s4),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: matches.isEmpty
          ? Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.of(9)),
              child: Text(
                  loading
                      ? 'Loading agents…'
                      : _mentionAgents == null
                          ? 'Could not load agents'
                          : 'No agent matches @${_mentionQuery ?? ''}',
                  style: sans(13, color: AppColors.fg4)),
            )
          : Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < matches.length; i++)
                Material(
                  color: i == _mentionIndex && !kMobile
                      ? AppColors.surface2
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(R.md),
                    onTap: () => _applyMention(matches[i]),
                    child: Container(
                      height: kMobile ? 44 : 34,
                      padding: EdgeInsets.symmetric(horizontal: S.of(10)),
                      child: Row(children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: matches[i].status == 'disabled'
                                ? AppColors.fg4
                                : AppColors.ok,
                          ),
                        ),
                        SizedBox(width: S.of(10)),
                        Flexible(
                          child: Text(
                              matches[i].displayName.trim().isEmpty
                                  ? matches[i].id
                                  : matches[i].displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(13, color: AppColors.fg1)),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
    );
  }

  Widget _composerCard(bool running) {
    var agent = (_meAgentName ?? '').trim();
    // A desk session belongs to its agent; never address it as "Snippet".
    if (agent.isEmpty && _inboxAgentId(widget.sessionId) != null) {
      agent = widget.title.trim();
    }
    final hint = _isMissionControl
        ? 'Ask Mission Control…'
        : (agent.isEmpty ? 'Reply to Snippet' : 'Message $agent');
    if (!kMobile) return _deskComposerCard(running, hint);
    return KeyedSubtree(
      key: _composerCardKey,
      child: ComposerCard(
        highlight: _draggingFiles,
        text: _input,
        banner: _state?.goal?.ongoing == true || _recipientChip() != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_state?.goal?.ongoing == true) _goalBanner(),
                  if (_recipientChip() != null) _recipientChip()!,
                ],
              )
            : null,
        field: CallbackShortcuts(
          bindings: _composerShortcuts,
          child: TextField(
            key: _inputFieldKey,
            controller: _input,
            focusNode: _inputFocus,
            contentInsertionConfiguration: _keyboardContent,
            minLines: 1,
            maxLines: 8,
            cursorColor: AppColors.accent,
            onSubmitted: (_) => _sendMessage(),
            style: ComposerCard.fieldStyle,
            decoration:
                ComposerCard.decoration(hint, style: ComposerCard.fieldStyle),
          ),
        ),
        attach: _composerPlus(),
        // The phone tray carries the model; the desktop pill keeps it inline.
        trailing: !(kMobile && _showsQuickActions) &&
                _inboxAgentId(widget.sessionId) == null
            ? _modelChip
            : null,
        send: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _input,
          builder: (_, __, ___) => _composerAction(running),
        ),
      ),
    );
  }

  Widget _deskComposerCard(bool running, String hint) {
    final goal = _state?.goal?.ongoing == true;
    final rcpt = _recipientChip();
    return KeyedSubtree(
      key: _composerCardKey,
      child: ListenableBuilder(
        listenable: _input,
        builder: (_, __) {
          final typing = _input.text.isNotEmpty;
          return DeskComposerCard(
            attentionExclude: widget.sessionId,
            highlight: _draggingFiles,
            focus: _inputFocus,
            banner: goal || rcpt != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (goal) _goalBanner(),
                      if (rcpt != null) rcpt,
                    ],
                  )
                : null,
            field: CallbackShortcuts(
              bindings: _composerShortcuts,
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                contentInsertionConfiguration: _keyboardContent,
                minLines: 1,
                maxLines: 10,
                cursorColor: AppColors.fg1,
                onSubmitted: (_) => _sendMessage(),
                style: DeskComposerCard.fieldStyle,
                decoration: DeskComposerCard.decoration(hint),
              ),
            ),
            attach: DeskIconButton('plus',
                tooltip: 'Attach',
                onTap: _onAttachTap,
                iconSize: 16,
                color: AppColors.fg2),
            model: _inboxAgentId(widget.sessionId) == null
                ? Builder(
                    builder: (chipCtx) => DeskModelChip(
                      icon: _modelProvider == null
                          ? 'cpu'
                          : 'provider:$_modelProvider',
                      label: _modelLabel ?? 'Auto',
                      onTap: () => _switchModel(chipCtx),
                    ),
                  )
                : null,
            // No send-mode legend; only the new-line key, while idle.
            hint: !typing || running
                ? null
                : DeskHint([('\u21e7\u21b5', 'new line')]),
            mic: kCanRecord
                ? DeskIconButton('mic', tooltip: 'Record', onTap: _onMicTap)
                : null,
            action: _deskAction(running),
          );
        },
      ),
    );
  }

  Widget _deskRecorder() {
    final reviewing = !_isRecording && _recordingPath != null;
    final total = _playbackDuration > Duration.zero
        ? _playbackDuration
        : _recordingElapsed;
    final showPosition =
        reviewing && (_isPlayingRecording || _playbackPosition > Duration.zero);
    final time = !reviewing
        ? _audioTime(_recordingElapsed)
        : '${_audioTime(showPosition ? _playbackPosition : Duration.zero)} / ${_audioTime(total)}';
    final progress = !reviewing || total.inMilliseconds <= 0
        ? null
        : (_playbackPosition.inMilliseconds / total.inMilliseconds)
            .clamp(0.0, 1.0);
    final agent = (_meAgentName ?? '').trim();
    return DeskVoiceCard(
      recording: _isRecording,
      sending: _sendingAudio,
      playing: _isPlayingRecording,
      label: _isRecording
          ? (agent.isEmpty
              ? 'Recording a voice note'
              : 'Recording a voice note for $agent')
          : 'Voice note ready to send',
      time: time,
      wave: LiveRecordingWave(
          buffer: _waveform, live: _isRecording, progress: progress),
      onDiscard: () => unawaited(_discardRecording()),
      onPlay: () => unawaited(_toggleRecordingPlayback()),
      onStop: () => unawaited(_stopRecording()),
      onSend: () => unawaited(_sendMessage()),
      onMore: reviewing ? () => unawaited(_recordMore()) : null,
    );
  }

  /// Stop when the agent runs and there is nothing to send, else send.
  Widget _deskAction(bool running) {
    final draft = _hasDraft;
    final sendBtn = DeskActionButton(
      icon: 'arrow-up',
      tooltip: 'Send',
      on: _canSend,
      busy: _sendingAudio,
      onTap: _canSend ? () => _sendMessage() : null,
    );
    if (!running) return sendBtn;
    final stop = DeskActionButton(
      icon: 'stop',
      tooltip: 'Stop',
      soft: true,
      onTap: () => _send({'kind': 'interrupt'}),
    );
    if (!draft) return stop;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      stop,
      const SizedBox(width: 6),
      sendBtn,
    ]);
  }

  bool get _hasDraft =>
      _input.text.trim().isNotEmpty || _attachments.isNotEmpty;

  /// The pill's trailing control: one button that is mic, send or stop, with
  /// a bare mic beside stop so voice stays one tap away while the agent runs.
  Widget _composerAction(bool running) {
    final draft = _hasDraft;
    final action = draft
        ? ComposerAction.send
        : running
            ? ComposerAction.stop
            : kCanRecord
                ? ComposerAction.mic
                : ComposerAction.send;
    final morph = ComposerMorphButton(
      action: action,
      enabled: action != ComposerAction.send || _canSend,
      busy: _sendingAudio,
      onTap: switch (action) {
        ComposerAction.stop => () => _send({'kind': 'interrupt'}),
        ComposerAction.mic => _onMicTap,
        ComposerAction.send => _canSend ? () => _sendMessage() : null,
      },
      onLongPress: running && _canSend ? () => _sendMessage(steer: true) : null,
    );
    if (!(running && !draft && kCanRecord)) return morph;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ComposerBareButton('mic', label: 'Record', onTap: _onMicTap),
      const SizedBox(width: 4),
      morph,
    ]);
  }

  Widget _inputBar(bool running, {Widget? top}) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    return AnimatedPadding(
      duration: Motion.fast,
      curve: Motion.enter,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: kMobile ? double.infinity : kDesktopComposerWidth),
          child: LiveCaptionAnchor(
            // Inset from the pane on EVERY layout. Embedded used to be 0, which is
            // why the composer stuck to the sides of the shell.
            padding: EdgeInsets.fromLTRB(
                kMobile
                    ? M.gutter
                    : (widget.embedded ? kComposerGutter : S.s20),
                S.s8,
                kMobile
                    ? M.gutter
                    : (widget.embedded ? kComposerGutter : S.s20),
                kMobile
                    ? S.of(10) + (keyboard > 0 ? S.s8 : mq.padding.bottom)
                    : 18),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (kMobile && _showsQuickActions)
                    ListenableBuilder(
                      listenable: Listenable.merge([_tray, _input]),
                      builder: (_, __) => ComposerTray(
                          controller: _tray,
                          bleed: M.gutter,
                          child: _trayPage(running)),
                    ),
                  if (kMobile &&
                      _dockRun != null &&
                      _state?.status == 'running')
                    ActivityDock(
                        run: _dockRun!,
                        agentId: _me?.displayAgentId ?? 'snippet',
                        onOpen: _openLiveActivity),
                  if (_heldQueue.isNotEmpty) _queuedCard(),
                  // Attachments sit above the composer, never inside it.
                  if (_attachments.isNotEmpty) _attachmentBar(),
                  if (_mentionQuery != null && !_isMissionControl)
                    _mentionList(),
                  if (top != null) top,
                  Swap(
                    stateKey: (_isRecording || _recordingPath != null)
                        ? 'recorder'
                        : 'composer',
                    alignment: Alignment.bottomCenter,
                    child: (_isRecording || _recordingPath != null)
                        ? ValueListenableBuilder<int>(
                            valueListenable: _recorderTick,
                            builder: (_, __, ___) => kMobile
                                ? _mobileRecorder(running)
                                : _deskRecorder(),
                          )
                        : _composerCard(running),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  bool get _showsQuickActions =>
      !_isMissionControl &&
      !widget.readOnly &&
      _inboxAgentId(widget.sessionId) == null;

  /// The composer's "+": on phone sessions with actions it toggles the tray
  /// (turning 45 degrees to read as a close); elsewhere it attaches directly.
  Widget _composerPlus() {
    if (!(kMobile && _showsQuickActions)) {
      return ComposerIconButton('plus', tooltip: 'Attach', onTap: _onAttachTap);
    }
    return TapRegion(
      groupId: _tray,
      child: ListenableBuilder(
        listenable: Listenable.merge([_tray, _tray.progress]),
        builder: (context, _) {
          final k = _tray.progress.value;
          final t = k.clamp(0.0, 1.0);
          return Semantics(
            label: _tray.open ? 'Close actions' : 'Actions',
            expanded: _tray.open,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: C7.rowHi.withValues(alpha: t),
              ),
              child: AnimatedRotation(
                turns: 0.125 * k,
                duration: Duration.zero,
                child: ComposerIconButton('plus',
                    tooltip: 'Actions',
                    onTap: _tray.toggle,
                    color: Color.lerp(AppColors.fg2, AppColors.fg1, t)),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The tray's current page: the action list, or the hand-off or fork
  /// picker swapped in place of it.
  Widget _trayPage(bool running) {
    switch (_tray.view) {
      case 'handoff':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ComposerTrayHeader(
                title: 'Hand off to',
                subtitle: 'They take this session after the current turn.',
                onBack: _tray.back),
            Padding(
              padding: EdgeInsets.fromLTRB(S.of(10), 0, S.of(10), S.of(10)),
              child: SessionHandOffPanel(
                client: widget.client,
                sessionId: widget.sessionId,
                onHandedOff: (name, pending) {
                  _tray.close();
                  _toast(pending
                      ? 'Hands to $name after this turn'
                      : 'Handed to $name');
                },
              ),
            ),
          ],
        );
      case 'fork':
        final events = _state?.events.length ?? 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ComposerTrayHeader(
                title: 'Fork this conversation',
                subtitle:
                    'A new session; this one stays as it is. Files on disk are shared.',
                onBack: _tray.back),
            Padding(
              padding: EdgeInsets.fromLTRB(S.of(10), 0, S.of(10), S.of(10)),
              child: SessionForkPanel(
                fromLabel: 'the latest message',
                total: events > 0 ? events : null,
                onChoose: (_) {
                  _tray.close();
                  _forkFromLatest();
                },
              ),
            ),
          ],
        );
    }
    final lanes = _state?.lanes ?? const <LaneInfo>[];
    final live = lanes.where((l) => l.status == 'running').length;
    void run(VoidCallback fn) {
      _tray.close();
      fn();
    }

    final agent = (_meAgentName ?? '').trim();
    final heading = [if (agent.isNotEmpty) agent, if (_title.isNotEmpty) _title]
        .join(' \u00b7 ');
    final groups = <Widget>[
      if (running && _canSend)
        ComposerGroup(children: [
          ComposerTrayRow(
              icon: 'stop',
              label: 'Interrupt',
              subtitle: 'Stop this step, then send',
              onTap: () => run(() => _send({'kind': 'interrupt'}))),
        ]),
      ComposerGroup(children: [
        ComposerTrayRow(
            icon: 'camera', label: 'Camera', onTap: () => run(_pickCamera)),
        ComposerTrayRow(
            icon: 'image', label: 'Photos', onTap: () => run(_pickPhotos)),
        ComposerTrayRow(
            icon: 'paperclip', label: 'Files', onTap: () => run(_pickFiles)),
      ]),
      ComposerGroup(children: [
        ComposerTrayRow(
            icon: 'arrow-right',
            label: 'Hand off',
            subtitle: 'To another agent, after this turn',
            chevron: true,
            onTap: () => _tray.show('handoff')),
        ComposerTrayRow(
            icon: 'git-branch',
            label: 'Fork from here',
            subtitle: 'A new session; this one stays',
            chevron: true,
            onTap: () => _tray.show('fork')),
        if (lanes.isNotEmpty)
          ComposerTrayRow(
              icon: 'layers',
              label: 'Lanes',
              value: live > 0 ? '$live running' : null,
              chevron: true,
              onTap: () => run(_showLanes)),
      ]),
      ComposerGroup(children: [
        ComposerTrayRow(
            icon: _modelProvider == null ? 'cpu' : 'provider:$_modelProvider',
            label: 'Model',
            value: _modelLabel ?? 'Auto',
            chevron: true,
            onTap: () => run(() => _switchModel(context))),
      ]),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!kMobile && heading.isNotEmpty)
          ComposerTrayItem(index: 0, child: ComposerTrayHeading(heading)),
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) SizedBox(height: S.s12),
          ComposerTrayItem(index: i + 1, child: groups[i]),
        ],
      ],
    );
  }

  // Mirrors _confirmFork(null): with no checkpoint both choices cut at the
  // latest message, so the choice does not change the request.
  Future<void> _forkFromLatest() async {
    final events = _state?.events.length ?? 0;
    try {
      final result = await widget.client.forkSession(
        widget.sessionId,
        eventIndex: events > 0 ? events - 1 : null,
      );
      final id = result['id']?.toString() ?? '';
      final title = result['title']?.toString() ?? 'fork';
      if (id.isEmpty) {
        _toast('Fork created but no session id returned');
        return;
      }
      final open = widget.onOpenSession;
      if (open != null) {
        open(id, title, widget.profile);
      } else {
        _toast('Forked → $title');
      }
    } catch (e) {
      _toast('$e');
    }
  }

  // Composer attachment row: image thumbnails and file cards, each with its
  // own remove button and an upload overlay until the file reaches the daemon.
  Widget _attachmentBar() => ComposerAttachmentBar(
      tiles: [for (final a in _attachments) _attachmentTile(a)]);

  Widget _attachmentTile(_Attachment a) {
    Widget? body;
    final pasted = a.pastedText;
    if (pasted != null) {
      final lines = '\n'.allMatches(pasted.trimRight()).length + 1;
      final firstLine = pasted.trim().split('\n').first.trim();
      body = Container(
        height: ComposerAttachmentTile.side,
        width: 176,
        padding: EdgeInsets.fromLTRB(S.of(10), S.s8, S.s12, S.s8),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              AppIcon('file-text', size: 12, color: AppColors.fg3),
              SizedBox(width: S.of(5)),
              Text('Pasted · $lines lines',
                  style: sans(11, weight: W.label, color: AppColors.fg2)),
            ]),
            SizedBox(height: S.s4),
            Text(firstLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(11, color: AppColors.fg3)),
          ],
        ),
      );
    } else if (a.isImage &&
        !(a.localPath != null && File(a.localPath!).existsSync()) &&
        a.remotePath != null) {
      // A restored draft may have lost its local file; the uploaded copy stands in.
      body = Container(
        width: ComposerAttachmentTile.side,
        height: ComposerAttachmentTile.side,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image(
            image: ResizeImage(widget.client.imageProvider(a.remotePath!),
                width: 168, height: 168),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ColoredBox(
                color: AppColors.surface2,
                child: Center(
                    child: AppIcon('image', size: 16, color: AppColors.fg4)))),
      );
    }
    return ComposerAttachmentTile(
      name: a.name,
      isImage: a.isImage,
      isAudio: a.isAudio,
      uploading: a.uploading,
      localPath: a.localPath,
      body: body,
      onOpen: () => _previewAttachment(a),
      onRemove: () => _setState(() => _attachments.remove(a)),
    );
  }

  PreviewAttachment _toPreview(_Attachment a) {
    final remote = a.remotePath;
    return PreviewAttachment(
      name: a.name,
      isImage: a.isImage,
      isAudio: a.isAudio,
      localPath: a.localPath,
      pastedText: a.pastedText,
      imageProvider:
          remote == null ? null : widget.client.imageProvider(remote),
    );
  }

  /// Preview any attachment; pasted text can be edited, moved back into the
  /// message as plain text, or dropped.
  Future<void> _previewAttachment(_Attachment a) async {
    final pairs = {for (final x in _attachments) _toPreview(x): x};
    final items = pairs.keys.toList();
    await showAttachmentPreview(
      context,
      items,
      _attachments.indexOf(a),
      onRemove: (p) => _setState(() => _attachments.remove(pairs[p])),
      onEditText: (p, text) => _setState(() {
        final t = pairs[p]!;
        if (text.trim().isEmpty) {
          _attachments.remove(t);
        } else {
          t.pastedText = text;
        }
      }),
      onInsertText: (p, text) => _setState(() {
        _attachments.remove(pairs[p]);
        final current = _input.text;
        final joined = current.trim().isEmpty ? text : '$current\n$text';
        _input.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length),
        );
      }),
    );
  }

  // ---- event → widget (pairs tool_call with its tool_result) ----
}
