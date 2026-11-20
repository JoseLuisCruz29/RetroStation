import 'package:material_ui/material_ui.dart';

import '../../brand/logo.dart';

/// Estado vacío con icono, título, explicación y acciones opcionales reales.
/// El icono se muestra sobre un cartucho tenue que recuerda al logo.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 112,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    LogoMark(
                      size: 112,
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surfaceContainerHigh,
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(icon, size: 28, color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(title,
                  style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              ),
              if (action != null || secondaryAction != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [?action, ?secondaryAction],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
