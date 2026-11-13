part of 'session.dart';

const double kDesktopComposerWidth = 780;

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

  Future<void> _sendMessage() async {
    if (_input.text.trim().isNotEmpty || _attachments.isNotEmpty) {
      HapticFeedback.lightImpact();
    }
    // The composer can be triggered by both the send button and keyboard submit;
    // serialize the entire async path so a rapid double tap cannot create two
    // distinct nonces and two server turns.
    if (_sendingMessage) return;
    _sendingMessage = true;
    try {
      await _sendMessageOnce();
    } finally {
      _sendingMessage = false;
    }
  }

  Future<void> _sendMessageOnce() async {
    // Audio can be sent directly from the composer: stop the live take, upload
    // it through the normal attachment path, then continue with the same send.
    if (_sendingAudio) return;
    if (_isRecording || _recordingPath != null) {
      _sendingAudio = true;
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
      if (running) {
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
    _setState(() {
      _hideQueuedAt(visible);
      if (_heldQueue.length <= 1) {
        _hoveredQueuedIndex = null;
      }
    });
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
    _setState(() {
      _queueHidden.addAll(_heldQueue.map((item) => item.id));
      _hoveredQueuedIndex = null;
    });
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
      if (_heldQueue.length <= 1) {
        _hoveredQueuedIndex = null;
      }
    });
    _send({'kind': 'steer_queued', 'value': item.id, 'nonce': nonce});
    _armAckWatchdog();
  }

  Widget _queuedCard() {
    final queue = _heldQueue;
    if (queue.isEmpty) return const SizedBox.shrink();
    final count = queue.length;

    Widget textAction(String label, VoidCallback onTap, Color color) =>
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: S.s6, vertical: S.s2),
            child: Text(label, style: sans(12, color: color)),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: S.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (count > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: S.s4),
              child: Row(children: [
                const SizedBox(width: S.s6),
                Text('$count queued', style: sans(12, color: AppColors.fg4)),
                const Spacer(),
                textAction('Clear', _cancelAllQueued, AppColors.fg4),
                textAction('Send all', _steerAllQueued, AppColors.accent),
              ]),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 156),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: count,
              separatorBuilder: (_, __) => const SizedBox(height: S.s4),
              itemBuilder: (_, qi) => _queuedItemRow(qi, queue[qi]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _queuedItemRow(int qi, QueuedInput item) {
    final isHovered = _hoveredQueuedIndex == qi;
    final showActions = kMobile || isHovered;
    final text = _queuedText(item.text);
    final counts = _queuedAttachCounts(item.text);
    final images = _queuedImagePaths(item.text);
    final others = counts.$1 + counts.$3;
    final label = text.isNotEmpty
        ? text.replaceAll('\n', ' ')
        : images.isNotEmpty
            ? (images.length == 1 ? 'Image' : '${images.length} images')
            : 'Attachment';
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget thumb(String path) => Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image(
            image: ResizeImage(widget.client.imageProvider(path),
                width: (22 * dpr).round()),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                Center(child: AppIcon('image', size: 11, color: AppColors.fg4)),
          ),
        );

    Widget iconAction(String icon, String tip, VoidCallback onTap,
            {Color? color}) =>
        Tooltip(
          message: tip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox.square(
              dimension: kMobile ? 32 : 24,
              child: Center(
                  child:
                      AppIcon(icon, size: 13, color: color ?? AppColors.fg4)),
            ),
          ),
        );

    return MouseRegion(
      onEnter: (_) {
        if (_hoveredQueuedIndex != qi) {
          _setState(() => _hoveredQueuedIndex = qi);
        }
      },
      onExit: (_) {
        if (_hoveredQueuedIndex == qi) {
          _setState(() => _hoveredQueuedIndex = null);
        }
      },
      child: AnimatedContainer(
        duration: Motion.quick,
        height: kMobile ? 38 : 32,
        padding: EdgeInsets.only(
            left: images.isNotEmpty ? S.s6 : S.s12, right: S.s4),
        decoration: BoxDecoration(
          color: isHovered ? AppColors.raised : AppColors.surface1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          if (images.isEmpty)
            AppIcon('clock', size: 12, color: AppColors.fg4)
          else ...[
            for (final path in images.take(3)) thumb(path),
            if (images.length > 3)
              Text('+${images.length - 3}',
                  style: sans(11, tabular: true, color: AppColors.fg4)),
          ],
          const SizedBox(width: S.s8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  sans(13, color: text.isEmpty ? AppColors.fg3 : AppColors.fg2),
            ),
          ),
          if (others > 0) ...[
            const SizedBox(width: S.s6),
            AttachmentPill(audio: counts.$1, images: 0, files: counts.$3),
          ],
          AnimatedOpacity(
            opacity: showActions ? 1 : 0,
            duration: Motion.quick,
            child: IgnorePointer(
              ignoring: !showActions,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                iconAction('edit', 'Edit', () => _editQueuedAt(qi)),
                iconAction('x', 'Remove', () => _cancelQueuedAt(qi)),
              ]),
            ),
          ),
          iconAction('arrow-up', 'Send now', () => _steerQueuedAt(qi),
              color: AppColors.accent),
        ]),
      ),
    );
  }

  // Clean text for a held/pending message (markers stripped). Attachments
  // surface as AttachmentPill beside the text — same as a real Bubble.
  String _queuedText(String m) => hideAttachmentMarkers(m);

  List<String> _queuedImagePaths(String m) => [
        for (final x in RegExp(r'\[attached image —([^\]]*)\]').allMatches(m))
          if ((x.group(1) ?? '').trim().isNotEmpty) x.group(1)!.trim()
      ];

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
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.fromLTRB(
            10, kMobile ? 4 : 8, kMobile ? 4 : 8, kMobile ? 4 : 8),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Row(children: [
          AppIcon('goal', size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(plainInline(_state!.goal!.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, color: AppColors.fg2)),
          ),
          Text(_state!.goal!.paused ? 'paused' : 'active',
              style: mono(10, color: AppColors.accent)),
          const SizedBox(width: 5),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: matches.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _applyMention(matches[i]),
                    child: Container(
                      height: kMobile ? 44 : 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
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
                        const SizedBox(width: 10),
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
    final hint = _isMissionControl
        ? 'Ask Mission Control…'
        : running
            ? 'Steer or queue a message'
            : 'Reply to Snippet';
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
            controller: _input,
            focusNode: _inputFocus,
            contentInsertionConfiguration: _keyboardContent,
            minLines: 1,
            maxLines: 8,
            cursorColor: AppColors.accent,
            onSubmitted: (_) => _sendMessage(),
            style: TS.body(AppColors.fg1),
            decoration: ComposerCard.decoration(hint),
          ),
        ),
        attach:
            ComposerIconButton('plus', tooltip: 'Attach', onTap: _onAttachTap),
        trailing: _inboxAgentId(widget.sessionId) == null ? _modelChip : null,
        mic: kCanRecord
            ? ComposerIconButton(_isRecording ? 'mic-off' : 'mic',
                tooltip: 'Record',
                onTap: _onMicTap,
                color: _isRecording ? AppColors.danger : null)
            : null,
        send: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _input,
          builder: (_, __, ___) {
            final queue = running && _canSend;
            final stop = running && !queue;
            return ComposerSendButton(
                enabled: stop || _canSend,
                stop: stop,
                onTap: stop
                    ? () => _send({'kind': 'interrupt'})
                    : (_canSend ? _sendMessage : null));
          },
        ),
      ),
    );
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
                kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
                8,
                kMobile ? M.gutter : (widget.embedded ? kComposerGutter : 20),
                10 + (keyboard > 0 ? 8 : mq.padding.bottom)),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_heldQueue.isNotEmpty) _queuedCard(),
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
                            builder: (_, __, ___) => _mobileRecorder(running),
                          )
                        : _composerCard(running),
                  ),
                ]),
          ),
        ),
      ),
    );
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
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
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
              const SizedBox(width: 5),
              Text('Pasted · $lines lines',
                  style: sans(11, weight: W.label, color: AppColors.fg2)),
            ]),
            const SizedBox(height: 4),
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

