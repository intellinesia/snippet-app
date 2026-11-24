part of 'session.dart';

extension _SessionScreenAppBarExt on _SessionScreenState {
  void _applyTermFrame(Map<String, dynamic> j) {
    final seq = (j['seq'] as num?)?.toInt() ?? 0;
    if (seq != 0 && seq == _termSeq) return;
    if (seq != 0) _termSeq = seq;
    final id = (j['id'] as String?) ?? '0';
    final op = (j['op'] as String?) ?? '';
    final cols = (j['cols'] as num?)?.toInt();
    final rows = (j['rows'] as num?)?.toInt();
    final raw = j['data'] as String?;
    final bytes = (raw == null || raw.isEmpty)
        ? Uint8List(0)
        : Uint8List.fromList(base64Decode(raw));
    if (!mounted) return;
    _setState(() {
      final pane = _ensureTerm(id);
      final wasAlive = pane.alive;
      pane.alive = j['alive'] == true;
      // Only a shell that ran can end; a fresh pane reports !alive while its
      // pty spawns, and that must stay "starting".
      final exited = !pane.alive && !pane.ended && (wasAlive || pane.live);
      if (pane.alive) pane.ended = false;
      if (op != 'snapshot') {
        if (bytes.isNotEmpty) {
          pane.terminal.write(utf8.decode(bytes, allowMalformed: true));
        }
        if (cols != null) pane.cols = cols;
        if (rows != null) pane.rows = rows;
        if (op == 'out') pane.live = true;
      }
      if (exited) {
        pane.ended = true;
        final t = pane.terminal;
        final nl = t.buffer.cursorX == 0 ? '' : '\r\n';
        t.write('$nl\x1b[90m[process exited]\x1b[0m\r\n\x1b[?25l');
      }
    });
    // Only an `alive`/`live` transition or a new terminal changes what the
    // sidebar shows. Output frames must not republish: that would rebuild the
    // shell on every byte the pty writes.
    _publishTerminals();
  }

  /// Respawn an ended shell in place: same id, tab and scrollback. The daemon
  /// reaps the dead pty and spawns a new one on `new` for a known id.
  void _restartTerm(String id) {
    final i = _terms.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final t = _terms[i];
    _setState(() {
      t.ended = false;
      t.alive = false;
      t.live = false;
      _termFocus = i;
    });
    t.terminal.write('\x1b[?25h');
    _send({
      'wire': 'term',
      'op': 'new',
      'id': t.id,
      'cols': t.cols,
      'rows': t.rows,
    });
    _publishTerminals();
  }

  /// The session's folder with the home prefix folded to `~`.
  String get _termCwd {
    final ws = (_state?.workspace ?? '').trim();
    final raw = ws.isNotEmpty ? ws : (_me?.folder ?? '').trim();
    return raw
        .replaceFirst(RegExp(r'^(/home/[^/]+|/Users/[^/]+)(?=/|$)'), '~')
        .replaceFirst(RegExp(r'/+$'), '');
  }

  String? get _termBranch {
    final b = _me?.branch?.trim() ?? '';
    return b.isEmpty ? null : b;
  }

  String _nextTermTitle() {
    var n = _terms.length + 1;
    final used = _terms.map((t) => t.title).toSet();
    while (used.contains('Shell $n')) {
      n++;
    }
    return 'Shell $n';
  }

  _LiveTerm _ensureTerm(String id) {
    for (final t in _terms) {
      if (t.id == id) return t;
    }
    final t = _LiveTerm(id, title: _nextTermTitle());
    _terms.add(t);
    return t;
  }

  void _openTerm({bool fresh = false}) {
    // Lead has no working tree to shell into.
    if (_isLead) return;
    // Second click on Shell hides the drawer — keep the pty so reopening is instant.
    if (!fresh && _termOpen && _terms.isNotEmpty) {
      _setState(() => _termOpen = false);
      return;
    }
    if (!fresh && _terms.isNotEmpty) {
      _setState(() => _termOpen = true);
      final t = _terms[_termFocus.clamp(0, _terms.length - 1)];
      _send({
        'wire': 'term',
        'op': 'open',
        'id': t.id,
        'cols': t.cols,
        'rows': t.rows,
      });
      _publishTerminals();
      return;
    }
    final used = _terms.map((t) => int.tryParse(t.id) ?? 0).fold(0, math.max);
    final id = _terms.isEmpty ? '0' : '${used + 1}';
    _setState(() {
      _termOpen = true;
      _ensureTerm(id);
      _termFocus = _terms.length - 1;
    });
    _send({
      'wire': 'term',
      'op': fresh ? 'new' : 'open',
      'id': id,
      'cols': 80,
      'rows': 24,
    });
    _publishTerminals();
  }

  void _closeTerm(String id) {
    _send({'wire': 'term', 'op': 'close', 'id': id});
    _setState(() {
      _terms.removeWhere((t) => t.id == id);
      if (_terms.isEmpty) {
        _termOpen = false;
        _termFocus = 0;
      } else {
        _termFocus = _termFocus.clamp(0, _terms.length - 1);
      }
    });
    _publishTerminals();
  }

  /// Focus an existing terminal by index, opening the drawer if it is closed.
  ///
  /// Selecting a row in the shell's terminal panel must land on *that*
  /// terminal, so this takes an index rather than toggling whatever was last
  /// focused.
  void _focusTerm(int i) {
    if (_isLead || i < 0 || i >= _terms.length) return;
    _setState(() {
      _termOpen = true;
      _termFocus = i;
    });
    final t = _terms[i];
    _send({
      'wire': 'term',
      'op': 'open',
      'id': t.id,
      'cols': t.cols,
      'rows': t.rows,
    });
    _publishTerminals();
  }

  /// Hand the shell a host for this session's terminals, plus whether the pane
  /// should currently be showing.
  ///
  /// Cheap and idempotent; called from the paths that can change the set, the
  /// focus, or the open flag — never from the output stream.
  void _publishTerminals() {
    final publish = widget.onTerminalHost;
    if (publish == null) return;
    publish(
      TerminalHost(
        terms: [
          for (final t in _terms)
            TerminalInfo(
              id: t.id,
              title: t.title,
              alive: t.alive,
              live: t.live,
            ),
        ],
        focus: _termFocus,
        buildView: _buildTermView,
        onFocus: _focusTermById,
        onRequestNew: () => _openTerm(fresh: true),
        onRequestClose: _closeTerm,
      ),
      // `_termOpen` is the "not minimized" flag. Minimizing hides the pane but
      // deliberately keeps the pty alive — only the sidebar destroys a shell.
      _termOpen,
    );
  }

  /// Render one terminal by id, for whichever pane is currently hosting it.
  ///
  /// The shell owns the pane; the session owns the socket and the view's input
  /// wiring, so it must supply the widget rather than expose the `Terminal`.
  Widget _buildTermView(String id, {required bool mobileKeys}) {
    final t = _terms.firstWhere((e) => e.id == id, orElse: () => _terms.first);
    return SessionTermView(
      alive: t.alive,
      ended: t.ended,
      title: t.title,
      onRestart: () => _restartTerm(t.id),
      cwd: _termCwd,
      branch: _termBranch,
      terminal: t.terminal,
      onInput: (bytes) => _termInFor(t.id, bytes),
      onResize: (cols, rows) => _termResizeFor(t.id, cols, rows),
      onClose: () => _closeTerm(t.id),
      mobileKeys: mobileKeys,
      showChrome: false,
    );
  }

