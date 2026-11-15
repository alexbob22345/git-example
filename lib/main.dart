import 'package:material_ui/material_ui.dart';

import 'src/build_info.dart';
import 'src/session_home.dart';
import 'src/session_repository.dart';
import 'src/splash_screen.dart';

void main() {
  runApp(const ChangeGuiApp());
}

class ChangeGuiApp extends StatefulWidget {
  const ChangeGuiApp({
    super.key,
    this.repository,
    this.skipSplash = false,
    this.splashDuration = const Duration(milliseconds: 1200),
  });

  final SessionRepository? repository;
  final bool skipSplash;
  final Duration splashDuration;

  @override
  State<ChangeGuiApp> createState() => _ChangeGuiAppState();
}

class _ChangeGuiAppState extends State<ChangeGuiApp> {
  late final SessionRepository _repository =
      widget.repository ?? FilesystemSessionRepository();
  var _showSplash = true;

  @override
  void initState() {
    super.initState();
    _showSplash = !widget.skipSplash;
    if (_showSplash) {
      Future<void>.delayed(widget.splashDuration, () {
        if (mounted) {
          setState(() => _showSplash = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16324F)),
      ),
      home: _showSplash
          ? const SplashScreen()
          : SessionHome(repository: _repository),
    );
  }
}
