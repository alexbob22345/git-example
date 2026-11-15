import 'desktop_session.dart';
import 'dmrc.dart';

/// AccountsService user cache read by GDM.
const String kAccountsUsersDirectory = '/var/lib/AccountsService/users';

/// Machine-wide SDDM state. It is not a per-user setting.
const String kSddmStatePath = '/var/lib/sddm/state.conf';

/// `x11` or `wayland`, the values AccountsService `SessionType` accepts.
String accountsSessionType(SessionType type) {
  return type == SessionType.wayland ? 'wayland' : 'x11';
}

String accountsUserFilePath(String username) {
  return '$kAccountsUsersDirectory/$username';
}

bool isSafeAccountName(String username) {
  return RegExp(r'^[A-Za-z_][A-Za-z0-9._-]{0,31}$').hasMatch(username);
}

class AccountsUserFields {
  const AccountsUserFields({this.session, this.xSession, this.sessionType});

  final String? session;
  final String? xSession;
  final String? sessionType;
}

/// Reads `Session`, `XSession`, and `SessionType` from `[User]`.
AccountsUserFields readAccountsUser(String contents) {
  var inUser = false;
  String? session;
  String? xSession;
  String? sessionType;
  for (final raw in contents.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    if (line.length >= 2 && line.startsWith('[') && line.endsWith(']')) {
      inUser =
          line.substring(1, line.length - 1).trim().toLowerCase() == 'user';
      continue;
    }
    if (!inUser) {
      continue;
    }
    final eq = line.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final key = line.substring(0, eq).trim().toLowerCase();
    final value = line.substring(eq + 1).trim();
    if (value.isEmpty) {
      continue;
    }
    if (key == 'session') {
      session = value;
    } else if (key == 'xsession') {
      xSession = value;
    } else if (key == 'sessiontype') {
      sessionType = value;
    }
  }
  return AccountsUserFields(
    session: session,
    xSession: xSession,
    sessionType: sessionType,
  );
}

/// Sets the GDM keys inside `[User]`, preserving every other line.
String upsertAccountsUser(
  String existing, {
  required String sessionId,
  required String sessionType,
}) {
  if (!isSafeSessionId(sessionId)) {
    throw FormatException('Refusing to write unsafe session id.');
  }
  if (sessionType != 'x11' && sessionType != 'wayland') {
    throw FormatException('Refusing to write unsafe session type.');
  }
  return upsertIniSection(
    existing,
    section: 'User',
    keys: {
      'Session': sessionId,
      'XSession': sessionId,
      'SessionType': sessionType,
    },
  );
}

String sddmUnchangedNote([String path = kSddmStatePath]) {
  return 'SDDM has no per-user session file. Left $path unchanged.';
}
