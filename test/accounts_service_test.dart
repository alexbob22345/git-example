import 'package:change_gui/src/accounts_service.dart';
import 'package:change_gui/src/accounts_user.dart';
import 'package:change_gui/src/desktop_session.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAccountsBus implements AccountsBus {
  FakeAccountsBus({this.missing = false, this.unknownSessionType = false});

  final bool missing;
  final bool unknownSessionType;
  final calls = <String>[];

  @override
  Future<BusCallResult> call({
    required int uid,
    required String method,
    required String value,
  }) async {
    calls.add('$method=$value uid=$uid');
    if (missing) {
      return const BusCallResult(
        exitCode: 127,
        stdout: '',
        stderr: 'busctl not found',
        executableMissing: true,
      );
    }
    if (unknownSessionType && method == 'SetSessionType') {
      return const BusCallResult(
        exitCode: 1,
        stdout: '',
        stderr: 'Unknown method SetSessionType',
      );
    }
    return const BusCallResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<BusCallResult> getProperty({
    required int uid,
    required String property,
  }) async {
    if (property == 'Session') {
      return const BusCallResult(exitCode: 0, stdout: 's "plasma"', stderr: '');
    }
    return const BusCallResult(exitCode: 0, stdout: 's "wayland"', stderr: '');
  }
}

void main() {
  test('accounts file keeps other keys and sets GDM session fields', () {
    const existing = '''
[User]
Language=en_US.utf8
Session=gnome
Icon=/home/ada/.face

[Other]
Session=keep
''';
    final updated = upsertAccountsUser(
      existing,
      sessionId: 'xfce',
      sessionType: 'x11',
    );
    final fields = readAccountsUser(updated);
    expect(fields.session, 'xfce');
    expect(fields.xSession, 'xfce');
    expect(fields.sessionType, 'x11');
    expect(updated, contains('Language=en_US.utf8'));
    expect(updated, contains('Icon=/home/ada/.face'));
    expect(updated.split('[Other]\n').last, 'Session=keep\n');
  });

  test('busctl and gdbus property strings parse', () {
    expect(parseAccountsProperty('s "xfce"'), 'xfce');
    expect(parseAccountsProperty('s ""'), isNull);
    expect(parseAccountsProperty("('plasma',)"), 'plasma');
    expect(readProcUid('Name:\tapp\nUid:\t1000\t1000\t1000\t1000\n'), 1000);
  });

  test('dbus update sets Session, XSession, and SessionType', () async {
    final bus = FakeAccountsBus();
    final port = DbusAccountsSessionPort(bus: bus, uid: 1000, username: 'ada');
    final result = await port.write(
      sessionId: 'plasma',
      type: SessionType.wayland,
    );
    expect(result.succeeded, isTrue);
    expect(result.path, '/var/lib/AccountsService/users/ada');
    expect(result.message, contains('SessionType=wayland'));
    expect(bus.calls, [
      'SetSession=plasma uid=1000',
      'SetXSession=plasma uid=1000',
      'SetSessionType=wayland uid=1000',
    ]);
    final state = await port.read();
    expect(state?.session, 'plasma');
    expect(state?.sessionType, 'wayland');
  });

  test(
    'an older AccountsService without SetSessionType still records the session',
    () async {
      final bus = FakeAccountsBus(unknownSessionType: true);
      final port = DbusAccountsSessionPort(
        bus: bus,
        uid: 1000,
        username: 'ada',
      );
      final result = await port.write(sessionId: 'xfce', type: SessionType.x11);
      expect(result.succeeded, isTrue);
      expect(result.message, contains('XSession=xfce'));
      expect(result.message, isNot(contains('SessionType=')));
    },
  );

  test('without a bus, the user file is written directly', () async {
    String? written;
    final port = DbusAccountsSessionPort(
      bus: FakeAccountsBus(missing: true),
      uid: 1000,
      username: 'ada',
      readFile: (path) async => '[User]\nLanguage=en\n',
      writeFile: (path, contents) async => written = contents,
    );
    final result = await port.write(sessionId: 'xfce', type: SessionType.x11);
    expect(result.succeeded, isTrue);
    expect(written, contains('Session=xfce'));
    expect(written, contains('XSession=xfce'));
    expect(written, contains('SessionType=x11'));
    expect(written, contains('Language=en'));
  });
}
