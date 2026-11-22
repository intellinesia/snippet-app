part of 'session.dart';

extension _SessionScreenTranscriptExt on _SessionScreenState {
  List<Widget> _transcript(List<Map<String, dynamic>> events) {
    _dockRun = null;
    _lastUserRowKey = null;
    final out = <Widget>[];
    final activityRuns = <ActivityRun>[];
    ToolBatch? activityLive;
    Map<String, dynamic>? pending;
    final run = <Widget>[]; // consecutive dense tool rows
    String? runStartKey;
    String? pendingKey;
    List<({String path, String caption})>? openFiles;
    var openFilesAt = -1;
    final newestArtifact = <String, int>{};
    for (final e in events) {
      if (e['kind'] != 'artifact_presented') continue;
      final id = _s(e['id']);
      final v = (e['version'] as num?)?.toInt() ?? 1;
      if (v >= (newestArtifact[id] ?? 0)) newestArtifact[id] = v;
    }

    // Items are spaced here, not per widget, so every pair of neighbours
    // gets the same gap.
    Widget spaced(Widget child) => Padding(
        padding: EdgeInsets.symmetric(vertical: transcriptGap / 2),
        child: child);

    void addEvent(String key, Widget child) {
      out.add(KeyedSubtree(
        key: ValueKey(key),
        child: spaced(child),
      ));
    }

    // Index of the event being laid out, and where the open run began.
    var curIdx = 0;
    int? runFirst;

    void addToolRow(Widget child, String key) {
      runStartKey ??= key;
      runFirst ??= curIdx;
      run.add(child);
    }

    DenseToolRow toolRow(String key,
        {required String tool,
        dynamic args,
        dynamic result,
        int? startMs,
        int? endMs}) {
      final open = _openToolRows.contains(key);
      return DenseToolRow(
        key: ValueKey('tool-row-$key'),
        tool: tool,
        args: args,
        result: result,
        startMs: startMs,
        endMs: endMs,
        open: open,
        onOpenChanged: (next) {
          if (!mounted) return;
          _setState(() {
            if (next) {
              _openToolRows.add(key);
            } else {
              _openToolRows.remove(key);
            }
            _transcriptDirty = true;
          });
        },
      );
    }

    void flushPending(String fallbackKey) {
      final p = pending;
      if (p != null) {
        final name = _s(p['tool_name']);
        final k = pendingKey ?? fallbackKey;
        addToolRow(
            toolRow(k, tool: name, args: p['arguments'], startMs: _eventMs(p)),
            k);
        pending = null;
        pendingKey = null;
      }
    }

    void endTools(String fallbackKey) {
      flushPending(fallbackKey);
      if (run.isEmpty) return;
      final start = runStartKey ?? fallbackKey;
      final isSessionRunning = _state?.status == 'running';
      // A call with no result followed by later events was cut off, not live.
      final running = isSessionRunning &&
          curIdx >= events.length &&
          run.any((w) => w is DenseToolRow && w.pending);
      final toolKey = 'transcript-tools-$start';
      final took = transcriptRunDuration(events, runFirst ?? curIdx, curIdx);
      if (kMobile) {
        final steps = [
          for (final w in run.whereType<DenseToolRow>())
            ToolStep(tool: w.tool, args: w.args, result: w.result),
        ];
        if (steps.isNotEmpty) {
          // The newest run stays live between calls too, while the model thinks.
          final live = isSessionRunning && curIdx >= events.length;
          if (live) {
            int? startMs;
            for (var i = (runFirst ?? curIdx) - 1;
                i >= 0 && startMs == null;
                i--) {
              startMs = _eventMs(events[i]);
            }
            final startedAt = startMs != null
                ? DateTime.fromMillisecondsSinceEpoch(startMs)
                : _dockSeen.putIfAbsent(toolKey, DateTime.now);
            final batch = ToolBatch(steps, running: true);
            _dockRun = DockRun(batch, startedAt);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _dockBatch.value = batch;
            });
          } else {
            out.add(KeyedSubtree(
              key: ValueKey(toolKey),
              child: spaced(ActivityPill(
                agentId: _me?.displayAgentId ?? 'snippet',
                steps: steps,
                took: took,
                onOpen: (i) => showActivitySheet(context,
                    client: widget.client,
                    batch: ValueNotifier<ToolBatch>(ToolBatch(steps)),
                    initial: i,
                    took: took,
                    onOpenFile: _openChangedFile),
              )),
            ));
          }
          run.clear();
          runStartKey = null;
          runFirst = null;
          return;
        }
      }
      // As on mobile, the newest run stays live between calls while the turn runs.
      final live =
          running || (!kMobile && isSessionRunning && curIdx >= events.length);
      if (!kMobile) {
        final steps = [
          for (final w in run.whereType<DenseToolRow>())
            ToolStep(
                tool: w.tool,
                args: w.args,
                result: w.result,
                startMs: w.startMs,
                endMs: w.endMs),
        ];
        if (steps.isNotEmpty) {
          if (live) {
            activityLive = ToolBatch(steps, running: true);
          } else {
            activityRuns.add(ActivityRun(toolKey, steps, took));
          }
        }
      }
      final open = _toolRunOpen[toolKey] ?? false;
      out.add(KeyedSubtree(
        key: ValueKey(toolKey),
        child: spaced(CollapsedActivity(
          List.of(run),
          running: live,
          took: took,
          open: open,
          onOpenChanged: (nextOpen) {
            if (!mounted) return;
            _setState(() {
              _toolRunOpen[toolKey] = nextOpen;
              // Rebuild cached transcript so CollapsedActivity reflects open immediately.
              _transcriptDirty = true;
            });
          },
        )),
      ));
      run.clear();
      runStartKey = null;
      runFirst = null;
    }

    String? laneTitleFor(String agentId) {
      if (!agentId.startsWith('lane ')) return null;
      final id = agentId.substring(5).trim();
      for (final l in _state?.lanes ?? const <LaneInfo>[]) {
        if (l.id == id) return l.title;
      }
      return null;
    }

    final superseded = supersededAmbientTurns([
      for (final e in events)
        if (e['kind'] == 'user_input' || e['kind'] == 'steer') _s(e['text']),
    ]);

    final quietWakes = quietWakeRuns(events);
    // A plan is drawn once, at its latest update, not once per update.
    final lastPlan = events.lastIndexWhere((e) => e['kind'] == 'plan_updated');
    final staleStalls = supersededStalls(events);

    final resultOf = <int, int>{};
    final pairedResults = <int>{};
    {
      final open = <String, List<int>>{};
      for (var i = 0; i < events.length; i++) {
        final kind = events[i]['kind'];
        final name = _s(events[i]['tool_name']);
        if (kind == 'tool_call') {
          (open[name] ??= []).add(i);
        } else if (kind == 'tool_result') {
          final waiting = open[name];
          if (waiting != null && waiting.isNotEmpty) {
            final call = waiting.removeAt(0);
            if (i > call + 1) {
              resultOf[call] = i;
              pairedResults.add(i);
            }
          }
        }
      }
    }

    for (var idx = 0; idx < events.length; idx++) {
      curIdx = idx;
      final e = events[idx];
      // Keyed by absolute index, which a reconnect snapshot or an older page
      // never shifts, so rows keep their state instead of remounting.
      final key = 'transcript-event-${_transcriptStart + idx}';
      final abs = 'event-${_transcriptStart + idx}';
      final k = e['kind'] as String? ?? '';
      final quietRun = quietWakes[idx];
      if (quietRun != null) {
        endTools(key);
        addEvent(key, QuietWakesRow(run: quietRun));
        idx = quietRun.end;
        continue;
      }
      switch (k) {
        case 'tool_call':
          flushPending(key);
          // Meta-tools render via their own events (note → note, ask_user →
          // user_question, delegate_task → lane_spawned). Skip their generic tool
          // lines so they don't double up.
          if (_isSpeakTool(_s(e['tool_name']))) {
            endTools(key);
            final args = e['arguments'];
            final spoken = args is Map ? _s(args['text']).trim() : '';
            if (spoken.isNotEmpty) {
              addEvent(
                  key,
                  SpeakCard(
                      text: spoken,
                      expecting: args is Map ? _s(args['expecting']) : ''));
            }
            break;
          }
          if (_isMetaTool(_s(e['tool_name']))) break;
          final paired = resultOf[idx];
          if (paired != null) {
            final r = events[paired];
            final shared = _sharedArtifact(_s(e['tool_name']), r['result']);
            if (shared != null) {
              endTools(key);
              addEvent(key, shared);
              break;
            }
            addToolRow(
                toolRow(abs,
                    tool: _s(e['tool_name']),
                    args: e['arguments'],
                    result: r['result'],
                    startMs: _eventMs(e),
                    endMs: _eventMs(r)),
                abs);
            break;
          }
          pending = e;
          pendingKey = abs;
        case 'tool_result':
          if (pairedResults.contains(idx)) break;
          {
            final p = pending;
            final shared =
                _sharedArtifact(_s((p ?? e)['tool_name']), e['result']);
            if (shared != null) {
              pending = null;
              pendingKey = null;
              endTools(key);
              addEvent(key, shared);
            } else if (p != null) {
              final k = pendingKey ?? abs;
              addToolRow(
                  toolRow(k,
                      tool: _s(p['tool_name']),
                      args: p['arguments'],
                      result: e['result'],
                      startMs: _eventMs(p),
                      endMs: _eventMs(e)),
                  k);
              pending = null;
              pendingKey = null;
            } else {
              final name = _s(e['tool_name']);
              if (_isMetaTool(name) || _isSpeakTool(name)) break;
              addToolRow(
                  toolRow(abs,
                      tool: name,
                      result: e['result']),
                  abs);
            }
          }
        case 'user_input':
        case 'steer':
          endTools(key);
          final text = _s(e['text']);
          // Answers are already shown on the question card — don't also
          // render them as a user bubble.
          if (_looksLikeQuestionAnswer(text)) break;
          final envelope = parseMissionEnvelope(text);
          if (envelope != null) {
            if (staleStalls.contains(idx)) {
              addEvent(
                  key,
                  NoteLine('Stalled, later updated: ${envelope.title}',
                      icon: 'alert-triangle'));
              break;
            }
            addEvent(key, MissionEnvelopeCard(envelope: envelope));
            break;
          }
          final round = parseAutonomousRound(text);
          if (round != null) {
            addEvent(key, AutonomousRoundCard(round: round));
            break;
          }
          final workerQuestion = parseWorkerQuestion(text);
          if (workerQuestion != null) {
            addEvent(key, WorkerQuestionCard(question: workerQuestion));
            break;
          }
          final board = parseBoardMessage(text);
          if (board != null) {
            addEvent(key, BoardMessageCard(message: board));
            break;
          }
          final direct = parseDirectMessage(text);
          if (direct != null) {
            // Your own plain message reads as your bubble, not a card.
            if (direct.fromLabel == 'you' &&
                !direct.isReply &&
                !direct.urgent &&
                parseTaskOffer(direct.body) == null &&
                direct.body.trim().isNotEmpty) {
              _lastUserRowKey = key;
              addEvent(
                  key,
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Bubble(
                          mine: true,
                          text: direct.body.trim(),
                          client: widget.client)));
              break;
            }
            addEvent(key, DirectMessageCard(message: direct));
            break;
          }
          final group = parseGroupMessage(text);
          if (group != null) {
            addEvent(key, GroupMessageCard(message: group));
            break;
          }
          final reply = parseCoordinationReply(text);
          if (reply != null) {
            addEvent(key, DirectMessageCard(message: reply));
            break;
          }
          final watchEnvelope = parseWatchEnvelope(text);
          if (watchEnvelope != null) {
            addEvent(key, WatchEnvelopeCard(watch: watchEnvelope));
            break;
          }
          final wakeNote = parseWakeNote(text);
          if (wakeNote != null) {
            addEvent(key, WakeNoteCard(note: wakeNote));
            break;
          }
          final parent = parseParentMessage(text);
          if (parent != null) {
            addEvent(key, ParentMessageCard(body: parent));
            break;
          }
          if (isAmbientResume(text)) {
            addEvent(key, const NoteLine('Resumed after background noise'));
            break;
          }
          final routingNote = parseRoutingNote(text);
          if (routingNote != null) {
            final prevSwitched =
                idx > 0 && events[idx - 1]['kind'] == 'profile_switched';
            if (!prevSwitched) {
              addEvent(key, NoteLine(routingNote, icon: 'transfer'));
            }
            break;
          }
          if (text.trimLeft().startsWith('<ambient_context_alert')) {
            addEvent(
                key,
                const NoteLine(
                    'Voice classifier flagged out-of-context speech'));
            break;
          }
          if (text.trimLeft().startsWith('<ambient_check_in')) {
            addEvent(key, const NoteLine('Checked recent microphone activity'));
            break;
          }
          final ambient = parseAmbientTurn(text);
          if (ambient != null) {
            if (ambient.ids.isNotEmpty &&
                ambient.ids.every(superseded.contains)) {
              break;
            }
            addEvent(
                key,
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: AmbientTurnCard(turn: ambient)));
            break;
          }
          final assignment = parseAssignmentEnvelope(text);
          if (assignment != null) {
            addEvent(key, AssignmentCard(assignment: assignment));
            break;
          }
          final notice = parseSystemNotice(text);
          if (notice != null) {
            addEvent(key, SystemNoticeLine(notice: notice));
            break;
          }
          final userBubble =
              Bubble(mine: true, text: text, client: widget.client);
          _lastUserRowKey = key;
          addEvent(
              key,
              KeyedSubtree(
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: userBubble),
              ));
        case 'assistant_text':
          endTools(key);
          var reply = _s(e['text']).trim();
          if (idx + 1 < events.length &&
              events[idx + 1]['kind'] == 'model_error' &&
              _s(events[idx + 1]['message']).trim() == reply) {
            break;
          }
          // Always keep SpeakCard ("Said aloud" voice bubble) visible; if this
          // assistant_text merely repeats what a SpeakCard in the same turn
          // already spoke, strip or skip the duplicate text on assistant_text.
          for (var j = idx - 1; j >= 0; j--) {
            final jk = events[j]['kind'] as String? ?? '';
            if (jk == 'user_input' || jk == 'steer') break;
            if (jk == 'tool_call' && _isSpeakTool(_s(events[j]['tool_name']))) {
              final args = events[j]['arguments'];
              final spoken = args is Map ? _s(args['text']).trim() : '';
              if (spoken.isNotEmpty) {
                if (reply == spoken) {
                  reply = '';
                  break;
                } else if (reply.startsWith(spoken)) {
                  reply = reply.substring(spoken.length).trimLeft();
                }
              }
            }
          }
          if (reply.isEmpty) break;
          addEvent(
              key,
              Padding(
                  padding: EdgeInsets.zero,
                  child: e['quiet'] == true
                      ? QuietAside(text: reply)
                      : Bubble(mine: false, text: reply)));
        case 'agent_message':
          endTools(key);
          final voiceNote = e['outbound'] == true
              ? null
              : voiceClassifierNote(_s(e['agent_id']), _s(e['body']));
          if (voiceNote != null) {
            addEvent(key, NoteLine(voiceNote));
            break;
          }
          ensureAgentNames(widget.client);
          final from = _s(e['agent_id']);
          if (from.startsWith('lane ')) {
            // A lane's run of notes folds into one card, with the parent's
            // reply right after them inside it.
            final notes = <LaneNote>[];
            Map<String, dynamic>? reply;
            var j = idx;
            if (e['outbound'] == true) {
              reply = e;
            } else {
              while (j < events.length &&
                  events[j]['kind'] == 'agent_message' &&
                  _s(events[j]['agent_id']) == from &&
                  events[j]['outbound'] != true) {
                notes.add(LaneNote(
                    body: _s(events[j]['body']),
                    at: events[j]['at'] ?? events[j]['created_at']));
                j++;
              }
              idx = j - 1;
              if (j < events.length &&
                  events[j]['kind'] == 'agent_message' &&
                  _s(events[j]['agent_id']) == from &&
                  events[j]['outbound'] == true) {
                reply = events[j];
                idx = j;
              }
            }
            // The daemon names lanes `lane «title»`; older events use the id.
            var laneId = from.substring(5).trim();
            if (laneId.length > 1 &&
                laneId.startsWith('«') &&
                laneId.endsWith('»')) {
              laneId = laneId.substring(1, laneId.length - 1).trim();
            }
            LaneInfo? lane;
            for (final l in _state?.lanes ?? const <LaneInfo>[]) {
              if (l.id == laneId || l.title.trim() == laneId) lane = l;
            }
            final given = lane?.title.trim() ?? '';
            final waiting = reply == null &&
                notes.isNotEmpty &&
                notes.last.body.contains('?') &&
                lane?.status == 'running';
            final open = lane;
            addEvent(
                key,
                LaneMessageCard(
                  laneTitle: given.isNotEmpty ? given : laneId,
                  notes: notes,
                  reply: reply == null ? null : _s(reply['body']),
                  replyAt: reply?['at'] ?? reply?['created_at'],
                  meId: _me?.displayAgentId,
                  meName: _meAgentName,
                  waiting: waiting,
                  onOpenLane: open == null
                      ? null
                      : () => openLaneView(context, open,
                          client: widget.client,
                          sessionId: widget.sessionId,
                          liveLanes: () => _state?.lanes ?? const <LaneInfo>[]),
                ));
            break;
          }
          addEvent(
              key,
              AgentMessageCard(
                agentId: _s(e['agent_id']),
                body: _s(e['body']),
                outbound: e['outbound'] == true,
                laneTitle: laneTitleFor(_s(e['agent_id'])),
                meId: _me?.displayAgentId,
                meName: _meAgentName,
                time: formatEventTime(e['at'] ?? e['created_at']),
              ));
        case 'model_error':
          endTools(key);
          final msg = _s(e['message']).trim();
          var count = 1;
          var look = idx + 1;
          while (look < events.length) {
            final nk = events[look]['kind'] as String? ?? '';
            if (nk == 'assistant_text' &&
                _s(events[look]['text']).trim() == msg) {
              look++;
              continue;
            }
            if (nk == 'model_error' &&
                _s(events[look]['message']).trim() == msg) {
              count++;
              idx = look;
              look++;
              continue;
            }
            break;
          }
          final firstLine = msg.split('\n').first.trim();
          final shortMsg = firstLine.length > 90
              ? '${firstLine.substring(0, 89)}\u2026'
              : firstLine;
          addEvent(
              key,
              Builder(
                builder: (ctx) => SignalRow(
                  icon: 'alert-triangle',
                  tone: SignalTone.danger,
                  text: '${shortMsg.isEmpty ? 'Model error' : shortMsg}'
                      '${count > 1 ? ' \u00d7$count' : ''}',
                  time: formatEventTime(e['at'] ?? e['created_at']),
                  action: 'Details',
                  actionTone: SignalTone.danger,
                  onAction: () =>
                      showSignalDetails(ctx, title: 'Model error', body: msg),
                ),
              ));
        case 'profile_switched':
          endTools(key);
          addEvent(
              key,
              SignalRow(
                icon: 'transfer',
                tone: SignalTone.run,
                text: '**${prettyProfile(_s(e['from']))}** hit its limit'
                    ' \u00b7 now on **${prettyProfile(_s(e['to']))}**',
                time: formatEventTime(e['at'] ?? e['created_at']),
              ));
        case 'session_handoff':
          endTools(key);
          ensureAgentNames(widget.client);
          addEvent(key, HandoffNotice(event: e));
        case 'task_dispatched':
          endTools(key);
          ensureAgentNames(widget.client);
          final by = _s(e['by']);
          final title = _s(e['title']).trim();
          addEvent(
              key,
              AgentNamesBuilder(
                builder: (_, names) => SignalRow(
                  icon: 'send',
                  tone: SignalTone.accent,
                  leading: by.isEmpty
                      ? null
                      : AgentMochi(by.replaceFirst('agent:', ''), size: 20),
                  text: '**${agentDisplayName(by, names)}** dispatched '
                      '${title.isEmpty ? 'a task' : '**$title**'}',
                  time: formatEventTime(e['at'] ?? e['created_at']),
                ),
              ));
        case 'limit_wait':
          endTools(key);
          final at = (e['resets_at'] as num?)?.toInt() ?? 0;
          addEvent(
              key,
              SignalRow(
                icon: 'clock',
                tone: SignalTone.run,
                text: at > 0
                    ? 'Waiting for **${prettyProfile(_s(e['profile']))}** to reset at ${limitLabel(at)}'
                    : 'Waiting for **${prettyProfile(_s(e['profile']))}** to reset',
                time: formatEventTime(e['at'] ?? e['created_at']),
              ));
        case 'limit_reached':
          endTools(key);
          const later = {
            'profile_switched',
            'limit_wait',
            'user_input',
            'steer',
            'assistant_text',
          };
          addEvent(
              key,
              LimitCard(
                client: widget.client,
                session: widget.sessionId,
                profile: _s(e['profile']),
                resetsAt: (e['resets_at'] as num?)?.toInt() ?? 0,
                options: [
                  for (final o in (e['options'] as List? ?? const [])) '$o'
                ],
                settled:
                    events.skip(idx + 1).any((x) => later.contains(x['kind'])),
              ));
        case 'invalid_tool_call':
          endTools(key);
          addEvent(
              key,
              NoteLine(_s(e['error']),
                  error: true, label: 'Invalid call · ${_s(e['tool_name'])}'));
        case 'plan_updated':
          endTools(key);
          final steps =
              (e['steps'] as List? ?? const []).whereType<Map>().toList();
          if (steps.isNotEmpty && idx == lastPlan) {
            // Clear air around it, so it never reads as a step of the
            // activity cards on either side.
            addEvent(
                key,
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: PlanProgressCard(
                      steps: steps, explanation: _s(e['explanation'])),
                ));
          }
        case 'system_decision':
          // Watch lines are part of the work, so they join the open fold.
          if (const {'watch_added', 'watch_removed', 'file_watch'}
              .contains(_s(e['step']))) {
            flushPending(key);
            addToolRow(
                SystemRow(
                    key: ValueKey('watch-$key'),
                    step: _s(e['step']),
                    reasoning: _s(e['reasoning']),
                    time: formatEventTime(e['at'] ?? e['created_at'])),
                key);
            break;
          }
          endTools(key);
          // Don't render "interrupted" decisions — just noise in the chat.
          if (_s(e['step']) == 'interrupted') break;
          // One quiet line per run of restart notices.
          if (_isRestartNote(_s(e['reasoning']))) {
            var prev = idx - 1;
            while (prev >= 0 &&
                const {'model_error', 'status'}
                    .contains(events[prev]['kind'])) {
              prev--;
            }
            if (prev >= 0 &&
                events[prev]['kind'] == 'system_decision' &&
                _isRestartNote(_s(events[prev]['reasoning']))) {
              break;
            }
            addEvent(
                key,
                const NoteLine('Snippet restarted mid-turn; the next message '
                    'picks it up'));
            break;
          }
          addEvent(
              key,
              SystemRow(
                  step: _s(e['step']),
                  reasoning: _s(e['reasoning']),
                  time: formatEventTime(e['at'] ?? e['created_at'])));
        case 'turn_changes':
          endTools(key);
          if (isDedicatedMcSession(widget.sessionId)) break;
          addEvent(
              key,
              TurnChangesCard(
                event: e,
                onOpenFile: _openChangedFile,
              ));
        case 'file_presented':
          endTools(key);
          final file = (path: _s(e['path']), caption: _s(e['caption']));
          final group = openFiles;
          if (group != null && openFilesAt == out.length) {
            group.add(file);
            break;
          }
          final files = [file];
          openFiles = files;
          addEvent(
              key,
              Padding(
                padding: EdgeInsets.symmetric(vertical: S.s6),
                child: PresentedFiles(
                  client: widget.client,
                  files: files,
                  onOpenFileTab: widget.onOpenFileTab,
                ),
              ));
          openFilesAt = out.length;
        case 'artifact_presented':
          endTools(key);
          final artifactId = _s(e['id']);
          final artifactVersion = (e['version'] as num?)?.toInt() ?? 1;
          final artifactKind = _s(e['artifact_kind']);
          final display = e['display'] as String?;
          addEvent(
              key,
              Padding(
                padding: EdgeInsets.symmetric(vertical: S.s6),
                child: artifactVersion == newestArtifact[artifactId] &&
                        artifactShowsInline(artifactKind, display)
                    ? ArtifactInline(
                        key: ValueKey(
                            'artifact-inline-$artifactId-$artifactVersion'),
                        client: widget.client,
                        session: widget.sessionId,
                        id: artifactId,
                        version: artifactVersion,
                        title: _s(e['title']),
                        kind: artifactKind,
                        caption: _s(e['caption']),
                      )
                    : ArtifactRow(
                        client: widget.client,
                        session: widget.sessionId,
                        id: artifactId,
                        version: artifactVersion,
                        title: _s(e['title']),
                        kind: artifactKind,
                        caption: _s(e['caption']),
                      ),
              ));
        case 'lane_spawned':
        case 'lane_cancelled':
        case 'lane_completed':
          break; // lanes live in the header pill and the Lanes board
        case 'user_question':
          endTools(key);
          String? answer;
          final qi = events.indexOf(e);
          for (var j = qi + 1; j < events.length; j++) {
            final n = events[j];
            if (n['kind'] == 'user_question') break;
            if (n['kind'] == 'user_input' || n['kind'] == 'steer') {
              final t = _s(n['text']);
              if (t.trim().isNotEmpty) {
                answer = t;
                break;
              }
            }
          }
          // The open question is already the answer bar under the transcript;
          // it joins the record once answered.
          final laterQuestion =
              events.skip(qi + 1).any((n) => n['kind'] == 'user_question');
          if (answer == null && !laterQuestion && _questionOpen) break;
          addEvent(key, _QuestionRecord(e, answer: answer));
        case 'approval_request':
          break; // shown by the approval bar
        case 'decision':
          endTools(key);
          final line = _decisionLine(e);
          if (line != null && line.isNotEmpty) {
            addEvent(key, NoteLine(line));
          }
        default:
          break;
      }
    }
    // Trailing tool_call/tool_result events stay in `run` until a later
    // user/assistant message would flush them. Without this, live tools
    // remain invisible until the next chat message.
    curIdx = events.length;
    endTools('transcript-tools-tail');
    _stripLive = activityLive != null;
    // Coordination rows go LAST: they are the most recent thing to happen to
    // this session's agent, and they read as a live footer under the work.
    for (var i = 0; i < _agentEvents.length; i++) {
      out.add(_agentEventRow(_agentEvents[i], i));
    }
    if (!kMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Only notify on change: the panel listens, and this runs every build.
        final cur = _activityRuns.value;
        if (cur.length != activityRuns.length ||
            (cur.isNotEmpty && cur.last.key != activityRuns.last.key)) {
          _activityRuns.value = activityRuns;
        }
        final was = _activityLive.value;
        if ((was == null) != (activityLive == null) ||
            (activityLive != null &&
                was!.steps.length != activityLive!.steps.length)) {
          _activityLive.value = activityLive;
        }
      });
    }
    return out;
  }

  String _s(dynamic v) => v?.toString() ?? '';

  String? _decisionLine(Map<String, dynamic> e) {
    final outcome = _s(e['outcome']).trim();
    if (outcome.isEmpty) return null;
    final request = _s(e['request']).trim();
    final byRaw = _s(e['by']).trim();
    final actor = switch (byRaw) {
      '' || 'human' => 'You',
      'mission-control' || 'mission_control' => 'Mission Control',
      _ => byRaw,
    };
    final at = (e['at'] as num?)?.toInt() ?? 0;
    final time = at > 0
        ? () {
            final dt = DateTime.fromMillisecondsSinceEpoch(at * 1000).toLocal();
            return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
          }()
        : '';
    final rawSummary = _s(e['summary']).trim();
    final cleanedSummary = rawSummary.isEmpty
        ? _s(e['tool_name']).trim()
        : ApprovalSummary.parse(rawSummary)
            .shownCommand
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final answer = _s(e['answer']).replaceAll(RegExp(r'\s+'), ' ').trim();
    final rule = _s(e['rule']).trim();
    final head = switch (outcome) {
      _ when byRaw == 'rule' => 'Allowed by rule',
      'approved' when rule.isNotEmpty => '$actor approved · always for $rule',
      'approved' => '$actor approved',
      'approved_all' => '$actor approved all',
      'denied' => '$actor denied',
      'answered' =>
        answer.isEmpty ? '$actor answered' : '$actor answered: $answer',
      'skipped' => '$actor skipped the question',
      'outdated' =>
        request == 'question' ? 'Question outdated' : 'Approval outdated',
      _ => '$actor $outcome',
    };
    final parts = <String>[
      head,
      if (outcome != 'answered' &&
          outcome != 'skipped' &&
          cleanedSummary.isNotEmpty)
        cleanedSummary,
      if (time.isNotEmpty) time,
    ];
    return parts.join(' · ');
  }

  /// Live thought stays until this turn produces a tool/action the user can see.
  bool _turnHasVisibleAction(List<Map<String, dynamic>> events) {
    for (var i = events.length - 1; i >= 0; i--) {
      switch (events[i]['kind'] as String? ?? '') {
        case 'user_input':
        case 'steer':
          return false;
        case 'tool_call':
        case 'tool_result':
        case 'invalid_tool_call':
        case 'plan_updated':
        case 'file_presented':
        case 'artifact_presented':
        case 'user_question':
        case 'approval_request':
        case 'assistant_text':
          return true;
      }
    }
    return false;
  }

  Widget? _sharedArtifact(String tool, dynamic result) {
    if (toolBaseName(tool) != 'share_artifact') return null;
    dynamic decoded = result;
    if (result is String) {
      try {
        decoded = jsonDecode(result);
      } catch (_) {
        return null;
      }
    }
    final data = ToolStep(tool: tool, result: decoded).data;
    final artifact = data?['artifact'];
    if (artifact is! Map || _s(artifact['id']).isEmpty) return null;
    final session = _s(artifact['session']);
    return SharedArtifactLine(
      client: widget.client,
      session: session.isEmpty ? widget.sessionId : session,
      id: _s(artifact['id']),
      version: (artifact['version'] as num?)?.toInt() ?? 1,
      title: _s(artifact['title']),
      kind: _s(artifact['kind']),
      url: _s(artifact['url']),
      to: _s(data?['to']),
    );
  }

  // Meta-tools have dedicated event rendering, so their generic tool lines are skipped.
  bool _isSpeakTool(String n) => n == 'speak' || n.endsWith('__speak');

  bool _isMetaTool(String raw) {
    final n = toolBaseName(raw);
    return n == 'update_plan' ||
        n == 'ask_user' ||
        n == 'delegate_task' ||
        n == 'cancel_delegated_task' ||
        n == 'complete_goal' ||
        n == 'monitor' ||
        n == 'present_file';
  }

  Future<void> _switchModel([BuildContext? anchor]) async {
    ServerConfig cfg;
    try {
      cfg = await widget.client.getConfig();
    } catch (e) {
      _toast('$e');
      return;
    }
    if (!mounted) return;
    if (cfg.profiles.isEmpty) {
      _toast('No inference profiles');
      return;
    }
    final current = _modelLabel;
    final picked = await showAppMenu<String>(
      context,
      anchor: anchor ?? context,
      verticalAnchor: _composerCardKey.currentContext,
      minWidth: 260,
      maxWidth: 360,
      items: [
        appMenuHeading<String>('Inference profile'),
        appMenuRow<String>(
          value: '',
          icon: 'info',
          label: _modelPin != null
              ? 'Pinned to $_modelPin'
              : _modelFollowing != null
                  ? "Following $_modelFollowing's profile"
                  : 'Following the default model',
          description: 'Picking a profile pins it to this session',
          enabled: false,
        ),
        for (final p in cfg.profiles)
          appMenuRow<String>(
            value: p.name,
            icon: 'provider:${p.provider}',
            label: p.name,
            description: '${p.provider} · ${p.model}',
            selected: p.name == current,
          ),
      ],
    );
    if (picked == null || picked.isEmpty || picked == current) return;
    final before = _currentProfile;
    _setState(() {
      _currentProfile = picked;
      _modelPin = picked;
      _modelFollowing = null;
    });
    try {
      await widget.client.setSessionModel(widget.sessionId, picked);
      if (mounted) {
        _loadModel();
        _connect();
      }
    } catch (e) {
      if (mounted) _setState(() => _currentProfile = before);
      _toast('$e');
    }
  }

  void _showLanes() {
    if ((_state?.lanes ?? const <LaneInfo>[]).isEmpty) return;
    presentScreen(
      context,
      style: PanelStyle.drawer,
      purpose: ShellPanelPurpose.lanes,
      originClient: widget.client,
      originSessionId: widget.sessionId,
      builder: (_, close) => LanesScreen(
        liveLanes: () => _state?.lanes ?? const <LaneInfo>[],
        onClose: close,
        client: widget.client,
        sessionId: widget.sessionId,
        sessionTitle: _title,
        sessionAgentId: _me?.displayAgentId,
        sessionAgentName: _meAgentName,
      ),
    );
  }

  /// Message an agent from THIS session.
  ///
  /// The message carries this session as its origin, so the agent knows which
  /// session to reply in and which session to request dispatch on. Nothing here
  /// creates work: dispatching belongs to Mission Control.
  Future<void> _giveWork() async {
    final sent = await showAgentWorkSheet(
      context,
      client: widget.client,
      sessionId: widget.sessionId,
      workspaceLabel: _state?.workspace,
    );
    if (sent && mounted) {
      _toast('Sent — the agent replies in this session');
    }
  }

  void _showCheckpoints() {
    final s = _state;
    if (s == null) return;
    final events = s.events;
    final steps = sessionChangeSteps(events);
    final shell = shellChanges(events, fileChanges(steps));
    Widget panel({required bool embedded}) => SessionCheckpointsPanel(
          client: widget.client,
          sessionId: widget.sessionId,
          checkpoints: s.checkpoints.reversed.toList(),
          embedded: embedded,
          onRewind: _confirmRewind,
          onFork: (c) => _confirmFork(c, sheet: true),
          below: embedded
              ? FileChangesSection(
                  steps: steps, shell: shell, onOpenFile: _openChangedFile)
              : null,
        );
    if (kMobile) {
      Navigator.of(context).push(AppPageRoute<void>(
          builder: (_) => Scaffold(
                backgroundColor: AppColors.paneBg,
                body: SafeArea(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const MobileBackBar(title: 'Checkpoints'),
                        Expanded(child: panel(embedded: false)),
                      ]),
                ),
              )));
    } else {
      presentScreen(context,
          style: PanelStyle.drawer,
          purpose: ShellPanelPurpose.checkpoints,
          originClient: widget.client,
          originSessionId: widget.sessionId,
          builder: (_, close) => _SessionActionPanel(
              title: 'Checkpoints',
              onClose: close,
              child: panel(embedded: true)));
    }
  }

  /// Resolve a checkpoint id sent from the shell's right pane against live
  /// state, so the pane never holds a stale copy.
  Checkpoint? _checkpointById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final c in _state?.checkpoints ?? const <Checkpoint>[]) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _confirmRewind(Checkpoint c) async {
    final ok = await confirmAction(
      context,
      title: 'Restore workspace?',
      body:
          'This rolls the workspace back to “${c.label.isEmpty ? c.id : c.label}”. Changes after this point are discarded.',
      confirmLabel: 'Restore',
      danger: false,
    );
    if (!ok) return;
    if (mounted) Navigator.pop(context); // close the sheet
    await _rewindTo(c);
  }

  Future<void> _rewindTo(Checkpoint c) async {
    try {
      await widget.client.rewind(widget.sessionId, c.id);
      _toast('Workspace restored');
    } catch (e) {
      _toast('$e');
    }
  }

  // Kept temporarily for compatibility with any in-flight route callbacks; the
  // user-facing fork entry now lives only inside Checkpoints.
  // ignore: unused_element
  void _showForkPoints() {
    final s = _state;
    if (s == null) return;
    final cps = s.checkpoints.reversed.toList();
    showAppSheet(context,
        title: 'Fork conversation',
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s12),
            child: Text(
              'Creates a new session with history up to the point you pick. '
              'This chat is left unchanged. Workspace files are shared.',
              style: sans(12, height: 1.45, color: AppColors.fg3),
            ),
          ),
          if (cps.isEmpty)
            Padding(
              padding: EdgeInsets.all(S.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      'No checkpoints yet — you can still fork the full history.',
                      style: TS.meta()),
                  SizedBox(height: S.s12),
                  Btn('Fork full history',
                      onTap: () => _confirmFork(null, sheet: true)),
                ],
              ),
            )
          else ...[
            Padding(
              padding: EdgeInsets.only(bottom: S.s8),
              child: AppCard(
                padding: EdgeInsets.all(S.of(13)),
                onTap: () => _confirmFork(null, sheet: true),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    child: AppIcon('git-branch',
                        size: 17, color: AppColors.accent),
                  ),
                  SizedBox(width: S.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Full history', style: TS.rowTitle()),
                        SizedBox(height: S.of(3)),
                        Text('Branch everything so far', style: TS.meta()),
                      ],
                    ),
                  ),
                  AppIcon('chevron-right', size: 16, color: AppColors.fg4),
                ]),
              ),
            ),
            ...cps.map((c) => Padding(
                  padding: EdgeInsets.only(bottom: S.s8),
                  child: AppCard(
                    padding: EdgeInsets.all(S.of(13)),
                    onTap: () => _confirmFork(c, sheet: true),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                        child: AppIcon('git-branch',
                            size: 17, color: AppColors.fg3),
                      ),
                      SizedBox(width: S.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.label.isEmpty ? c.id : c.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TS.rowTitle()),
                            SizedBox(height: S.of(3)),
                            Text(formatCheckpointDate(c.createdAt),
                                style: TS.meta()),
                          ],
                        ),
                      ),
                      AppIcon('chevron-right', size: 16, color: AppColors.fg4),
                    ]),
                  ),
                )),
          ],
        ]));
  }

  Future<void> _confirmFork(Checkpoint? c, {bool sheet = false}) async {
    final label =
        c == null ? 'the latest message' : (c.label.isEmpty ? c.id : c.label);
    final events = _state?.events.length ?? 0;
    final fromHere = await showForkSheet(
      context,
      fromLabel: label,
      totalMessages: events > 0 ? events : null,
      origin: c == null ? lastChipOrigin : null,
    );
    lastChipOrigin = null;
    if (fromHere == null || !mounted) return;
    if (sheet) Navigator.pop(context);
    await _forkFrom(fromHere ? c : null);
  }

  /// Fork at [cut], or at the latest message when null, and open the fork.
  Future<void> _forkFrom(Checkpoint? cut) async {
    final events = _state?.events.length ?? 0;
    try {
      final result = await widget.client.forkSession(
        widget.sessionId,
        checkpoint: cut?.id,
        eventIndex: cut == null && events > 0 ? events - 1 : null,
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
}

extension _SessionActivityExt on _SessionScreenState {
  void _openLiveActivity(int? index) {
    final run = _dockRun;
    showActivitySheet(context,
        client: widget.client,
        batch: _dockBatch,
        initial: index,
        startedAt: run?.startedAt,
        onOpenFile: _openChangedFile);
  }
}

class CollapsedActivity extends StatefulWidget {
  final List<Widget> rows;
  final bool running;
  final Duration? took;
  final bool open;
  final ValueChanged<bool>? onOpenChanged;

  const CollapsedActivity(
    this.rows, {
    super.key,
    this.running = false,
    this.took,
    this.open = false,
    this.onOpenChanged,
  });

  @override
  State<CollapsedActivity> createState() => _CollapsedActivityState();
}

class _CollapsedActivityState extends State<CollapsedActivity> {
  bool _localOpen = false;

  bool get _open => widget.onOpenChanged != null ? widget.open : _localOpen;

  void _toggle() {
    if (widget.onOpenChanged != null) {
      widget.onOpenChanged!(!widget.open);
    } else {
      setState(() => _localOpen = !_localOpen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActivityFold(
        rows: widget.rows,
        running: widget.running,
        took: widget.took,
        open: _open,
        onTap: _toggle);
  }
}

int? _eventMs(Map<String, dynamic> e) {
  final v = e['at_ms'];
  return v is num ? v.toInt() : null;
}

/// Time between the message before a run of steps (events `[from, to)`) and
/// the reply that ends it, from the daemon's `at_ms` write stamps. Without a
/// closing reply it ends at the run's last stamp, so an idle gap before the
/// user's next message is never counted. Null when unstamped or under 1s.
Duration? transcriptRunDuration(
    List<Map<String, dynamic>> events, int from, int to) {
  int? start;
  for (var i = from - 1; i >= 0 && start == null; i--) {
    start = _eventMs(events[i]);
  }
  int? end;
  if (to < events.length && events[to]['kind'] == 'assistant_text') {
    end = _eventMs(events[to]);
  }
  for (var i = to - 1; i >= from && end == null; i--) {
    end = _eventMs(events[i]);
  }
  if (start == null || end == null || end - start < 1000) return null;
  return Duration(milliseconds: end - start);
}

bool _isRestartNote(String s) => s.trim().startsWith('Snippet restarted while');

/// The gap between any two transcript items.
double get transcriptGap => kMobile ? 12 : 10;
