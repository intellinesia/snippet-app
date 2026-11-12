/// Where an agent's messages to you go, per kind, and which channels it may use.
class AgentReach {
  const AgentReach({
    required this.policy,
    required this.channels,
    this.inQuietHours = false,
    this.onCall = false,
  });

  /// `question`, `blocker`, `result`, `status` to the ordered channels tried.
  final Map<String, List<String>> policy;
  final Map<String, ReachChannel> channels;
  final bool inQuietHours;
  final bool onCall;

  static const kinds = ['question', 'blocker', 'result', 'status'];
  static const channelOrder = ['push', 'chat', 'voice', 'task_room'];

  /// Chat and the task room always deliver; the service refuses turning them off.
  static bool alwaysOn(String channel) =>
      channel == 'chat' || channel == 'task_room';

  ReachChannel channel(String name) =>
      channels[name] ?? const ReachChannel(enabled: false, quietHours: false);

  factory AgentReach.fromJson(Map<String, dynamic> j) {
    final policy = <String, List<String>>{};
    final p = j['policy'];
    if (p is Map) {
      p.forEach((k, v) {
        if (v is List) policy['$k'] = [for (final c in v) '$c'];
      });
    }
    final channels = <String, ReachChannel>{};
    final c = j['channels'];
    if (c is Map) {
      c.forEach((k, v) {
        if (v is Map) {
          channels['$k'] = ReachChannel(
              enabled: v['enabled'] == true,
              quietHours: v['quiet_hours'] == true);
        }
      });
    }
    return AgentReach(
      policy: policy,
      channels: channels,
      inQuietHours: j['in_quiet_hours'] == true,
      onCall: j['on_call'] == true,
    );
  }
}

class ReachChannel {
  const ReachChannel({required this.enabled, required this.quietHours});
  final bool enabled;

  /// Held during quiet hours rather than sent.
  final bool quietHours;
}

/// The always-on microphone's attention profile on the listening device.
class AmbientTuning {
  const AmbientTuning({
    required this.profile,
    this.expiresAt,
    this.setBy,
    this.reason,
  });

  final String profile;

  /// Unix seconds; null while it stands until changed.
  final int? expiresAt;
  final String? setBy;
  final String? reason;

  static const profiles = [
    'alone',
    'with_people',
    'meeting',
    'demo',
    'driving',
  ];

  factory AmbientTuning.fromJson(Map<String, dynamic> j) {
    final t = j['tuning'] is Map ? (j['tuning'] as Map) : const {};
    return AmbientTuning(
      profile: '${t['profile'] ?? 'alone'}',
      expiresAt: (t['expires_at'] as num?)?.toInt(),
      setBy: j['set_by'] as String?,
      reason: j['reason'] as String?,
    );
  }
}

String reachChannelLabel(String c) => switch (c) {
      'push' => 'Push',
      'chat' => 'Chat',
      'voice' => 'Voice',
      'task_room' => 'Task room',
      _ => c,
    };

String reachKindLabel(String k) => switch (k) {
      'question' => 'Questions',
      'blocker' => 'Blockers',
      'result' => 'Results',
      'status' => 'Status updates',
      _ => k,
    };

String ambientProfileLabel(String p) => switch (p) {
      'alone' => 'Alone',
      'with_people' => 'With people',
      'meeting' => 'Meeting',
      'demo' => 'Demo',
      'driving' => 'Driving',
      'custom' => 'Custom',
      _ => p,
    };

String ambientProfileDetail(String p) => switch (p) {
      'alone' => 'Normal listening',
      'with_people' => 'Only your voice counts; quiet unless addressed',
      'meeting' => 'Nearly silent, notes everything',
      'demo' => 'Forward and quick',
      'driving' => 'Short and hands-free',
      'custom' => 'Knobs set individually',
      _ => '',
    };
