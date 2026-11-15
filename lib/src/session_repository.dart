import 'dart:convert';
import 'dart:io';

import 'desktop_session.dart';
import 'dmrc.dart';

/// Choice recorded by this app so the selection stays visible after restart.
class SavedChoice {
  const SavedChoice({
    required this.sessionId,
    required this.name,
    required this.type,
    required this.dmrcPath,
    required this.updatedAt,
  });

  final String sessionId;
  final String name;
  final SessionType type;
  final String dmrcPath;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'name': name,
    'type': type.name,
    'dmrcPath': dmrcPath,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static SavedChoice? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['sessionId'];
    final name = json['name'];
    final typeName = json['type'];
    final dmrcPath = json['dmrcPath'];
    final updatedAt = json['updatedAt'];
    if (id is! String ||
        name is! String ||
        typeName is! String ||
        dmrcPath is! String ||
        updatedAt is! String) {
      return null;
    }
    final type = SessionType.parse(typeName);
    final parsedTime = DateTime.tryParse(updatedAt);
    if (type == null || parsedTime == null || !isSafeSessionId(id)) {
      return null;
    }
    return SavedChoice(
      sessionId: id,
      name: name,
      type: type,
      dmrcPath: dmrcPath,
      updatedAt: parsedTime,
    );
  }
}

/// What a successful switch wrote to disk.
class SwitchResult {
  const SwitchResult({
    required this.session,
    required this.dmrcPath,
    required this.appStatePath,
    required this.sessionLine,
  });

  final DesktopSession session;
  final String dmrcPath;
  final String appStatePath;
  final String sessionLine;
}

/// Installed sessions plus the choice already stored for the next login.
class SessionSnapshot {
  const SessionSnapshot({
    required this.sessions,
    required this.dmrcPath,
    required this.appStatePath,
    this.saved,
    this.dmrcSessionId,
    this.warning,
  });

  final List<DesktopSession> sessions;
  final SavedChoice? saved;
  final String? dmrcSessionId;
  final String dmrcPath;
  final String appStatePath;
  final String? warning;
}

/// Loads installed sessions and persists the user's next-login choice.
abstract class SessionRepository {
  Future<SessionSnapshot> load();

  Future<SwitchResult> switchTo(DesktopSession session);
}

/// Scans the system session directories and writes `~/.dmrc` plus an app file.
class FilesystemSessionRepository implements SessionRepository {
  FilesystemSessionRepository({
    List<String>? x11Directories,
    List<String>? waylandDirectories,
    String? dmrcPath,
    String? appStatePath,
    String? locale,
    DateTime Function()? clock,
  }) : x11Directories = x11Directories ?? kX11SessionDirectories,
       waylandDirectories = waylandDirectories ?? kWaylandSessionDirectories,
       dmrcPath = dmrcPath ?? defaultDmrcPath(),
       appStatePath = appStatePath ?? defaultAppStatePath(),
       locale = locale ?? Platform.localeName,
       clock = clock ?? DateTime.now;

  final List<String> x11Directories;
  final List<String> waylandDirectories;
  final String dmrcPath;
  final String appStatePath;
  final String locale;
  final DateTime Function() clock;

  @override
  Future<SessionSnapshot> load() async {
    final sessions = await scan();
    String? warning;
    String? dmrcSessionId;
    SavedChoice? saved;
    try {
      dmrcSessionId = await readDmrcSession();
    } on IOException catch (error) {
      warning = 'Could not read $dmrcPath ($error).';
    }
    try {
      saved = await readSavedChoice();
    } on IOException catch (error) {
      final note = 'Could not read $appStatePath ($error).';
      warning = warning == null ? note : '$warning $note';
    }
    return SessionSnapshot(
      sessions: sessions,
      saved: saved,
      dmrcSessionId: dmrcSessionId,
      dmrcPath: dmrcPath,
      appStatePath: appStatePath,
      warning: warning,
    );
  }

