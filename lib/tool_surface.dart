/// Grouped daemon tools (`process`, `message`, `web`, ...) lowered to the
/// internal tool they run, mirroring the daemon's `surface::lower`, so every
/// preview and detail view keys off one set of names.
library;

// action -> (internal tool, fixed action or null, op passes through as action)
const Map<String, Map<String, (String, String?, bool)>> _surfaces = {
  'web': {
    'search': ('web_search', null, false),
    'read': ('web_read', null, false),
  },
  'process': {
    'list': ('manage_process', 'list', false),
    'log': ('manage_process', 'log', false),
    'wait': ('manage_process', 'wait', false),
    'kill': ('manage_process', 'kill', false),
    'watch': ('monitor', 'add', false),
    'unwatch': ('monitor', 'remove', false),
    'watches': ('monitor', 'list', false),
  },
  'present': {
    'show': ('present_file', null, false),
    'share': ('share_artifact', null, false),
  },
  'delegate': {
    'run': ('delegate_task', null, false),
    'cancel': ('cancel_delegated_task', null, false),
    'profiles': ('list_profiles', null, false),
  },
  'skill': {
    'search': ('search_skills', null, false),
    'load': ('skill', null, false),
  },
  'message': {
    'send': ('send_agent_message', null, false),
    'post': ('post_chat', null, false),
    'task': ('post_task_coordination', null, false),
    'group': ('group_thread', null, true),
    'push': ('ping_user', null, false),
  },
  'read': {
    'chats': ('chats', null, false),
    'thread': ('read_chat', null, false),
    'agent': ('read_agent_thread', null, false),
    'room': ('read_coordination_thread', null, false),
    'inbox': ('read_agent_inbox', null, false),
    'board': ('read_coordination_board', null, false),
    'groups': ('group_thread', 'list', false),
    'group': ('group_thread', 'read', false),
    'session': ('inspect_session', null, false),
    'sessions': ('list_sessions', null, false),
  },
  'task': {
    'report': ('report_mission_task', null, false),
    'ledger': ('task_ledger', null, false),
    'update': ('update_task_state', null, false),
    'pass': ('pass_turn', null, false),
    'invite': ('invite_task_agent', null, false),
    'review': ('submit_review', null, false),
    'answer': ('answer_session', null, false),
    'follow_up': ('file_follow_up_task', null, false),
    'hand_off': ('hand_off_session', null, false),
    'inspect': ('inspect_task', null, false),
    'board': ('view_task_board', null, false),
    'claim': ('claim_and_dispatch_task', null, false),
    'decline': ('decline_task', null, false),
    'start': ('start_task', null, false),
  },
  'wake': {
    'once': ('schedule_wake', null, false),
    'every': ('wake_schedule', null, true),
    'watch': ('watch', null, true),
    'automation': ('automated_wakes', null, true),
  },
  'tasks': {
    'create': ('create_mission_task', null, false),
    'update': ('update_mission_task', null, false),
    'list': ('list_mission_tasks', null, false),
    'cancel': ('cancel_mission_task', null, false),
    'retry': ('retry_mission_task', null, false),
    'assign': ('assign_task_agent', null, false),
    'transfer': ('transfer_mission_task_lease', null, false),
    'inspect': ('inspect_task', null, false),
    'ledger': ('task_ledger', null, false),
    'review': ('submit_review', null, false),
    'report': ('report_mission_task', null, false),
  },
  'goals': {
    'create': ('create_goal', null, false),
    'plan': ('plan_goal', null, false),
    'replan': ('replan_goal', null, false),
    'update': ('update_goal', null, false),
    'list': ('list_goals', null, false),
    'close': ('close_goal', null, false),
  },
  'sessions': {
    'create': ('create_mission_session', null, false),
    'deliver': ('deliver_to_session', null, false),
    'stop': ('stop_session', null, false),
    'state': ('session_state', null, false),
    'clean_up': ('clean_up_sessions', null, true),
    'answer': ('answer_worker', null, false),
  },
};

String _base(String tool) => tool.startsWith('mcp__')
    ? tool.substring(tool.lastIndexOf('__') + 2)
    : tool;

/// The internal tool and arguments behind a grouped call, or null when the
/// call is not a grouped one.
(String, Map<String, dynamic>)? lowerToolCall(String tool, dynamic args) {
  final surface = _surfaces[_base(tool)];
  if (surface == null || args is! Map) return null;
  final act = surface[args['action']?.toString()];
  if (act == null) return null;
  final (internal, fixed, op) = act;
  final lowered = Map<String, dynamic>.from(args)..remove('action');
  if (fixed != null) {
    lowered['action'] = fixed;
  } else if (op && lowered.containsKey('op')) {
    lowered['action'] = lowered.remove('op');
  }
  return (internal, lowered);
}

bool _isSurface(String tool) => _surfaces.containsKey(_base(tool));

/// Lowers grouped tool calls in [events] in place. A result carries only the
/// grouped name, so it takes the internal name of the nearest earlier call
/// with that grouped name, looking back into [prior] when needed.
List<Map<String, dynamic>> lowerToolEvents(List<Map<String, dynamic>> events,
    {List<Map<String, dynamic>> prior = const []}) {
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    final name = e['tool_name'];
    if (name is! String) continue;
    // Newer daemons name the internal tool and keep the visible one aside.
    final visible = e['surface_tool'];
    if (!_isSurface(name)) {
      if (e['kind'] == 'tool_call' && visible is String) {
        final lowered = lowerToolCall(visible, e['arguments']);
        if (lowered != null && lowered.$1 == name) {
          events[i] = {...e, 'arguments': lowered.$2};
        }
      }
      continue;
    }
    if (e['kind'] == 'tool_call') {
      final lowered = lowerToolCall(name, e['arguments']);
      if (lowered == null) continue;
      events[i] = {
        ...e,
        'tool_name': lowered.$1,
        'arguments': lowered.$2,
        'surface': name,
      };
    } else {
      final internal = _callBefore(name, events, i) ??
          _callBefore(name, prior, prior.length);
      if (internal != null) events[i] = {...e, 'tool_name': internal};
    }
  }
  return events;
}

String? _callBefore(
    String surface, List<Map<String, dynamic>> events, int end) {
  for (var j = end - 1; j >= 0 && j >= end - 400; j--) {
    final e = events[j];
    if (e['kind'] == 'tool_call' && e['surface'] == surface) {
      return e['tool_name'] as String?;
    }
  }
  return null;
}
