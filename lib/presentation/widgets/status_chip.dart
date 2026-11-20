import 'package:material_ui/material_ui.dart';

import '../../engines/console.dart';

class CoreStatusChip extends StatelessWidget {
  const CoreStatusChip(this.status, {super.key});

  final CoreStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      CoreStatus.available => const Color(0xFF22C55E),
      CoreStatus.inDevelopment => const Color(0xFFF59E0B),
      CoreStatus.planned => Theme.of(context).colorScheme.onSurfaceVariant,
      CoreStatus.unavailable => const Color(0xFFEF4444),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