  Future<List<DesktopSession>> scan() async {
    final sessions = <DesktopSession>[
      ...await _scanDirectories(x11Directories, SessionType.x11),
      ...await _scanDirectories(waylandDirectories, SessionType.wayland),
    ];
    sessions.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) {
        return byName;
      }
      return a.type.name.compareTo(b.type.name);
    });
    return sessions;
  }

  Future<String?> readDmrcSession() async {
    final file = File(dmrcPath);
    if (!await file.exists()) {
      return null;
    }
    return readDmrcSessionId(await file.readAsString());
  }

  Future<SavedChoice?> readSavedChoice() async {
    final file = File(appStatePath);
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    return SavedChoice.fromJson(decoded);
  }

  @override
  Future<SwitchResult> switchTo(DesktopSession session) async {
    if (!isSafeSessionId(session.id)) {
      throw FormatException('Refusing to write unsafe session id.');
    }
    final dmrcFile = File(dmrcPath);
    final existing = await dmrcFile.exists()
        ? await dmrcFile.readAsString()
        : '';
    final updated = upsertDmrcSession(existing, session.id);
    await _writeAtomic(dmrcFile, updated);

    final choice = SavedChoice(
      sessionId: session.id,
      name: session.name,
      type: session.type,
      dmrcPath: dmrcPath,
      updatedAt: clock(),
    );
    final stateFile = File(appStatePath);
    final encoded = const JsonEncoder.withIndent('  ').convert(choice.toJson());
    await _writeAtomic(stateFile, '$encoded\n');

    return SwitchResult(
      session: session,
      dmrcPath: dmrcPath,
      appStatePath: appStatePath,
      sessionLine: 'Session=${session.id}',
    );
  }

  Future<List<DesktopSession>> _scanDirectories(
    List<String> directories,
    SessionType type,
  ) async {
    final sessions = <DesktopSession>[];
    for (final directoryPath in directories) {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        continue;
      }
      await for (final entity in directory.list(followLinks: true)) {
        if (entity is! File || !entity.path.endsWith('.desktop')) {
          continue;
        }
        try {
          final bytes = await entity.readAsBytes();
          final text = utf8.decode(bytes, allowMalformed: true);
          final session = parseDesktopSession(
            text,
            path: entity.path,
            type: type,
            locale: locale,
          );
          if (session != null) {
            sessions.add(session);
          }
        } on IOException {
          continue;
        }
      }
    }
    return sessions;
  }

  Future<void> _writeAtomic(File file, String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp-$pid-${clock().microsecondsSinceEpoch}',
    );
    await temporary.writeAsString(contents, flush: true);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      await file.writeAsString(contents, flush: true);
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }
}

/// Session that should appear selected when the window opens.
DesktopSession? initialSelection(SessionSnapshot snapshot) {
  final saved = snapshot.saved;
  if (saved != null) {
    for (final session in snapshot.sessions) {
      if (session.id == saved.sessionId && session.type == saved.type) {
        return session;
      }
    }
  }
  final dmrcId = snapshot.dmrcSessionId;
  if (dmrcId == null) {
    return null;
  }
  final matches = snapshot.sessions
      .where((session) => session.id == dmrcId)
      .toList();
  if (matches.isEmpty) {
    return null;
  }
  for (final session in matches) {
    if (session.type == SessionType.wayland) {
      return session;
    }
  }
  return matches.first;
}

String describeSnapshot(SessionSnapshot snapshot) {
  final parts = <String>[];
  final dmrcId = snapshot.dmrcSessionId;
  if (dmrcId == null) {
    parts.add('No Session= entry in ${snapshot.dmrcPath} yet.');
  } else {
    parts.add('Next login in ${snapshot.dmrcPath} is Session=$dmrcId.');
  }
  final saved = snapshot.saved;
  if (saved != null) {
    parts.add('App record: ${saved.name} (${saved.type.label}).');
  }
  final warning = snapshot.warning;
  if (warning != null && warning.isNotEmpty) {
    parts.add(warning);
  }
  return parts.join(' ');
}

String describeSwitch(SwitchResult result) {
  return 'Wrote ${result.sessionLine} to ${result.dmrcPath}. '
      'Saved ${result.session.name} (${result.session.type.label}) in '
      '${result.appStatePath}. This applies at the next login. '
      'You stay signed in.';
}