  /// Focus a terminal by id. The shell knows ids; the session knows order.
  void _focusTermById(String id) {
    final i = _terms.indexWhere((t) => t.id == id);
    if (i >= 0) _focusTerm(i);
  }

  void _termInFor(String id, Uint8List bytes) {
    _send({
      'wire': 'term',
      'op': 'in',
      'id': id,
      'data': base64Encode(bytes),
    });
  }

  void _termResizeFor(String id, int cols, int rows) {
    for (final t in _terms) {
      if (t.id == id) {
        t.cols = cols;
        t.rows = rows;
        break;
      }
    }
    _send({
      'wire': 'term',
      'op': 'resize',
      'id': id,
      'cols': cols,
      'rows': rows,
    });
  }

  void _termIn(Uint8List bytes) {
    if (_terms.isEmpty) return;
    final t = _terms[_termFocus.clamp(0, _terms.length - 1)];
    _send({
      'wire': 'term',
      'op': 'in',
      'id': t.id,
      'data': base64Encode(bytes),
      'cols': t.cols,
      'rows': t.rows,
    });
  }

  void _termResize(int cols, int rows) {
    if (_terms.isEmpty) return;
    final t = _terms[_termFocus.clamp(0, _terms.length - 1)];
    t.cols = cols;
    t.rows = rows;
    _send({
      'wire': 'term',
      'op': 'resize',
      'id': t.id,
      'cols': cols,
      'rows': rows,
    });
  }

  Future<void> _renameCurrent() async {
    if (_isLead) return;
    final title = await promptText(context,
        title: 'Rename session',
        initial: _title,
        hint: 'New title',
        saveLabel: 'Rename');
    if (title == null) return;
    final before = _title;
    _setState(() => _publishTitle(title));
    try {
      await widget.client.renameSession(widget.sessionId, title);
    } catch (e) {
      if (mounted) {
        _setState(() => _publishTitle(before));
        _toast('$e');
      } else {
        _publishTitle(before);
      }
    }
  }

