import 'dart:io';

/// Whether a session file came from an X11 or Wayland session directory.
enum SessionType {
  x11('X11'),
  wayland('Wayland');

  const SessionType(this.label);

  final String label;

  static SessionType? parse(String value) {
    for (final type in SessionType.values) {
      if (type.name == value) {
        return type;
      }
    }
    return null;
  }
}

/// One `*.desktop` session a display manager can start.
class DesktopSession {
  const DesktopSession({
    required this.id,
    required this.name,
    required this.type,
    required this.sourcePath,
    this.comment,
  });

  /// Desktop file name without `.desktop`. This is the `Session=` value.
  final String id;
  final String name;
  final SessionType type;
  final String sourcePath;
  final String? comment;

  String get selectionKey => '${type.name}:$id';
}

final RegExp _safeSessionId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.+-]*$');

/// Session ids are written into `~/.dmrc`, so they stay a single token.
bool isSafeSessionId(String id) => _safeSessionId.hasMatch(id);

String sessionIdFromPath(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  const suffix = '.desktop';
  if (name.toLowerCase().endsWith(suffix)) {
    return name.substring(0, name.length - suffix.length);
  }
  return name;
}

String unescapeDesktopValue(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == r'\' && i + 1 < value.length) {
      final next = value[i + 1];
      switch (next) {
        case 's':
          buffer.write(' ');
        case 'n':
          buffer.write('\n');
        case 't':
          buffer.write('\t');
        case 'r':
          buffer.write('\r');
        case r'\':
          buffer.write(r'\');
        default:
          buffer.write(next);
      }
      i++;
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

/// Parses a session desktop file.
///
/// Returns null when the file is hidden, is not a session, or its id would
/// not be safe to write into `~/.dmrc`.
DesktopSession? parseDesktopSession(
  String contents, {
  required String path,
  required SessionType type,
  String locale = '',
}) {
  final id = sessionIdFromPath(path);
  if (!isSafeSessionId(id)) {
    return null;
  }
  final fields = _desktopEntryFields(contents);
  if (fields == null) {
    return null;
  }
  if (_isTrue(fields['Hidden'])) {
    return null;
  }
  final entryType = fields['Type'];
  if (entryType != null &&
      entryType.isNotEmpty &&
      entryType != 'Application' &&
      entryType != 'XSession') {
    return null;
  }
  final name = _localized(fields, 'Name', locale) ?? id;
  final comment = _localized(fields, 'Comment', locale);
  return DesktopSession(
    id: id,
    name: name,
    type: type,
    sourcePath: path,
    comment: comment,
  );
}

bool _isTrue(String? value) => value?.toLowerCase() == 'true';

Map<String, String>? _desktopEntryFields(String contents) {
  final fields = <String, String>{};
  var inEntry = false;
  var sawEntry = false;
  for (final raw in contents.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      final section = line.substring(1, line.length - 1).trim().toLowerCase();
      inEntry = section == 'desktop entry';
      if (inEntry) {
        sawEntry = true;
      }
      continue;
    }
    if (!inEntry) {
      continue;
    }
    final eq = line.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final key = line.substring(0, eq).trim();
    final value = unescapeDesktopValue(line.substring(eq + 1).trim());
    fields.putIfAbsent(key, () => value);
  }
  if (!sawEntry) {
    return null;
  }
  return fields;
}

String? _localized(Map<String, String> fields, String base, String locale) {
  final normalized = locale.split('.').first.trim();
  if (normalized.isNotEmpty) {
    final exact = fields['$base[$normalized]'];
    if (exact != null && exact.isNotEmpty) {
      return exact;
    }
    final language = normalized.split('_').first;
    if (language.isNotEmpty) {
      final lang = fields['$base[$language]'];
      if (lang != null && lang.isNotEmpty) {
        return lang;
      }
    }
  }
  final plain = fields[base];
  if (plain != null && plain.isNotEmpty) {
    return plain;
  }
  return null;
}

/// Default directories a display manager reads for session desktop files.
const List<String> kX11SessionDirectories = ['/usr/share/xsessions'];
const List<String> kWaylandSessionDirectories = ['/usr/share/wayland-sessions'];

String defaultDmrcPath() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('HOME is not set, so ~/.dmrc cannot be located.');
  }
  return '$home/.dmrc';
}

String defaultAppStatePath() {
  final override = Platform.environment['XDG_CONFIG_HOME'];
  final base = (override != null && override.isNotEmpty)
      ? override
      : '${Platform.environment['HOME']}/.config';
  return '$base/change_gui/selection.json';
}
