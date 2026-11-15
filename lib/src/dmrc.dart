import 'desktop_session.dart';

/// Reads `Session=` from the `[Desktop]` section of a `~/.dmrc` file.
String? readDmrcSessionId(String contents) {
  var inDesktop = false;
  String? session;
  for (final raw in contents.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    final section = _sectionName(line);
    if (section != null) {
      inDesktop = section == 'desktop';
      continue;
    }
    if (!inDesktop) {
      continue;
    }
    final eq = line.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final key = line.substring(0, eq).trim().toLowerCase();
    if (key == 'session') {
      final value = line.substring(eq + 1).trim();
      if (value.isNotEmpty) {
        session = value;
      }
    }
  }
  return session;
}

/// Sets `Session=` inside `[Desktop]`, preserving every other line.
///
/// Creates the section when the file is missing or has no `[Desktop]` group.
/// Display managers such as LightDM read this key at the next login.
String upsertDmrcSession(String existing, String sessionId) {
  if (!isSafeSessionId(sessionId)) {
    throw FormatException('Refusing to write unsafe session id.');
  }
  final newline = existing.contains('\r\n') ? '\r\n' : '\n';
  final lines = existing.replaceAll('\r\n', '\n').split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }

  final sessionLine = 'Session=$sessionId';
  var desktopStart = -1;
  for (var i = 0; i < lines.length; i++) {
    if (_sectionName(lines[i]) == 'desktop') {
      desktopStart = i;
      break;
    }
  }

  if (desktopStart == -1) {
    if (lines.isNotEmpty && lines.last.trim().isNotEmpty) {
      lines.add('');
    }
    lines
      ..add('[Desktop]')
      ..add(sessionLine);
  } else {
    var sectionEnd = lines.length;
    for (var i = desktopStart + 1; i < lines.length; i++) {
      if (_sectionName(lines[i]) != null) {
        sectionEnd = i;
        break;
      }
    }
    var replaced = false;
    for (var i = desktopStart + 1; i < sectionEnd; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith(';')) {
        continue;
      }
      final eq = trimmed.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      final key = trimmed.substring(0, eq).trim().toLowerCase();
      if (key == 'session') {
        lines[i] = sessionLine;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      lines.insert(sectionEnd, sessionLine);
    }
  }

  return '${lines.join(newline)}$newline';
}

String? _sectionName(String line) {
  final trimmed = line.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('[') && trimmed.endsWith(']')) {
    return trimmed.substring(1, trimmed.length - 1).trim().toLowerCase();
  }
  return null;
}