  // On desktop, keep chat content to a comfortable reading width (centered),
  // rather than stretching across the whole pane.
  Widget _centerWide(Widget child, {double extra = 0}) => widget.embedded
      ? Center(
          child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 960 + extra), child: child))
      : child;

  // Mobile chat header: a back button that returns to the session list, the
  // title with a live status dot, and a compact subtitle folding in the key
  // facts (status · model · context · approval) — so there's no separate,
  // cramped desktop toolbar + scrolling chip strip on a phone.
  /// Phone session bar: back, title, and the shell action. Deliberately NO run
  /// state — the chat canvas already carries working/idle, so a second readout
  /// here was one more thing competing with the title for the same 56px.
  Widget _readOnlyHeader(String status) {
    final live = status == 'running';
    final label = switch (status) {
      'running' => 'Working',
      'completed' || 'idle' => 'Finished',
      'failed' => 'Failed',
      'connecting' => 'Connecting',
      _ => status,
    };
    final (fg, _) = toneColors(live ? Tone.run : Tone.neutral);
    return Container(
      height: kMobile ? M.appBarHeight : 44,
      padding: EdgeInsets.symmetric(horizontal: S.s6),
      color: kMobile ? AppColors.pageBg : AppColors.bg,
      child: Row(children: [
        if (kMobile || Navigator.of(context).canPop())
          IconBtn('chevron-left',
              size: kMobile ? M.minTarget : 32,
              iconSize: 20,
              tooltip: 'Back',
              onTap: () => Navigator.of(context).maybePop())
        else
          SizedBox(width: S.s6),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s6),
            child: Text(
              _title.isEmpty ? 'Lane' : _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(kMobile ? M.sectionTitle : 15,
                  weight: W.label, color: AppColors.fg1),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(right: S.of(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            SizedBox(width: S.s6),
            Text(label, style: mono(11, color: fg)),
          ]),
        ),
      ]),
    );
  }

  void _openPullRequests() {
    final status = _github;
    if (status == null) return;
    final reveal = widget.onShowPullRequests;
    if (reveal != null) {
      reveal(status);
      return;
    }
    openPullRequests(context,
        client: widget.client, session: widget.sessionId, status: status);
  }

  void _openDeliverables() {
    final files = <({String path, String caption})>[
      for (final e in _state?.events ?? const <Map<String, dynamic>>[])
        if (e['kind'] == 'file_presented')
          (
            path: e['path']?.toString() ?? '',
            caption: e['caption']?.toString() ?? ''
          ),
    ];
    if (kMobile) {
      showArtifactSheet(
          context,
          (close) => SessionDeliverables(
                client: widget.client,
                session: widget.sessionId,
                files: files,
                onOpenFileTab: widget.onOpenFileTab,
                onClose: close,
              ));
      return;
    }
    presentScreen(context,
        style: PanelStyle.drawer,
        maxWidth: 560,
        purpose: ShellPanelPurpose.deliverables,
        originClient: widget.client,
        originSessionId: widget.sessionId,
        builder: (_, close) => SessionDeliverables(
              client: widget.client,
              session: widget.sessionId,
              files: files,
              onOpenFileTab: widget.onOpenFileTab,
              onClose: close,
            ));
  }

  void _openWorkspaceFile(String full, String name) {
    final open = widget.onOpenFileTab;
    if (open != null) {
      open(full, name);
    } else {
      presentFileOnDesktop(context,
          client: widget.client, path: full, name: name);
    }
  }

  void _openChangedFile(String rel) {
    final ws = _state?.workspace ?? '';
    final full = rel.startsWith('/') || ws.isEmpty
        ? rel
        : '${ws.endsWith('/') ? ws : '$ws/'}$rel';
    final name = rel.split('/').last;
    if (openFileForViewing(context,
        client: widget.client, path: full, name: name)) {
      return;
    }
    final open = widget.onOpenFileTab;
    if (open != null) {
      open(full, name);
    } else {
      presentFileOnDesktop(context,
          client: widget.client, path: full, name: name);
    }
  }

  double _mobileHeaderTopPad(HarnessState? s) {
    if (widget.mobileTopBar != null) return GlassTopFrame.inset + S.s12;
    if (_isLead) return StageBar.phoneHeight + S.s8;
    return GlassTopFrame.inset + S.s12;
  }

  Widget _mobileHeader(HarnessState? s) {
    final offline = _connError != null;
    final stuck = _connError == _SessionScreenState._unreachable;
    final back = widget.onMenu ?? () => Navigator.maybePop(context);
    if (_isLead) {
      return _mcStageHeader(s, stuck);
    }
    // Stays the same with the keyboard up: swapping headers made it jump.
    if (!offline && _me != null) {
      final agent = (_meAgentName ?? '').trim().isEmpty
          ? (_me!.displayAgentId ?? 'Snippet')
          : _meAgentName!;
      final needsYou =
          s?.pendingQuestion != null || s?.status == 'waiting_for_input';
      final plan = _me!.plan;
      final step = plan != null && plan.total > 0 && plan.done < plan.total
          ? 'plan ${(plan.done + 1).clamp(1, plan.total)} of ${plan.total}'
          : '';
      // Scrolled away from the working row: the header carries it.
      final dock = _dockRun;
      final workingAway = !_stickToBottom &&
          dock != null &&
          s?.status == 'running';
      final word = needsYou
          ? 'waiting on you'
          : s?.status == 'in_review'
              ? 'in review'
              : workingAway
                  ? 'working · ${formatWorkDuration(DateTime.now().difference(dock.startedAt))}'
                  : step;
      final lanesPill = lanePillLabel(s?.lanes ?? const <LaneInfo>[]);
      return MobileBackBar(
        title: _title.isEmpty ? 'Session' : _title,
        subtitle: word.isEmpty ? agent : '$agent · $word',
        onBack: back,
        keepBack: true,
        onTitleTap: () => _openActionsDrawer(s),
        onTitleTapHint: 'Session actions',
        trailing: [
          if (lanesPill != null)
            GestureDetector(
              onTap: _showLanes,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: AppColors.fg2, shape: BoxShape.circle)),
                  SizedBox(width: S.s6),
                  Text(lanesPill,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.fg2)),
                ]),
              ),
            ),
          RoundBtn(
            icon: 'more-horizontal',
            tooltip: 'Session actions',
            onTap: () => _openActionsDrawer(s),
          ),
        ],
      );
    }
    final ws = s?.workspace.trim() ?? '';
    final folder = ws.isEmpty ? '' : lastPathSegment(ws, ifEmpty: ws);
    String joinFolder(String state) =>
        folder.isNotEmpty ? '$state · $folder' : state;

    String sub = folder;
    Widget? subView = offline ? _mobileConnectionLine() : null;
    if (!offline && s != null) {
      if (s.status == 'running') {
        final started = DateTime.tryParse(s.turnStartedAt ?? '');
        final mins =
            started == null ? 0 : DateTime.now().difference(started).inMinutes;
        final label = joinFolder(mins >= 1 ? 'Working ${mins}m' : 'Working');
        sub = '';
        subView = Row(mainAxisSize: MainAxisSize.min, children: [
          WorkingDots(size: 3, color: AppColors.fg2),
          SizedBox(width: S.of(5)),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TS.caption(AppColors.fg2).copyWith(fontSize: 12, height: 1.2),
            ),
          ),
        ]);
      } else if (s.compacting) {
        sub = joinFolder('Tidying up');
      } else if (s.pendingQuestion != null || s.status == 'waiting_for_input') {
        sub = joinFolder('Needs you');
      } else if (s.status == 'in_review') {
        sub = joinFolder('In review');
      }
    }
    final working = s?.status == 'running';
    return StageBar(
      framed: false,
      members: const [],
      title: _title.isEmpty ? 'Session' : _title,
      subtitle: working ? null : (sub.isEmpty ? null : sub),
      below: subView,
      onBack: back,
      onTap: stuck ? _retryNow : () => _openActionsDrawer(s),
      trailing: RoundBtn(
        icon: 'terminal',
        tooltip: 'Shell',
        size: 44,
        iconSize: 18,
        onTap: _openTerm,
      ),
    );
  }

  /// Lead on stage; the count is the board's in-progress tasks.
  Widget _mcStageHeader(HarnessState? s, bool stuck) {
    final n = _mcInFlight ?? 0;
    final working = s?.status == 'running';
    return StageBar(
      framed: false,
      members: [
        StageMember('lead',
            state: working
                ? AgentCharacterState.working
                : AgentCharacterState.idle),
      ],
      title: 'Lead',
      subtitle: working
          ? 'Coordinator \u00b7 Working'
          : n > 0
              ? 'Coordinator \u00b7 $n ${n == 1 ? 'task' : 'tasks'} in flight'
              : 'Coordinator',
      onTap: stuck ? _retryNow : () => _openActionsDrawer(s),
      trailing: RoundBtn(
        icon: 'phone',
        tooltip: 'Start voice',
        size: 44,
        iconSize: 18,
        onTap: () => startMobileVoice(context, widget.client),
      ),
    );
  }

  bool get _hasTermDock => !kMobile && !_isLead && !widget.readOnly;

  Widget _withTermDock(Widget chat) {
    if (!_hasTermDock) return chat;
    final open = _termOpen && _terms.isNotEmpty;
    return LayoutBuilder(builder: (context, box) {
      final maxH = (box.maxHeight - 120).clamp(120.0, double.infinity);
      final height = !open
          ? 0.0
          : _termMax
              ? box.maxHeight
              : _termHeight.clamp(120.0, maxH);
      return Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: _termMax ? 0 : height,
          child: chat,
        ),
        if (open)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            child: _desktopTermDock(maxH),
          ),
      ]);
    });
  }

  Widget _desktopTermDock(double maxH) {
    final i = _termFocus.clamp(0, _terms.length - 1);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TermDockBar(
            tabs: _termTabs,
            focus: i,
            onSelect: _selectTermTab,
            onRename: (n) => _renameTerm(_terms[n].id),
            onClose: (n) => _closeTerm(_terms[n].id),
            onNew: () => _openTerm(fresh: true),
            actions: [
              _dockAction(
                  _termMax ? 'shrink' : 'expand',
                  _termMax ? 'Restore' : 'Maximize',
                  () => _setState(() => _termMax = !_termMax)),
              _dockAction('chevron-down', 'Hide terminal', () {
                _setState(() {
                  _termOpen = false;
                  _termMax = false;
                });
                _publishTerminals();
              }),
            ],
          ),
          Expanded(
            child: SessionTermView(
              key: ValueKey('dock-term-${_terms[i].id}'),
              alive: _terms[i].alive,
              ended: _terms[i].ended,
              title: _terms[i].title,
              onRestart: () => _restartTerm(_terms[i].id),
              cwd: _termCwd,
              branch: _termBranch,
              terminal: _terms[i].terminal,
              onInput: _termIn,
              onResize: _termResize,
              onClose: () => _closeTerm(_terms[i].id),
              mobileKeys: false,
              showChrome: false,
              flat: true,
            ),
          ),
        ]),
        if (!_termMax)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 5,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) => _setState(() {
                  _termHeight = (_termHeight - d.delta.dy).clamp(120.0, maxH);
                }),
                onDoubleTap: () => _setState(() => _termMax = true),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _dockAction(String icon, String tooltip, VoidCallback onTap) =>
      IconBtn(icon, size: 26, iconSize: 13, tooltip: tooltip, onTap: onTap);

  Widget _mobileTermTab() {
    final i = _termFocus.clamp(0, _terms.length - 1);
    final t = _terms[i];
    final cwd = _termCwd;
    final branch = _termBranch;
    final sub =
        [if (cwd.isNotEmpty) cwd, if (branch != null) branch].join(' · ');
    return Material(
      color: AppColors.canvas,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MobileBackBar(
          title: 'Terminals',
          subtitleView: sub.isEmpty
              ? null
              : Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: codeMono(12, height: 1.4, color: AppColors.fg3)),
          onBack: () => _setState(() => _termOpen = false),
          keepBack: true,
          trailing: [
            RoundBtn(
                icon: 'plus',
                tooltip: 'New shell',
                onTap: () => _openTerm(fresh: true)),
          ],
        ),
        if (_terms.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: MobileTermTabs(
              tabs: _termTabs,
              focus: i,
              onSelect: _selectTermTab,
              onRename: (n) => _renameTerm(_terms[n].id),
              onClose: (n) => _closeTerm(_terms[n].id),
            ),
          ),
        Expanded(
          child: SessionTermView(
            key: ValueKey('mobile-term-${t.id}'),
            alive: t.alive,
            ended: t.ended,
            title: t.title,
            onRestart: () => _restartTerm(t.id),
            terminal: t.terminal,
            onInput: _termIn,
            onResize: _termResize,
            onClose: () => _closeTerm(t.id),
            mobileKeys: true,
            showChrome: false,
          ),
        ),
      ]),
    );
  }

  /// Rename a terminal from its tab. Titles are local to this client (the pty
  /// has no notion of a name), so this only has to republish to the sidebar.
  Future<void> _renameTerm(String id) async {
    final t = _terms.firstWhere((e) => e.id == id, orElse: () => _terms.first);
    final name = await promptText(context,
        title: 'Rename terminal',
        initial: t.title,
        hint: 'Terminal name',
        saveLabel: 'Rename');
    if (name == null || name.trim().isEmpty) return;
    _setState(() => t.title = name.trim());
    _publishTerminals();
  }

  List<TermTab> get _termTabs => [
        for (final t in _terms)
          TermTab(t.title, termDotColor(alive: t.alive, ended: t.ended)),
      ];

  void _selectTermTab(int n) {
    _setState(() => _termFocus = n);
    _publishTerminals();
  }

  // macOS keeps this row focused on the active session title. Workspace
  // context and Git actions live in the clickable repository bar above.
  // Set an autonomous /goal: the agent drives toward it on its own until it's
  // done, you cancel, or it's rate-limited. Sent as a LoopInput over the socket.
  Future<void> _setGoal({String initial = ''}) async {
    final text = await promptText(context,
        title: initial.isEmpty ? 'Set goal' : 'Edit goal',
        initial: initial,
        hint: 'What should the agent work toward?',
        saveLabel: 'Set goal',
        minLines: 2,
        maxLines: 4);
    final t = text?.trim();
    if (t == null || t.isEmpty || t == initial.trim()) return;
    _toast('Submitting goal…');
    _send({'kind': 'set_goal', 'value': t});
    _toast('Goal set — the agent will drive toward it');
  }

  void _submitGoal(String t) {
    _send({'kind': 'set_goal', 'value': t});
    _toast('Goal set — the agent will drive toward it');
  }

  /// Desktop writes the goal inside the panel; the phone keeps its sheet.
  void _editGoal() {
    if (kMobile) {
      _setGoal();
      return;
    }
    sessionGoalEditRequest.value = true;
    _showPanel();
  }

  void _resumeGoal() {
    _send({'kind': 'resume_goal'});
    _toast('Resuming the goal');
  }

  void _cancelGoal() {
    _send({'kind': 'cancel_goal'});
    _toast('Cancelling the goal');
  }

  /// Hand the session to another agent: pick one, optional note, done.
  void _showHandOff() {
    showAppSheet(context,
        title: 'Hand off',
        subtitle: 'Pass this session to another agent',
        maxWidth: 400,
        maxHeight: 560,
        child: SessionHandOffSheet(
          client: widget.client,
          sessionId: widget.sessionId,
          onHandedOff: (name, pending) => _toast(
              pending ? 'Hands to $name after this turn' : 'Handed to $name'),
        ));
  }

  void _openAutonomy() {
    if (!kMobile) {
      presentScreen(context,
          style: PanelStyle.drawer,
          purpose: ShellPanelPurpose.autonomy,
          originClient: widget.client,
          originSessionId: widget.sessionId,
          builder: (_, close) => AutonomyPanel(client: widget.client));
      return;
    }
    showAppSheet(context,
        title: 'Automated wakes',
        maxWidth: 440,
        maxHeight: 680,
        child: AutonomyPanel(client: widget.client, embedded: true));
  }

  void _openWakes() {
    final name = _title.trim().isEmpty ? widget.sessionId : _title.trim();
    if (!kMobile) {
      presentScreen(context,
          style: PanelStyle.drawer,
          purpose: ShellPanelPurpose.wakes,
          panelId: widget.sessionId,
          originClient: widget.client,
          originSessionId: widget.sessionId,
          builder: (_, close) => SingleChildScrollView(
              padding: EdgeInsets.all(S.s12),
              child: AgentWakePanel(
                  client: widget.client, owner: widget.sessionId, name: name)));
      return;
    }
    showAgentWakeSettings(context,
        client: widget.client, owner: widget.sessionId, name: name);
  }

  void _openRecurring() {
    // Desktop: the shell owns the panes and opens this as a right-pane readout,
    // the same shape Tasks/Lanes/Checkpoints get. A session cannot toggle a pane
    // itself, so it asks. Null on mobile, where there are no panes and the
    // drawer is the right shape for a phone.
    final toPane = widget.onOpenScheduled;
    if (toPane != null && ShellPanelScope.maybeOf(context) == null) {
      toPane();
      return;
    }
    presentScreen(context,
        style: PanelStyle.drawer,
        purpose: ShellPanelPurpose.recurring,
        originClient: widget.client,
        originSessionId: widget.sessionId,
        builder: (_, close) => RecurringScreen(
            client: widget.client,
            onClose: close,
            sessionId: widget.sessionId,
            workspace: _state?.workspace));
  }

  void _setApproval(bool manual) {
    final mode = manual ? 'manual' : 'auto';
    final s = _state;
    if (s != null) {
      _setState(() => _state = s.withApprovalMode(mode));
    }
    _send({'kind': 'set_mode', 'value': mode});
    _toast(manual ? 'Approval: ask' : 'Approval: auto');
  }

  void _performMacAction(String action, [String? extra]) {
    final s = _state;
    switch (action) {
      case 'focus_composer':
        _inputFocus.requestFocus();
        return;
      case 'rename':
        _renameCurrent();
        return;
      case 'model':
        _switchModel(_modelChipKey.currentContext ?? context);
        return;
      case 'goal':
        final text = extra?.trim();
        if (text != null && text.isNotEmpty) {
          _send({'kind': 'set_goal', 'value': text});
          _toast('Goal set — the agent will drive toward it');
        } else if (s?.goal?.ongoing ?? false) {
          _cancelGoal();
        } else {
          _editGoal();
        }
        return;
      case 'resume_goal':
        _resumeGoal();
        return;
      case 'lanes':
        _showLanes();
        return;
      case 'handoff':
        if (!_isLead && !widget.readOnly) _showHandOff();
        return;
      case 'files':
        final ws = s?.workspace ?? '';
        final name = lastPathSegment(ws, ifEmpty: 'Files');
        presentScreen(context,
            style: PanelStyle.drawer,
            purpose: ShellPanelPurpose.files,
            originClient: widget.client,
            originSessionId: widget.sessionId,
            maxWidth: 1060,
            maxHeight: 760,
            builder: (_, close) => FileExplorer(
                client: widget.client,
                title: name,
                start: ws.isEmpty ? null : ws,
                onClose: close,
                onOpenFile: widget.onOpenFileTab));
        return;
      case 'shell':
        if (!_isLead) _openTerm();
        return;
      case 'shell_new':
        if (!_isLead) _openTerm(fresh: true);
        return;
      // Called from the SIDEBAR's terminal panel. Creating a shell is the
      // sidebar's job; showing the resulting pane is the shell's. Kept separate
      // from `shell_new` so the sidebar's + does not depend on the pane's own
      // toggle logic.
      case 'shell_create':
        if (!_isLead) _openTerm(fresh: true);
        return;
      // Destroy a shell. Only the sidebar can do this — the pane may only
      // minimize, so a pty is never lost by collapsing a view.
      case 'shell_close':
        if (extra != null && extra.isNotEmpty) _closeTerm(extra);
        return;
      case 'shell_focus':
        // `extra` is the terminal index, from the shell's terminal panel.
        final i = extra == null ? null : int.tryParse(extra);
        if (i != null) _focusTerm(i);
        return;
      case 'processes':
        presentScreen(context,
            style: PanelStyle.drawer,
            purpose: ShellPanelPurpose.processes,
            originClient: widget.client,
            originSessionId: widget.sessionId,
            builder: (_, close) => _activityPanel(close));
        return;
      case 'actions':
        _openActions(_state);
        return;
      case 'autonomy':
        if (_isLead) _openAutonomy();
        return;
      case 'pull_requests':
        final status = _github;
        if (status == null) {
          _toast('Pull requests need the GitHub CLI signed in for this repo');
          return;
        }
        final number = int.tryParse(extra ?? '');
        if (number != null && widget.onShowPullRequests == null) {
          openPullRequest(context,
              client: widget.client,
              session: widget.sessionId,
              status: status,
              number: number);
        } else {
          _openPullRequests();
        }
        return;
      case 'artifacts':
        _openDeliverables();
        return;
      case 'artifact':
        if (extra != null && extra.isNotEmpty) {
          openArtifact(context,
              client: widget.client, session: widget.sessionId, id: extra);
        }
        return;
      case 'task':
        if (extra != null && extra.isNotEmpty) {
          openTaskDetail(context, widget.client, extra);
        }
        return;
      case 'file_changes':
        final events = _state?.events ?? const <Map<String, dynamic>>[];
        final steps = sessionChangeSteps(events);
        final shell = shellChanges(events, fileChanges(steps));
        if (kMobile) {
          Navigator.of(context).push(AppPageRoute<void>(
              builder: (_) => FileChangesScreen(
                  steps: steps, shell: shell, onOpenFile: _openChangedFile)));
        } else {
          presentScreen<void>(context,
              maxWidth: 760,
              maxHeight: 640,
              purpose: ShellPanelPurpose.changes,
              originClient: widget.client,
              originSessionId: widget.sessionId,
              builder: (_, close) => FileChangesScreen(
                  steps: steps, shell: shell, onOpenFile: _openChangedFile));
        }
        return;
      case 'memory':
        if (!kMobile) {
          presentScreen(context,
              style: PanelStyle.drawer,
              maxWidth: 760,
              purpose: ShellPanelPurpose.memory,
              originClient: widget.client,
              originSessionId: widget.sessionId,
              builder: (_, close) => DeskMemoryView(
                  client: widget.client,
                  sessionId: widget.sessionId,
                  workspace: _state?.workspace));
          return;
        }
        presentScreen(context,
            builder: (_, close) => MemoryScreen(
                client: widget.client, embedded: true, onBack: close));
        return;
      case 'recurring':
        _openRecurring();
        return;
      case 'approval':
        _setApproval(extra == 'ask');
        return;
      case 'git':
        presentScreen(context,
            purpose: ShellPanelPurpose.git,
            originClient: widget.client,
            originSessionId: widget.sessionId,
            builder: (_, close) => GitScreen(
                client: widget.client,
                sessionId: widget.sessionId,
                onClose: close));
        return;
      case 'compact':
        _confirmCompact();
        return;
      case 'checkpoints':
        _showCheckpoints();
        return;
      // Rewind / fork from a checkpoint shown in the shell's right pane. The
      // pane sends the id, so the session resolves it against live state rather
      // than the pane holding a stale Checkpoint copy.
      case 'rewind':
        final cp = _checkpointById(extra);
        if (cp != null) _confirmRewind(cp);
        return;
      case 'fork':
        _confirmFork(_checkpointById(extra));
        return;
    }
  }

  Future<void> _loadProviders() async {
    if (_profileProviders.isNotEmpty) return;
    try {
      final cfg = await widget.client.getConfig();
      if (!mounted) return;
      _setState(() => _profileProviders = {
            for (final p in cfg.profiles) p.name: p.provider,
          });
    } catch (_) {}
  }

  /// Same confirm as the desktop shell rail, then back to the home list.
  Future<void> _deleteSession(void Function(VoidCallback) close) async {
    final name = _title.trim().isEmpty ? '(untitled session)' : _title.trim();
    final ok = await confirmAction(
      context,
      title: 'Delete session?',
      body:
          '$name\n\nPermanently removes the conversation. The folder and its files are untouched.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    await _deleteNow(close);
  }

  Future<void> _deleteNow(void Function(VoidCallback) close) async {
    try {
      await widget.client.deleteSession(widget.sessionId);
    } catch (e) {
      if (mounted) toast(context, "Couldn't delete: $e", danger: true);
      return;
    }
    if (!mounted) return;
    close(() {
      final done = widget.onDeleted;
      if (done != null) {
        done();
      } else {
        Navigator.of(context).maybePop();
      }
    });
  }

  void _openActions(HarnessState? s, {BuildContext? anchor}) {
    _loadProviders();
    void run(VoidCallback f) {
      Navigator.pop(context);
      f();
    }

    if (!kMobile && anchor != null) {
      showAnchoredPanel<void>(anchor,
          width: 380,
          maxHeight: 680,
          alignRight: true,
          child: SingleChildScrollView(child: _actionsPanel(s, run)));
      return;
    }
    showAppSheet(context,
        title: 'Actions',
        maxWidth: 420,
        maxHeight: 680,
        child: _actionsPanel(s, run));
  }

  /// The action list, shared by the mobile end-drawer and the pull-up sheet so
  /// the two hosts cannot offer different actions. [run] dismisses the host,
  /// then performs the action.
  Widget _actionsPanel(HarnessState? s, void Function(VoidCallback) run,
      {void Function(VoidCallback)? navigate}) {
    navigate ??= run;
    final ws = s?.workspace ?? '';
    final changeSteps = sessionChangeSteps(s?.events ?? const []);
    final shell = shellChanges(
        s?.events ?? const <Map<String, dynamic>>[], fileChanges(changeSteps));
    final me = _me;
    final agentId = me?.displayAgentId ?? 'snippet';
    final agentName =
        (_meAgentName ?? '').trim().isEmpty ? agentId : _meAgentName!.trim();
    final changedCount = fileChanges(changeSteps).length + shell.length;
    return _SessionActionsPanel(
      session: s,
      page: true,
      ownAgent: agentId,
      ownProfile: widget.profile,
      providers: _profileProviders,
      header: SettingsHero(
        plate: false,
        avatar: AgentMochi(_isLead ? 'lead' : agentId,
            size: Grouped.avatarCharacter),
        name: _title.isEmpty ? 'Session' : _title,
        sub: _isLead
            ? 'Coordinator'
            : [
                agentName,
                if ((me?.branch ?? '').trim().isNotEmpty) me!.branch!.trim(),
                if (changedCount > 0)
                  '$changedCount file${changedCount == 1 ? '' : 's'} changed',
              ].join(' \u00b7 '),
      ),
      onDelete: _isLead ||
              widget.readOnly ||
              _inboxAgentId(widget.sessionId) != null
          ? null
          : () => _deleteSession(run),
      onFork: widget.readOnly || _isLead
          ? null
          : () => run(() => _confirmFork(null)),
      fileChangeCount: changedCount,
      onFileChanges: () => navigate!(() => Navigator.of(context).push(
          AppPageRoute<void>(
              builder: (_) => FileChangesScreen(
                  steps: changeSteps,
                  shell: shell,
                  onOpenFile: _openChangedFile)))),
      hideWorkspace: _isLead,
      hideGoal: _isLead,
      hideCheckpoints: _isLead,
      autoSettle: _isLead || widget.readOnly ? null : !_keepAwake,
      onAutoSettle: _setAutoSettle,
      resumeMode: _isLead || widget.readOnly ? null : _resumeMode,
      onResumeMode: (m) => _setResumeMode(m),
      onAutonomy: _isLead ? () => navigate!(_openAutonomy) : null,
      onWakes: () => run(_openWakes),
      onSetGoal: (text) {
        _send({'kind': 'set_goal', 'value': text});
        _toast('Goal set — the agent will drive toward it');
      },
      onCancelGoal: _cancelGoal,
      onResumeGoal: _resumeGoal,
      onLanes: () => navigate!(_showLanes),
      onGiveWork: _giveWork,
      hideShell: _isLead,
      onTerm: () => run(_openTerm),
      onGit: () => navigate!(() => presentScreen(context,
          builder: (_, close) => GitScreen(
              client: widget.client,
              sessionId: widget.sessionId,
              onClose: close))),
      onDeliverables: () => navigate!(_openDeliverables),
      onPullRequests:
          _github == null ? null : () => navigate!(_openPullRequests),
      onFiles: () => navigate!(() {
        final name = lastPathSegment(ws, ifEmpty: 'Files');
        presentScreen(context,
            maxWidth: 1060,
            maxHeight: 760,
            builder: (_, close) => FileExplorer(
                client: widget.client,
                title: name,
                start: ws.isEmpty ? null : ws,
                onClose: close,
                onOpenFile: widget.onOpenFileTab));
      }),
      onProcesses: () => navigate!(() => presentScreen(context,
          style: PanelStyle.drawer,
          purpose: ShellPanelPurpose.processes,
          originClient: widget.client,
          originSessionId: widget.sessionId,
          builder: (_, close) => _activityPanel(close))),
      onRecurring: () => run(_openRecurring),
      onTasks: kMobile && _isLead
          ? () => run(() => openMobileTasksPage(context, widget.client))
          : null,
      onCompact: () => run(_confirmCompact),
      onCheckpoints: () => navigate!(_showCheckpoints),
      onHandOff: _isLead ||
              widget.readOnly ||
              _inboxAgentId(widget.sessionId) != null
          ? null
          : () => run(_showHandOff),
      onMemory: () => navigate!(() => presentScreen(context,
          builder: (_, close) => MemoryScreen(
              client: widget.client, embedded: true, onBack: close))),
    );
  }

  // Lead's panel is the agent panel; it has no session rail.
  bool _railVisible(double columnWidth) =>
      !kMobile &&
      !widget.readOnly &&
      !_isLead &&
      _inboxAgentId(widget.sessionId) == null &&
      columnWidth >= kSessionRailMinColumn;

  void _cycleResumeMode() {
    const order = ['ask', 'lean', 'full'];
    final next = order[(order.indexOf(_resumeMode) + 1) % order.length];
    _setResumeMode(next);
  }

  void _openProcesses() => presentScreen(context,
      style: PanelStyle.drawer,
      purpose: ShellPanelPurpose.processes,
      originClient: widget.client,
      originSessionId: widget.sessionId,
      builder: (_, close) => _activityPanel(close));

  /// Desktop shows tool steps plus background jobs; the phone keeps jobs only.
  Widget _activityPanel(VoidCallback close) => kMobile
      ? ProcessesScreen(
          client: widget.client, sessionId: widget.sessionId, onClose: close)
      : SessionActivityPanel(
          client: widget.client,
          sessionId: widget.sessionId,
          runs: _activityRuns,
          live: _activityLive,
          onClose: close,
          onOpenFile: _openChangedFile);

  /// The chat pane: 960 of text, centred, the same with or without the session
  /// panel so opening it never reflows the transcript. Alone (phone,
  /// read-only, inbox) it takes the full width.
  Widget _chatPane(bool paired, Widget child) {
    final hasPanel =
        !widget.readOnly && _inboxAgentId(widget.sessionId) == null;
    if (kMobile || (!paired && !hasPanel)) return Expanded(child: child);
    // The transcript keeps a 20px gutter inside the pane.
    // Chat centres in the space left of the panel; the panel itself hugs the edge under its toggle.
    return Expanded(
        child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Flexible(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960 + 40),
                  child: child)),
        ]));
  }

  Widget _passThrough(Widget w) => w;

  /// Below the pair width the panel opens as a floating card under the header
  /// button and closes on a click away.
  Widget _floatingRail(HarnessState? s, BoxConstraints column) {
    if (_railVisible(column.maxWidth) ||
        _isLead ||
        widget.readOnly ||
        _inboxAgentId(widget.sessionId) != null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: sessionRailFloating,
      builder: (_, open, __) {
        if (!open) return const SizedBox.shrink();
        // Drops in from under the header rather than popping into place.
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
                offset: Offset(0, (1 - t) * -8), child: child),
          ),
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => sessionRailFloating.value = false,
              ),
            ),
            Positioned(
              right: kSessionRailEdgeInset,
              top: 8,
              child: _sessionRail(s, floating: true),
            ),
          ]),
        );
      },
    );
  }

  Widget _sessionRail(HarnessState? s,
      {bool floating = false, double? column}) {
    final mc = _isLead;
    final open = widget.onOpenRightPanel;
    final goalOn = s?.goal?.ongoing ?? false;
    final profile = (_currentProfile ?? widget.profile ?? '').trim();
    if (!_railProvidersAsked) {
      _railProvidersAsked = true;
      _loadProviders();
    }
    return SessionRail(
      client: widget.client,
      sessionId: widget.sessionId,
      state: s,
      isLead: mc,
      floating: floating,
      columnWidth: column,
      agentId: _me?.displayAgentId,
      profileLabel: profile.isEmpty ? 'Default model' : profile,
      resumeMode: _resumeMode,
      github: _github != null,
      onModel: () => _switchModel(_modelChipKey.currentContext ?? context),
      onWakes: _openWakes,
      onGoal: () {
        if (goalOn) {
          s!.goal!.paused ? _resumeGoal() : _cancelGoal();
        } else {
          _setGoal();
        }
      },
      onCycleResume: _cycleResumeMode,
      onAnswer:
          mc ? (v) => _sendDecision({'kind': 'answer', 'value': v}) : null,
      onAutonomy: mc ? _openAutonomy : null,
      onChanges: mc
          ? null
          : () => open != null
              ? open('changes')
              : widget.onOpenWorkspace != null
                  ? widget.onOpenWorkspace!()
                  : _performMacAction('file_changes'),
      onOpenDiff: widget.onOpenDiffTab,
      onOpenFile: _openWorkspaceFile,
      onFiles: mc
          ? null
          : () => widget.onOpenWorkspace != null
              ? widget.onOpenWorkspace!()
              : _performMacAction('files'),
      onGit: mc ? null : () => _performMacAction('git'),
      onPullRequests: _github == null ? null : _openPullRequests,
      onLanes: () => open != null ? open('lanes') : _showLanes(),
      onProcesses: mc ? null : _openProcesses,
      onShell: mc ? null : _openTerm,
      onCheckpoints: () =>
          open != null ? open('checkpoints') : _showCheckpoints(),
      onMemory: () => _performMacAction('memory'),
      onOpenTask: (id) => openTaskDetail(context, widget.client, id),
      onHandOff:
          mc || widget.readOnly || _inboxAgentId(widget.sessionId) != null
              ? null
              : _showHandOff,
      onFork: mc || widget.readOnly ? null : () => _confirmFork(null),
      onCompact: _confirmCompact,
      onDeliverables: mc ? null : _openDeliverables,
      onRecurring: _openRecurring,
      onDelete: mc || widget.readOnly || _inboxAgentId(widget.sessionId) != null
          ? null
          : () => _deleteSession((f) => f()),
      onSubmitGoal: mc || widget.readOnly ? null : _submitGoal,
      handOffPanel:
          mc || widget.readOnly || _inboxAgentId(widget.sessionId) != null
              ? null
              : (close) => SessionHandOffPanel(
                    client: widget.client,
                    sessionId: widget.sessionId,
                    list: true,
                    onHandedOff: (name, pending) {
                      close();
                      _toast(pending
                          ? 'Hands to $name after this turn'
                          : 'Handed to $name');
                    },
                  ),
      onForkNow: mc || widget.readOnly ? null : () => _forkFrom(null),
      onRewindNow: _rewindTo,
      onCompactNow: _compactNow,
      onDeleteNow:
          mc || widget.readOnly || _inboxAgentId(widget.sessionId) != null
              ? null
              : () => _deleteNow((f) => f()),
      onResumeGoal: mc || widget.readOnly ? null : _resumeGoal,
      onEndGoal: mc || widget.readOnly ? null : _cancelGoal,
      providers: _profileProviders,
      ownProfile: profile.isEmpty ? null : profile,
      ownAgent: _me?.displayAgentId ?? 'snippet',
      headerActions: mc ? _mcHeaderActions(s) : null,
      headerChips: mc ? null : _workspaceChips(s),
    );
  }

  /// Desktop: connection state as a quiet strip on top of the composer.
  Widget _deskConnectionNotice() {
    final stuck = _connError == _SessionScreenState._unreachable;
    final q = _outbox.length;
    final text = [
      stuck ? _SessionScreenState._unreachable : 'Reconnecting',
      if (q > 0) '$q message${q == 1 ? '' : 's'} will send on reconnect',
    ].join(' · ');
    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        margin: EdgeInsets.only(bottom: S.s8),
        padding: EdgeInsets.fromLTRB(S.s12, S.s6, S.s6, S.s6),
        decoration: BoxDecoration(
          color: stuck ? AppColors.dangerBg : AppColors.surface2,
          borderRadius: BorderRadius.circular(R.of(10)),
        ),
        child: Row(children: [
          StatusDot(
              status: stuck ? 'offline' : 'checking',
              size: 6,
              color: stuck ? AppColors.danger : AppColors.fg3),
          SizedBox(width: S.s8),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12.5, color: AppColors.fg2)),
          ),
          HoverSurface(
            radius: 6,
            onTap: _retryNow,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: 3),
              child: Text('Retry now',
                  style: sans(12,
                      weight: W.label,
                      color: stuck ? AppColors.danger : AppColors.fg2)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _disconnectedBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: S.s16, vertical: S.of(10)),
      decoration: BoxDecoration(color: AppColors.surface2),
      child: Row(children: [
        AppIcon('wifi-off', size: 15, color: AppColors.run),
        SizedBox(width: S.of(9)),
        Expanded(
            child: Text(
                _outbox.isEmpty
                    ? (_connError ?? 'Disconnected')
                    : '${_connError ?? 'Disconnected'} · ${_outbox.length} message${_outbox.length == 1 ? '' : 's'} will send on reconnect',
                style: sans(12, height: 1.3, color: AppColors.fg1))),
        TapDetector(
          onTap: _retryNow,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Retry now',
                style: sans(12, weight: W.label, color: AppColors.fg1)),
          ]),
        ),
      ]),
    );
  }

  void _retryNow() {
    HapticFeedback.selectionClick();
    _reconnectAttempt = 0;
    if (_connError != null) {
      _setState(() => _connError = _SessionScreenState._reconnecting);
    }
    _connect();
  }

  Widget _mobileConnectionLine() {
    final stuck = _connError == _SessionScreenState._unreachable;
    final queued = _outbox.length;
    final text = [
      stuck ? _SessionScreenState._unreachable : 'Reconnecting',
      if (queued > 0) '$queued queued',
      if (stuck) 'tap to retry',
    ].join(' · ');
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        StatusDot(
            status: stuck ? 'offline' : 'checking',
            size: 6,
            color: stuck ? AppColors.danger : AppColors.fg2),
        SizedBox(width: S.s6),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg3)),
        ),
      ]),
    );
  }

  /// Open the full-screen actions panel (slides in from the right).
  ///
  /// Dismisses the keyboard first: the panel is a navigation surface, and a
  /// composer keyboard left open underneath makes the slide look broken.
  void _openActionsDrawer(HarnessState? s) {
    FocusManager.instance.primaryFocus?.unfocus();
    _loadProviders();
    _scaffoldKey.currentState?.openEndDrawer();
  }

  /// The phone's action list as a FULL-SCREEN panel entering from the right.
  ///
  /// Full width rather than a 320px drawer: the actions carry descriptions and
  /// expandable forms (goal, lanes), which a narrow drawer squeezes into
  /// ellipsis. The right edge distinguishes it from the Chats panel on the left.
  Widget _actionsDrawer(HarnessState? s) {
    // Closing the drawer dismisses the host, then runs the action — the drawer
    // is not a route, so `Navigator.pop` (what the sheet uses) would not close
    // it and the action would fire behind an open panel.
    void run(VoidCallback f) {
      _scaffoldKey.currentState?.closeEndDrawer();
      f();
    }

    return Drawer(
      width: MediaQuery.sizeOf(context).width,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Grouped.gutter, 8, Grouped.gutter, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GroupedCircleButton(
                    icon: 'x',
                    tooltip: 'Close',
                    onTap: () => _scaffoldKey.currentState?.closeEndDrawer()),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(Grouped.gutter, 0, Grouped.gutter,
                    S.of(28) + MediaQuery.paddingOf(context).bottom),
                child: _actionsPanel(s, run, navigate: (action) => action()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Desktop floating header: the session's actions at the right over the
  // transcript. The tab strip carries the title; the phone keeps its own chrome.
  bool get _deskHeader => !kMobile && !widget.readOnly;

  // No header row on desktop; the window bar carries status and actions.
  double get _deskHeaderHeight => 8;

  /// With the session panel open, its header holds the actions; the chat
  /// header carries them only when the panel is hidden or does not fit, and
  /// then a panel button shows it (docked, or floating when it cannot dock).
  Widget _deskHeaderBar(HarnessState? s, bool running, {bool rail = false}) {
    return ListenableBuilder(
      listenable: Listenable.merge([sessionRailCollapsed, sessionRailFloating]),
      builder: (_, __) {
        final docked = rail && !sessionRailCollapsed.value;
        final floating =
            !rail && !_isLead && sessionRailFloating.value;
        return _deskHeaderBarWith(s, running,
            actions: !docked && !floating);
      },
    );
  }

  Widget _deskHeaderBarWith(HarnessState? s, bool running,
      {required bool actions}) {
    final mc = _isLead;
    final status = s?.pendingQuestion != null
        ? 'needs_you'
        : running
            ? 'running'
            : (s?.status ?? 'idle');
    // Only a wait on the user earns a pill; the sidebar dot shows working.
    final live = status == 'needs_you' || status == 'waiting_for_input';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (live) ...[
        SessionStatusPill(
            status: status,
            startedAt: DateTime.tryParse(s?.turnStartedAt ?? '')),
        Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: AppColors.lineStrong),
      ],
      // Sessions keep their tools in the pane row and the "/" menu.
      if (actions && mc) _mcHeaderActions(s),
    ]);
  }

  Widget _workspaceChips(HarnessState? s) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!kMobile && (s?.workspace ?? '').isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilesChip(
                client: widget.client,
                sessionId: widget.sessionId,
                workspace: s!.workspace,
                onOpenFile: _openWorkspaceFile,
                onOpenWorkspace: widget.onOpenWorkspace,
              ),
            ),
            GitChip(
              client: widget.client,
              sessionId: widget.sessionId,
              turnStatus: s.status,
              githubReady: _github != null,
              onOpenDiff: widget.onOpenDiffTab,
              onOpenWorkspace: widget.onOpenWorkspace,
            ),
          ],
        ],
      );

  /// Opens the session panel, docked or floating, whichever fits.
  void _showPanel() {
    if (sessionRailCollapsed.value) setSessionRailCollapsed(false);
    sessionRailFloating.value = true;
  }

  Widget _mcHeaderActions(HarnessState? s) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.deskActions?.call() ??
              Builder(
                builder: (ctx) => IconBtn('more-horizontal',
                    size: 30,
                    iconSize: 15,
                    tooltip: 'Lead actions',
                    onTap: () => _openActions(s, anchor: ctx)),
              ),
        ],
      );
}

