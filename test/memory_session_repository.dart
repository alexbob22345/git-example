import 'package:change_gui/src/desktop_session.dart';
import 'package:change_gui/src/session_repository.dart';

class MemorySessionRepository implements SessionRepository {
  MemorySessionRepository({
    this.sessions = const [],
    this.saved,
    this.dmrcSessionId,
    this.failSwitch = false,
    this.dmrcPath = '/tmp/change-gui-home/.dmrc',
    this.appStatePath =
        '/tmp/change-gui-home/.config/change_gui/selection.json',
  });

  List<DesktopSession> sessions;
  SavedChoice? saved;
  String? dmrcSessionId;
  bool failSwitch;
  final String dmrcPath;
  final String appStatePath;
  int switchCalls = 0;

  @override
  Future<SessionSnapshot> load() async {
    return SessionSnapshot(
      sessions: sessions,
      saved: saved,
      dmrcSessionId: dmrcSessionId,
      dmrcPath: dmrcPath,
      appStatePath: appStatePath,
    );
  }

  @override
  Future<SwitchResult> switchTo(DesktopSession session) async {
    switchCalls += 1;
    if (failSwitch) {
      throw StateError('disk full');
    }
    dmrcSessionId = session.id;
    saved = SavedChoice(
      sessionId: session.id,
      name: session.name,
      type: session.type,
      dmrcPath: dmrcPath,
      updatedAt: DateTime.utc(2026, 11, 15),
    );
    return SwitchResult(
      session: session,
      dmrcPath: dmrcPath,
      appStatePath: appStatePath,
      sessionLine: 'Session=${session.id}',
    );
  }
}
