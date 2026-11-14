import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/group_messaging.dart';

void main() {
  test('agents mentioning the user with @human are highlighted', () {
    expect(groupMarkdownWithMentions('@human pick one', {'argon'}),
        '**@human** pick one');
    expect(groupMarkdownWithMentions('Need you @human.', {'argon'}),
        'Need you **@human**.');
    expect(groupMarkdownWithMentions('@humans and me@human.com', {'argon'}),
        '@humans and me@human.com');
  });
}
