import 'dart:io';

import 'package:change_gui/src/desktop_session.dart';
import 'package:change_gui/src/dmrc.dart';
import 'package:change_gui/src/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('change_gui_test_');
    await Directory('${root.path}/xsessions').create();
    await Directory('${root.path}/wayland').create();
    await File('${root.path}/xsessions/xfce.desktop').writeAsString('''
[Desktop Entry]
Name=Xfce Session
Comment=Use Xfce
Type=Application
''');
    await File('${root.path}/wayland/plasma.desktop').writeAsString('''
[Desktop Entry]
Name=Plasma (Wayland)
Type=Application
''');
    await File('${root.path}/xsessions/hidden.desktop').writeAsString('''
[Desktop Entry]
Name=Hidden
Hidden=true
Type=Application
''');
    await File('${root.path}/xsessions/notes.txt').writeAsString('ignore me');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  FilesystemSessionRepository repository() {
    return FilesystemSessionRepository(
      x11Directories: ['${root.path}/xsessions'],
      waylandDirectories: ['${root.path}/wayland'],
      dmrcPath: '${root.path}/home/.dmrc',
      appStatePath: '${root.path}/config/change_gui/selection.json',
      locale: 'en_US.UTF-8',
      clock: () => DateTime.utc(2026, 11, 15, 18),
    );
  }

  test('scans session directories and skips hidden files', () async {
    final snapshot = await repository().load();
    expect(snapshot.sessions.map((session) => session.selectionKey), [
      'wayland:plasma',
      'x11:xfce',
    ]);
    expect(snapshot.dmrcSessionId, isNull);
    expect(describeSnapshot(snapshot), contains('No Session= entry'));
  });

  test('switch writes dmrc and the app record', () async {
    final repo = repository();
    final snapshot = await repo.load();
    final xfce = snapshot.sessions.firstWhere(
      (session) => session.id == 'xfce',
    );
    final result = await repo.switchTo(xfce);

    expect(result.sessionLine, 'Session=xfce');
    final dmrc = await File(result.dmrcPath).readAsString();
    expect(readDmrcSessionId(dmrc), 'xfce');
    expect(dmrc, contains('[Desktop]'));

    final reloaded = await repo.load();
    expect(reloaded.dmrcSessionId, 'xfce');
    expect(reloaded.saved?.name, 'Xfce Session');
    expect(reloaded.saved?.type, SessionType.x11);
    expect(initialSelection(reloaded)?.id, 'xfce');
    expect(describeSwitch(result), contains('Session=xfce'));
    expect(describeSwitch(result), contains(result.appStatePath));
    expect(describeSwitch(result), contains('You stay signed in'));
  });

  test(
    'switch updates an existing Session without dropping Language',
    () async {
      final dmrc = File('${root.path}/home/.dmrc');
      await dmrc.parent.create(recursive: true);
      await dmrc.writeAsString(
        '[Desktop]\nLanguage=en_US.utf8\nSession=gnome\n',
      );
      final repo = repository();
      final snapshot = await repo.load();
      final plasma = snapshot.sessions.firstWhere(
        (session) => session.id == 'plasma',
      );
      await repo.switchTo(plasma);
      final text = await dmrc.readAsString();
      expect(text, contains('Language=en_US.utf8'));
      expect(readDmrcSessionId(text), 'plasma');
    },
  );

  test('missing session directories are an empty list', () async {
    final repo = FilesystemSessionRepository(
      x11Directories: ['${root.path}/missing-x'],
      waylandDirectories: ['${root.path}/missing-w'],
      dmrcPath: '${root.path}/home/.dmrc',
      appStatePath: '${root.path}/config/change_gui/selection.json',
    );
    final snapshot = await repo.load();
    expect(snapshot.sessions, isEmpty);
  });
}
