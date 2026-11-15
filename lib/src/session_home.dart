import 'package:material_ui/material_ui.dart';

import 'accounts_user.dart';
import 'build_info.dart';
import 'desktop_session.dart';
import 'kernel_button.dart';
import 'session_repository.dart';

class SessionHome extends StatefulWidget {
  const SessionHome({super.key, required this.repository});

  final SessionRepository repository;

  @override
  State<SessionHome> createState() => _SessionHomeState();
}

class _SessionHomeState extends State<SessionHome> {
  SessionSnapshot? _snapshot;
  String? _pickedKey;
  String _status = 'Looking for installed desktop sessions…';
  var _loading = true;
  var _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await widget.repository.load();
      if (!mounted) {
        return;
      }
      final selected = initialSelection(snapshot);
      setState(() {
        _snapshot = snapshot;
        _pickedKey = selected?.selectionKey;
        _status = describeSnapshot(snapshot);
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = '$error';
        _status = 'Could not read desktop sessions: $error';
      });
    }
  }

  DesktopSession? get _picked {
    final snapshot = _snapshot;
    final key = _pickedKey;
    if (snapshot == null || key == null) {
      return null;
    }
    for (final session in snapshot.sessions) {
      if (session.selectionKey == key) {
        return session;
      }
    }
    return null;
  }

  bool _isCurrent(DesktopSession session) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return false;
    }
    final active = initialSelection(snapshot);
    return active?.selectionKey == session.selectionKey;
  }

  Future<void> _confirmSwitch() async {
    final session = _picked;
    final snapshot = _snapshot;
    if (session == null || snapshot == null || _busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Switch session'),
          content: Text(
            'Use ${session.name} (${session.type.label}) the next time you '
            'log in? Log out and back in for it to take effect. You stay '
            'signed in, and this machine will not reboot.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-switch'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Switch'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.repository.switchTo(session);
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = SessionSnapshot(
          sessions: snapshot.sessions,
          saved: SavedChoice(
            sessionId: session.id,
            name: session.name,
            type: session.type,
            dmrcPath: result.dmrcPath,
            updatedAt: DateTime.now(),
          ),
          dmrcSessionId: result.dmrcWritten
              ? session.id
              : snapshot.dmrcSessionId,
          accountsSessionId: result.accountsUpdated
              ? session.id
              : snapshot.accountsSessionId,
          accountsSessionType: result.accountsUpdated
              ? accountsSessionType(session.type)
              : snapshot.accountsSessionType,
          dmrcPath: result.dmrcPath,
          appStatePath: result.appStatePath,
        );
        _status = describeSwitch(result);
        _busy = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'Could not save the session: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final sessions = snapshot?.sessions ?? const <DesktopSession>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        actions: const [KernelButton()],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Installed desktop sessions. Switch writes the one used '
                  'the next time you log in.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Expanded(child: _buildBody(sessions)),
                const SizedBox(height: 12),
                Text(key: const Key('status-text'), _status),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('switch-button'),
                  onPressed: _picked == null || _busy || _loading
                      ? null
                      : _confirmSwitch,
                  child: Text(_busy ? 'Saving…' : 'Switch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<DesktopSession> sessions) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(child: Text(_loadError!));
    }
    if (sessions.isEmpty) {
      return const _EmptySessions();
    }
    return RadioGroup<String>(
      groupValue: _pickedKey,
      onChanged: (value) {
        if (value == null) {
          return;
        }
        setState(() => _pickedKey = value);
      },
      child: ListView.separated(
        key: const Key('session-list'),
        itemCount: sessions.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final session = sessions[index];
          final current = _isCurrent(session);
          return RadioListTile<String>(
            key: Key('session-${session.selectionKey}'),
            value: session.selectionKey,
            selected: _pickedKey == session.selectionKey,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(session.name),
            subtitle: Text('${session.type.label} · ${session.id}'),
            secondary: current
                ? Text(
                    'Current',
                    key: Key('current-${session.selectionKey}'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('empty-state'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.desktop_windows_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No desktop sessions are installed',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Looked in /usr/share/xsessions and '
            '/usr/share/wayland-sessions for .desktop files.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
