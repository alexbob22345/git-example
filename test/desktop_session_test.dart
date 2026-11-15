import 'package:change_gui/src/desktop_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = '''
[Desktop Entry]
Name=Generic Session
Name[fr]=Session FR
Name[en_GB]=British Session
Comment=A desktop
Type=Application
''';

  test('uses the untranslated name when the locale does not match', () {
    final session = parseDesktopSession(
      sample,
      path: '/usr/share/xsessions/generic.desktop',
      type: SessionType.x11,
      locale: 'en_US.UTF-8',
    );
    expect(session, isNotNull);
    expect(session!.id, 'generic');
    expect(session.name, 'Generic Session');
    expect(session.type, SessionType.x11);
    expect(session.comment, 'A desktop');
  });

  test('prefers an exact locale, then the language', () {
    final british = parseDesktopSession(
      sample,
      path: '/usr/share/wayland-sessions/generic.desktop',
      type: SessionType.wayland,
      locale: 'en_GB.UTF-8',
    );
    final french = parseDesktopSession(
      sample,
      path: '/usr/share/xsessions/generic.desktop',
      type: SessionType.x11,
      locale: 'fr_FR.UTF-8',
    );
    expect(british!.name, 'British Session');
    expect(british.type, SessionType.wayland);
    expect(french!.name, 'Session FR');
  });

  test('skips hidden sessions and unsafe file names', () {
    expect(
      parseDesktopSession(
        '[Desktop Entry]\nName=Hidden\nHidden=true\n',
        path: '/usr/share/xsessions/hidden.desktop',
        type: SessionType.x11,
      ),
      isNull,
    );
    expect(
      parseDesktopSession(
        '[Desktop Entry]\nName=Bad\n',
        path: '/usr/share/xsessions/my session.desktop',
        type: SessionType.x11,
      ),
      isNull,
    );
  });

  test('unescapes desktop values', () {
    final session = parseDesktopSession(
      r'[Desktop Entry]'
      '\n'
      r'Name=Hello\sWorld'
      '\n',
      path: '/usr/share/xsessions/hello.desktop',
      type: SessionType.x11,
    );
    expect(session!.name, 'Hello World');
  });
}
