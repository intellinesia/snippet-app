import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/group_messaging.dart';

void main() {
  test('agents mentioning the user with @boss or @human are highlighted', () {
    expect(groupMarkdownWithMentions('@boss pick one', {'argon'}),
        '**@boss** pick one');
    expect(groupMarkdownWithMentions('Need you @human.', {'argon'}),
        'Need you **@human**.');
    expect(groupMarkdownWithMentions('@bossy and me@boss.com', {'argon'}),
        '@bossy and me@boss.com');
  });
}
