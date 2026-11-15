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
/// LightDM reads this key at the next login.
String upsertDmrcSession(String existing, String sessionId) {
  if (!isSafeSessionId(sessionId)) {
    throw FormatException('Refusing to write unsafe session id.');
  }
  return upsertIniSection(
    existing,
    section: 'Desktop',
    keys: {'Session': sessionId},
  );
}

/// Sets keys inside one ini section, preserving every other line.
String upsertIniSection(
  String existing, {
  required String section,
  required Map<String, String> keys,
}) {
  final newline = existing.contains('\r\n') ? '\r\n' : '\n';
  final lines = existing.replaceAll('\r\n', '\n').split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }

  final wanted = keys.entries.toList();
  var sectionStart = -1;
  for (var i = 0; i < lines.length; i++) {
    if (_sectionName(lines[i]) == section.toLowerCase()) {
      sectionStart = i;
      break;
    }
  }

  if (sectionStart == -1) {
    if (lines.isNotEmpty && lines.last.trim().isNotEmpty) {
      lines.add('');
    }
    lines.add('[$section]');
    for (final entry in wanted) {
      lines.add('${entry.key}=${entry.value}');
    }
    return '${lines.join(newline)}$newline';
  }

  var sectionEnd = lines.length;
  for (var i = sectionStart + 1; i < lines.length; i++) {
    if (_sectionName(lines[i]) != null) {
      sectionEnd = i;
      break;
    }
  }

  final remaining = {
    for (final entry in wanted) entry.key.toLowerCase(): entry,
  };
  for (var i = sectionStart + 1; i < sectionEnd; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith(';')) {
      continue;
    }
    final eq = trimmed.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final key = trimmed.substring(0, eq).trim().toLowerCase();
    final replacement = remaining.remove(key);
    if (replacement != null) {
      lines[i] = '${replacement.key}=${replacement.value}';
    }
  }
  var insertAt = sectionEnd;
  for (final entry in remaining.values) {
    lines.insert(insertAt, '${entry.key}=${entry.value}');
    insertAt++;
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
