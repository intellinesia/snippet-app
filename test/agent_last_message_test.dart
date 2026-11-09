import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/crew_status.dart';
import 'package:snippet/models.dart';

CoordinationAgent _agent(Map<String, dynamic>? last) => CoordinationAgent.fromJson({
      'id': 'x-scout',
      'display_name': 'X Scout',
      'handle': 'x_scout',
      if (last != null) 'last_message': last,
    });

void main() {
  test('an idle agent shows its last message instead of what it finished', () {
    final e = deriveCrew([_agent({'text': 'Draft is ready.', 'from': 'agent', 'at': '2026-11-08T10:00:00Z'})], const []).single;
    expect(e.line, 'Draft is ready.');
  });

  test('your own last message is marked as yours', () {
    final e = deriveCrew([_agent({'text': 'Check the 320px layout', 'from': 'user'})], const []).single;
    expect(e.line, 'You: Check the 320px layout');
  });

  test('no preview falls back to the old line', () {
    expect(deriveCrew([_agent(null)], const []).single.line, 'Standing by');
    expect(deriveCrew([_agent({'text': '  ', 'from': 'agent'})], const []).single.line, 'Standing by');
  });
}