class SessionContextBar extends StatelessWidget {
  const SessionContextBar({
    super.key,
    required this.laneCount,
    required this.laneRunning,
    required this.onTapLanes,
    required this.termCount,
    required this.termRunning,
    required this.onTapTerms,
  });

  final int laneCount;
  final bool laneRunning;
  final VoidCallback onTapLanes;
  final int termCount;
  final bool termRunning;
  final VoidCallback onTapTerms;

  @override
  Widget build(BuildContext context) {
    if (laneCount == 0 && termCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (laneCount > 0)
            _ContextChip(
              icon: 'layers',
              label: 'Lanes $laneCount',
              running: laneRunning,
              onTap: onTapLanes,
            ),
          if (laneCount > 0 && termCount > 0) const SizedBox(width: 6),
          if (termCount > 0)
            _ContextChip(
              icon: 'terminal',
              label: '$termCount ${termCount == 1 ? 'terminal' : 'terminals'}',
              running: termRunning,
              onTap: onTapTerms,
            ),
        ],
      ),
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({
    required this.icon,
    required this.label,
    required this.running,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 24,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(icon, size: 12, color: AppColors.fg3),
                  const SizedBox(width: 6),
                  Text(label, style: TS.caption(AppColors.fg3)),
                  if (running) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.ok,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class SessionContextFooter extends StatelessWidget {
  const SessionContextFooter({
    super.key,
    required this.contextWindow,
    required this.lastPromptTokens,
    required this.cacheReadTokens,
    this.rateSecondary,
  });

  final int contextWindow;
  final int lastPromptTokens;
  final int cacheReadTokens;
  final RateWindow? rateSecondary;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    if (contextWindow > 0 && lastPromptTokens > 0) {
      final frac = (lastPromptTokens / contextWindow).clamp(0.0, 1.0);
      items.add(_ContextRingStat(
        fraction: frac,
        label: '${(frac * 100).round()}% context',
      ));
    }
    if (cacheReadTokens > 0) {
      items.add(Text('${fmtSi(cacheReadTokens)} cached',
          style: TS.caption(AppColors.fg4)));
    }
    final secondary = rateSecondary;
    if (secondary != null && secondary.isReported && !secondary.isExpired) {
      final frac = (secondary.usedPercent / 100).clamp(0.0, 1.0);
      final pct = secondary.usedPercent.clamp(0, 100).round();
      final win = limitWindowLabel(secondary);
      items.add(_ContextRingStat(
        fraction: frac,
        label: '$pct% ${win == '7d' ? 'this week' : win}',
      ));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            items[i],
          ],
        ],
      ),
    );
  }
}

class _ContextRingStat extends StatelessWidget {
  const _ContextRingStat({required this.fraction, required this.label});

  final double fraction;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 11,
            child: CustomPaint(
              painter: _ContextRingPainter(
                fraction: fraction,
                fill: AppColors.fg3,
                track: AppColors.surface3,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(label, style: TS.caption(AppColors.fg4)),
        ],
      );
}

class _ContextRingPainter extends CustomPainter {
  const _ContextRingPainter({
    required this.fraction,
    required this.fill,
    required this.track,
  });

  final double fraction;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..color = track);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fraction,
        true,
        Paint()..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_ContextRingPainter old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}
