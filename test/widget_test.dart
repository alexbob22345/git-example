import 'package:change_gui/main.dart';
import 'package:change_gui/src/desktop_session.dart';
import 'package:change_gui/src/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'memory_session_repository.dart';

void main() {
  const xfce = DesktopSession(
    id: 'xfce',
    name: 'Xfce Session',
    type: SessionType.x11,
    sourcePath: '/usr/share/xsessions/xfce.desktop',
  );
  const plasma = DesktopSession(
    id: 'plasma',
    name: 'Plasma',
    type: SessionType.wayland,
    sourcePath: '/usr/share/wayland-sessions/plasma.desktop',
  );

  testWidgets('splash shows the app name and credit, then the session list', (
    tester,
  ) async {
    final repository = MemorySessionRepository(sessions: const [xfce]);
    await tester.pumpWidget(ChangeGuiApp(repository: repository));

    expect(find.text('Change GUI'), findsOneWidget);
    expect(find.text('Created by Bored Programmer'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    expect(find.text('Created by Bored Programmer'), findsNothing);
    expect(find.text('Xfce Session'), findsOneWidget);
    expect(find.text('X11 · xfce'), findsOneWidget);
  });

  testWidgets('empty install shows an empty state and disables Switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeGuiApp(repository: MemorySessionRepository(), skipSplash: true),
    );
    await tester.pump();

    expect(find.byKey(const Key('empty-state')), findsOneWidget);
    expect(find.text('No desktop sessions are installed'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('switch-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Kernel shows the build date', (tester) async {
    await tester.pumpWidget(
      ChangeGuiApp(
        repository: MemorySessionRepository(sessions: const [xfce]),
        skipSplash: true,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('kernel-button')));
    await tester.pumpAndSettle();

    expect(find.text('Build date: 2026-11-15'), findsOneWidget);
  });

  testWidgets('confirming Switch records the choice and the status', (
    tester,
  ) async {
    final repository = MemorySessionRepository(
      sessions: const [xfce, plasma],
      saved: SavedChoice(
        sessionId: 'xfce',
        name: 'Xfce Session',
        type: SessionType.x11,
        dmrcPath: '/tmp/change-gui-home/.dmrc',
        updatedAt: DateTime.utc(2026, 11, 15),
      ),
      dmrcSessionId: 'xfce',
    );
    await tester.pumpWidget(
      ChangeGuiApp(repository: repository, skipSplash: true),
    );
    await tester.pump();

    expect(find.text('Current'), findsOneWidget);
    expect(find.textContaining('Session=xfce'), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-wayland:plasma')));
    await tester.pump();
    expect(repository.switchCalls, 0);

    await tester.tap(find.byKey(const Key('switch-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Plasma (Wayland)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-switch')));
    await tester.pumpAndSettle();

    expect(repository.switchCalls, 1);
    expect(repository.dmrcSessionId, 'plasma');
    expect(
      find.textContaining('Wrote Session=plasma to /tmp/change-gui-home/.dmrc'),
      findsOneWidget,
    );
    expect(find.textContaining('You stay signed in'), findsOneWidget);
    expect(find.byKey(const Key('current-wayland:plasma')), findsOneWidget);
  });

  testWidgets('a failed write leaves a status and does not claim success', (
    tester,
  ) async {
    final repository = MemorySessionRepository(
      sessions: const [xfce],
      failSwitch: true,
    );
    await tester.pumpWidget(
      ChangeGuiApp(repository: repository, skipSplash: true),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-x11:xfce')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('switch-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-switch')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save the session'), findsOneWidget);
    expect(find.textContaining('Wrote Session='), findsNothing);
  });
}
