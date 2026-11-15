import 'package:material_ui/material_ui.dart';

import 'build_info.dart';
import 'kernel_button.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/app_icon.png', width: 96, height: 96),
                const SizedBox(height: 20),
                Text(kAppName, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  kCredit,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Align(
            alignment: Alignment.topRight,
            child: SafeArea(child: KernelButton()),
          ),
        ],
      ),
    );
  }
}
