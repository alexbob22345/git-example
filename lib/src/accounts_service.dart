import 'dart:async';
import 'dart:io';

import 'accounts_user.dart';
import 'desktop_session.dart';

class AccountsSessionState {
  const AccountsSessionState({
    required this.path,
    this.session,
    this.sessionType,
  });

  final String path;
  final String? session;
  final String? sessionType;
}

class AccountsWriteResult {
  const AccountsWriteResult({
    required this.path,
    required this.succeeded,
    required this.message,
  });

  final String path;
  final bool succeeded;
  final String message;
}

/// Reads and updates the AccountsService user GDM consults at the next login.
abstract class AccountsSessionPort {
  Future<AccountsSessionState?> read();

  Future<AccountsWriteResult> write({
    required String sessionId,
    required SessionType type,
  });
}

class BusCallResult {
  const BusCallResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.executableMissing = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool executableMissing;

  bool get ok => exitCode == 0 && !executableMissing;
}

abstract class AccountsBus {
  Future<BusCallResult> call({
    required int uid,
    required String method,
    required String value,
  });

  Future<BusCallResult> getProperty({
    required int uid,
    required String property,
  });
}

/// `busctl` on the system bus, then `gdbus` when `busctl` is not installed.
class SystemAccountsBus implements AccountsBus {
  @override
  Future<BusCallResult> call({
    required int uid,
    required String method,
    required String value,
  }) {
    final objectPath = '/org/freedesktop/Accounts/User$uid';
    return _run(
      busctl: [
        'call',
        'org.freedesktop.Accounts',
        objectPath,
        'org.freedesktop.Accounts.User',
        method,
        's',
        value,
      ],
      gdbus: [
        'call',
        '--system',
        '--dest',
        'org.freedesktop.Accounts',
        '--object-path',
        objectPath,
        '--method',
        'org.freedesktop.Accounts.User.$method',
        value,
      ],
    );
  }

  @override
  Future<BusCallResult> getProperty({
    required int uid,
    required String property,
  }) {
    final objectPath = '/org/freedesktop/Accounts/User$uid';
    return _run(
      busctl: [
        'get-property',
        'org.freedesktop.Accounts',
        objectPath,
        'org.freedesktop.Accounts.User',
        property,
      ],
      gdbus: [
        'call',
        '--system',
        '--dest',
        'org.freedesktop.Accounts',
        '--object-path',
        objectPath,
        '--method',
        'org.freedesktop.DBus.Properties.Get',
        'org.freedesktop.Accounts.User',
        property,
      ],
    );
  }

  Future<BusCallResult> _run({
    required List<String> busctl,
    required List<String> gdbus,
  }) async {
    final first = await _start('busctl', busctl);
    if (first != null) {
      return first;
    }
    final second = await _start('gdbus', gdbus);
    if (second != null) {
      return second;
    }
    return const BusCallResult(
      exitCode: 127,
      stdout: '',
      stderr: 'busctl and gdbus are not installed.',
      executableMissing: true,
    );
  }

  Future<BusCallResult?> _start(String executable, List<String> args) async {
    try {
      final result = await Process.run(
        executable,
        args,
      ).timeout(const Duration(seconds: 45));
      return BusCallResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
      );
    } on ProcessException {
      return null;
    } on TimeoutException {
      return const BusCallResult(
        exitCode: 124,
        stdout: '',
        stderr: 'timed out waiting for AccountsService.',
      );
    } on IOException {
      return null;
    }
  }
}

class DbusAccountsSessionPort implements AccountsSessionPort {
  DbusAccountsSessionPort({
    AccountsBus? bus,
    this.uid,
    this.username,
    this.readFile,
    this.writeFile,
  }) : bus = bus ?? SystemAccountsBus();

  final AccountsBus bus;
  final int? uid;
  final String? username;
  final Future<String?> Function(String path)? readFile;
  final Future<void> Function(String path, String contents)? writeFile;

  @override
  Future<AccountsSessionState?> read() async {
    final uid = _resolveUid();
    final path = _displayPath();
    if (uid == null) {
      return null;
    }
    final session = await bus.getProperty(uid: uid, property: 'Session');
    if (!session.ok) {
      return null;
    }
    final type = await bus.getProperty(uid: uid, property: 'SessionType');
    return AccountsSessionState(
      path: path,
      session: parseAccountsProperty(session.stdout),
      sessionType: type.ok ? parseAccountsProperty(type.stdout) : null,
    );
  }