/// Status dot for a terminal tab: ok while alive, faint once ended, accent
/// while the pty is still starting.
Color termDotColor({required bool alive, required bool ended}) => alive
    ? AppColors.ok
    : ended
        ? AppColors.fg4
        : AppColors.accent;

/// One terminal tab's label and status dot.
class TermTab {
  const TermTab(this.title, this.dot);
  final String title;
  final Color dot;
}

/// Phone terminal tabs: a scrolling row of 32px chips.
class MobileTermTabs extends StatelessWidget {
  const MobileTermTabs({
    super.key,
    required this.tabs,
    required this.focus,
    required this.onSelect,
    required this.onRename,
    required this.onClose,
  });

  final List<TermTab> tabs;
  final int focus;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRename;
  final ValueChanged<int> onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, n) => TermTabChip(
          title: tabs[n].title,
          dot: tabs[n].dot,
          selected: n == focus,
          onTap: () => onSelect(n),
          onRename: () => onRename(n),
          onClose: () => onClose(n),
        ),
      ),
    );
  }
}

/// Desktop dock header: 28px tab chips, then +, then the dock's own actions
/// on the right.
class TermDockBar extends StatelessWidget {
  const TermDockBar({
    super.key,
    required this.tabs,
    required this.focus,
    required this.onSelect,
    required this.onRename,
    required this.onClose,
    required this.onNew,
    this.actions = const [],
  });

