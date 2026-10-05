import 'package:cotizi/invite_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le lien partagé contient le code', () {
    expect(inviteUrl('PAJ8R3'), 'https://zidane123-web.github.io/j/?c=PAJ8R3');
    expect(
      inviteMessage('Rejoins le groupe.', 'PAJ8R3'),
      contains('https://zidane123-web.github.io/j/?c=PAJ8R3'),
    );
  });

  test('code lu depuis le lien de l\'application ou de la page web', () {
    expect(inviteCodeFrom(Uri.parse('cotizi://join?c=paj8r3')), 'PAJ8R3');
    expect(
      inviteCodeFrom(Uri.parse('https://zidane123-web.github.io/j/?c=PAJ8R3')),
      'PAJ8R3',
    );
  });

  test('liens étrangers ou sans code ignorés', () {
    expect(inviteCodeFrom(Uri.parse('cotizi://join')), isNull);
    expect(
      inviteCodeFrom(Uri.parse('https://exemple.com/autre?c=ABC123')),
      isNull,
    );
    expect(inviteCodeFrom(Uri.parse('cotizi://autre?c=ABC123')), isNull);
  });
}
