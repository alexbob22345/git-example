import 'package:flutter/material.dart';

import 'build_info.dart';

/// Small top-right control that shows the build date.
class KernelButton extends StatelessWidget {
  const KernelButton({super.key, this.foregroundColor});

  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        key: const Key('kernel-button'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 28),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: foregroundColor,
        ),
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Kernel'),
                content: const Text('Build date: $kBuildDate'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          );
        },
        child: const Text('Kernel'),
      ),
    );
  }
}
