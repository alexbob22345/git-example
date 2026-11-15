import 'dart:io';

import 'package:change_gui/src/accounts_service.dart';
import 'package:change_gui/src/desktop_session.dart';
import 'package:change_gui/src/dmrc.dart';
import 'package:change_gui/src/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingAccounts implements AccountsSessionPort {
  String? sessionId;
  SessionType? type;
  bool fail = false;

  @override
  Future<AccountsSessionState?> read() async => null;

  @override
  Future<AccountsWriteResult> write({
    required String sessionId,
    required SessionType type,
  }) async {
    this.sessionId = sessionId;
    this.type = type;
    const path = '/var/lib/AccountsService/users/tester';
    if (fail) {
      return const AccountsWriteResult(
        path: path,
        succeeded: false,
        message: 'Could not update $path for GDM: permission denied.',
      );
    }
    final sessionType = type == SessionType.wayland ? 'wayland' : 'x11';
    return AccountsWriteResult(
      path: path,
      succeeded: true,
      message:
          'Wrote Session=$sessionId, XSession=$sessionId, and '
          'SessionType=$sessionType to $path for GDM.',
    );
  }
}

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

  final accounts = RecordingAccounts();
  var sddmPresent = false;

  FilesystemSessionRepository repository() {
    return FilesystemSessionRepository(
      x11Directories: ['${root.path}/xsessions'],
      waylandDirectories: ['${root.path}/wayland'],
      dmrcPath: '${root.path}/home/.dmrc',
      appStatePath: '${root.path}/config/change_gui/selection.json',
      locale: 'en_US.UTF-8',
      clock: () => DateTime.utc(2026, 11, 15, 18),
      accounts: accounts,
      sddmStateExists: () => sddmPresent,
      sddmStatePath: '${root.path}/sddm/state.conf',
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
    expect(accounts.sessionId, 'xfce');
    expect(accounts.type, SessionType.x11);
    expect(describeSwitch(result), contains('Session=xfce'));
    expect(describeSwitch(result), contains(result.appStatePath));
    expect(describeSwitch(result), contains('for GDM'));
    expect(describeSwitch(result), contains('Log out and back in'));
    expect(describeSwitch(result), contains('You stay signed in'));
    expect(describeSwitch(result), isNot(contains('state.conf')));
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
      accounts: RecordingAccounts(),
      sddmStateExists: () => false,
    );
    final snapshot = await repo.load();
    expect(snapshot.sessions, isEmpty);
  });

  test('a failed GDM update still writes LightDM and names both', () async {
    accounts.fail = true;
    sddmPresent = true;
    final result = await repository().switchTo(
      DesktopSession(
        id: 'xfce',
        name: 'Xfce Session',
        type: SessionType.x11,
        sourcePath: '${root.path}/xsessions/xfce.desktop',
      ),
    );
    final text = describeSwitch(result);
    expect(result.dmrcWritten, isTrue);
    expect(result.accountsUpdated, isFalse);
    expect(text, contains('for LightDM'));
    expect(text, contains('Could not update'));
    expect(text, contains('for GDM'));
    expect(text, contains('Left ${root.path}/sddm/state.conf unchanged'));
    expect(text, contains('Log out and back in'));
  });
}
