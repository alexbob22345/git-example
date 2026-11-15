import 'package:change_gui/src/dmrc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a desktop section when the file is empty', () {
    expect(upsertDmrcSession('', 'xfce'), '[Desktop]\nSession=xfce\n');
  });

  test('replaces Session and keeps other keys and sections', () {
    const existing = '''
[Desktop]
Language=en_US.utf8
Session = gnome

[Other]
Session=keep
''';
    final updated = upsertDmrcSession(existing, 'plasma');
    expect(updated, contains('Language=en_US.utf8'));
    expect(updated, contains('Session=plasma'));
    expect(updated, isNot(contains('Session = gnome')));
    expect(readDmrcSessionId(updated), 'plasma');
    expect(updated.split('[Other]\n').last, 'Session=keep\n');
  });

  test('keeps CRLF and appends Session when the section has none', () {
    const existing = '[Desktop]\r\nLanguage=en_US.utf8\r\n';
    final updated = upsertDmrcSession(existing, 'ubuntu-xorg');
    expect(
      updated,
      '[Desktop]\r\nLanguage=en_US.utf8\r\nSession=ubuntu-xorg\r\n',
    );
    expect(readDmrcSessionId(updated), 'ubuntu-xorg');
  });

  test('refuses an unsafe session id', () {
    expect(() => upsertDmrcSession('', '../evil'), throwsFormatException);
  });
}