  @override
  Future<AccountsWriteResult> write({
    required String sessionId,
    required SessionType type,
  }) async {
    final sessionType = accountsSessionType(type);
    final path = _displayPath();
    final detail =
        'Session=$sessionId, XSession=$sessionId, and SessionType=$sessionType';
    final uid = _resolveUid();
    if (uid == null) {
      return AccountsWriteResult(
        path: path,
        succeeded: false,
        message: 'Could not update $path for GDM: user id is unknown.',
      );
    }

    final sessionCall = await bus.call(
      uid: uid,
      method: 'SetSession',
      value: sessionId,
    );
    if (sessionCall.executableMissing) {
      return _writeFileDirect(
        path: path,
        sessionId: sessionId,
        sessionType: sessionType,
        detail: detail,
        reason: sessionCall.stderr,
      );
    }
    if (!sessionCall.ok) {
      return AccountsWriteResult(
        path: path,
        succeeded: false,
        message:
            'Could not update $path for GDM: ${_short(sessionCall.stderr)}',
      );
    }

    final xSessionCall = await bus.call(
      uid: uid,
      method: 'SetXSession',
      value: sessionId,
    );
    if (!xSessionCall.ok) {
      return AccountsWriteResult(
        path: path,
        succeeded: false,
        message:
            'Could not update $path for GDM: ${_short(xSessionCall.stderr)}',
      );
    }

    final typeCall = await bus.call(
      uid: uid,
      method: 'SetSessionType',
      value: sessionType,
    );
    if (!typeCall.ok) {
      if (_unknownMethod(typeCall.stderr)) {
        return AccountsWriteResult(
          path: path,
          succeeded: true,
          message:
              'Wrote Session=$sessionId and XSession=$sessionId to $path for GDM.',
        );
      }
      return AccountsWriteResult(
        path: path,
        succeeded: false,
        message: 'Could not update $path for GDM: ${_short(typeCall.stderr)}',
      );
    }

    return AccountsWriteResult(
      path: path,
      succeeded: true,
      message: 'Wrote $detail to $path for GDM.',
    );
  }

  Future<AccountsWriteResult> _writeFileDirect({
    required String path,
    required String sessionId,
    required String sessionType,
    required String detail,
    required String reason,
  }) async {
    final username = _resolveUsername();
    if (username == null) {
      return AccountsWriteResult(
        path: path,
        succeeded: false,
        message:
            'Could not update $path for GDM: ${_short(reason)} Account name is unknown.',
      );
    }
    try {
      final existing = readFile != null
          ? await readFile!(path)
          : await _readIfPresent(path);
      final updated = upsertAccountsUser(
        existing ?? '',
        sessionId: sessionId,
        sessionType: sessionType,
      );
      if (writeFile != null) {
        await writeFile!(path, updated);
      } else {
        final file = File(path);
        await file.writeAsString(updated, flush: true);
      }
      return AccountsWriteResult(
        path: path,
        succeeded: true,
        message: 'Wrote $detail to $path for GDM.',
      );
    } on IOException catch (error) {
      return AccountsWriteResult(
        path: path,
        succeeded: false,
        message: 'Could not update $path for GDM: ${_short('$reason $error')}',
      );
    }
  }

  Future<String?> _readIfPresent(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  int? _resolveUid() {
    if (uid != null) {
      return uid;
    }
    final status = File('/proc/self/status');
    if (!status.existsSync()) {
      return null;
    }
    return readProcUid(status.readAsStringSync());
  }

  String _displayPath() {
    final username = _resolveUsername();
    if (username == null) {
      return kAccountsUsersDirectory;
    }
    return accountsUserFilePath(username);
  }

  String? _resolveUsername() {
    final provided = username;
    if (provided != null && isSafeAccountName(provided)) {
      return provided;
    }
    for (final key in ['USER', 'LOGNAME']) {
      final value = Platform.environment[key];
      if (value != null && isSafeAccountName(value)) {
        return value;
      }
    }
    return null;
  }
}

String? parseAccountsProperty(String stdout) {
  final trimmed = stdout.trim();
  final busctl = RegExp(r'^s\s+"(.*)"$').firstMatch(trimmed);
  if (busctl != null) {
    final value = busctl.group(1)!;
    return value.isEmpty ? null : value;
  }
  final gdbus = RegExp(r"^\(\s*'(.*)'\s*,\s*\)$").firstMatch(trimmed);
  if (gdbus != null) {
    final value = gdbus.group(1)!;
    return value.isEmpty ? null : value;
  }
  return null;
}

int? readProcUid(String status) {
  for (final line in status.split('\n')) {
    if (!line.startsWith('Uid:')) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return int.tryParse(parts[1]);
    }
  }
  return null;
}

bool _unknownMethod(String stderr) {
  final text = stderr.toLowerCase();
  return text.contains('unknown method') || text.contains('unknownmethod');
}

String _short(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= 180) {
    return compact;
  }
  return '${compact.substring(0, 177)}...';
}
