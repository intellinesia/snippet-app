import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session_list_row.dart';
import 'package:snippet/screens/shell_nav.dart';

SessionInfo _s(Map<String, dynamic> extra) => SessionInfo.fromJson({
      'id': 's',
      'folder': '/code/app',
      'conversation': 'default',
      'title': 't',
      'last_active': 0,
      ...extra,
    });

void main() {
  test('an idle session with running lanes counts as busy', () {
    final s = _s({
      'status': 'idle',
      'lanes': {
        'running': 2,
        'items': [
          {'id': 'lane-1', 'title': 'Motion'},
          {'id': 'lane-2', 'title': 'Mockups'},
        ],
      },
    });
    expect(sessionBusy(s), isTrue);
    expect(sessionProgressLabel(s), '2 lanes');
  });

  test('an idle session with no lanes is not busy', () {
    expect(sessionBusy(_s({'status': 'idle'})), isFalse);
  });

  test('progress names the lanes', () {
    final s = _s({
      'status': 'running',
      'lanes': {'running': 1, 'items': []},
    });
    expect(sessionProgressLabel(s), '1 lane');
  });

  test('a running session without lanes has no progress label', () {
    final s = _s({'status': 'running'});
    expect(sessionProgressLabel(s), isNull);
  });
}
