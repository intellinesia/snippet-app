import 'dart:convert';

/// Compact, typed representation of a daemon `/events` message.
/// Unknown kinds are preserved and ignored safely by consumers.
class DeviceEvent {
  final String kind;
  final String action;
  final String session;
  final String status;
  final String queueId;
  final String agent;
  final String state;
  final String detail;
  final int since;
  final Map<String, dynamic>? notification;

  const DeviceEvent({
    required this.kind,
    this.action = '',
    this.session = '',
    this.status = '',
    this.queueId = '',
    this.agent = '',
    this.state = '',
    this.detail = '',
    this.since = 0,
    this.notification,
  });

  factory DeviceEvent.fromJson(Object? raw) {
    if (raw is! Map) return const DeviceEvent(kind: '');
    return DeviceEvent(
      kind: raw['kind']?.toString() ?? '',
      action: raw['action']?.toString() ?? '',
      session: raw['session']?.toString() ?? '',
      status: raw['status']?.toString() ?? '',
      queueId: raw['queue_id']?.toString() ?? '',
      agent: raw['agent']?.toString() ?? '',
      state: raw['state']?.toString() ?? '',
      detail: raw['detail']?.toString() ?? '',
      since: raw['since'] is num ? (raw['since'] as num).toInt() : 0,
      notification: raw['notification'] is Map<String, dynamic>
          ? raw['notification'] as Map<String, dynamic>
          : null,
    );
  }

  static DeviceEvent? decode(Object? message) {
    try {
      final raw = message is String ? jsonDecode(message) : message;
      final event = DeviceEvent.fromJson(raw);
      return event.kind.isEmpty ? null : event;
    } catch (_) {
      return null;
    }
  }
}