  final List<TermTab> tabs;
  final int focus;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRename;
  final ValueChanged<int> onClose;
  final VoidCallback onNew;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(children: [
        // A Flexible beside a Spacer only gets half the row; Expanded pins actions to the edge.
        Expanded(
          child: Row(children: [
            Flexible(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                shrinkWrap: true,
                padding: const EdgeInsets.only(left: 12, right: 4),
                itemCount: tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (_, n) => _DockTab(
                  title: tabs[n].title,
                  dot: tabs[n].dot,
                  selected: n == focus,
                  onTap: () => onSelect(n),
                  onRename: () => onRename(n),
                  onClose: () => onClose(n),
                ),
              ),
            ),
            IconBtn('plus',
                size: 26, iconSize: 13, tooltip: 'New terminal', onTap: onNew),
          ]),
        ),
        ...actions,
        const SizedBox(width: 8),
      ]),
    );
  }
}

/// Phone terminal tab: a 32px chip with a status dot. Long-press renames; the
/// active chip carries the close control.
class TermTabChip extends StatelessWidget {
  const TermTabChip({
    super.key,
    required this.title,
    required this.dot,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onClose,
  });

  final String title;
  final Color dot;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final on = selected;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(R.of(10)),
      side: BorderSide(color: on ? AppColors.border2 : AppColors.border),
    );
    return Material(
      color: on ? AppColors.surface2 : AppColors.surface1,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        onLongPress: onRename,
        child: Padding(
          padding: EdgeInsets.only(left: 12, right: on ? 4 : 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(title,
                style: sans(13, color: on ? AppColors.fg1 : AppColors.fg3)),
            if (on)
              TapDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                  child: AppIcon('x', size: 12, color: AppColors.fg4),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Desktop dock tab: a 28px chip in the header row with a status dot and a
/// close control. Double-click or right-click renames.
class _DockTab extends StatefulWidget {
  const _DockTab({
    required this.title,
    required this.dot,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onClose,
  });

  final String title;
  final Color dot;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onClose;

  @override
  State<_DockTab> createState() => _DockTabState();
}

class _DockTabState extends State<_DockTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.selected;
    final fg = on || _hover ? AppColors.fg1 : AppColors.fg3;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTap: widget.onRename,
        onDoubleTap: widget.onRename,
        child: Tooltip(
          message: 'Double-click to rename',
          waitDuration: const Duration(milliseconds: 700),
          child: Center(
            child: Container(
              height: 28,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: on
                    ? AppColors.surface2
                    : _hover
                        ? AppColors.surface1
                        : null,
                borderRadius: BorderRadius.circular(R.of(8)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: widget.dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(widget.title, style: sans(12, color: fg)),
                const SizedBox(width: 6),
                TapDetector(
                  onTap: widget.onClose,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: Center(
                      child: AppIcon('x', size: 12, color: AppColors.fg4),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header pill text while lanes run: the batch since the oldest running lane.
String? lanePillLabel(List<LaneInfo> lanes) {
  final running = lanes.where((l) => l.running).toList();
  if (running.isEmpty) return null;
  final since = running
      .map((l) => l.startedAt)
      .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  final batch = lanes
      .where(
          (l) => l.status != 'cancelled' && l.startedAt.compareTo(since) >= 0)
      .toList();
  final done = batch.where((l) => l.status == 'completed').length;
  final n = batch.length;
  final head = n == 1 ? '1 lane' : '$n lanes';
  return done == 0 ? head : '$head · $done done';
}
