import 'package:material_ui/material_ui.dart';

import '../../brand/retro.dart';
import '../../engines/console.dart';
import 'status_chip.dart';

/// Tarjeta de consola (estilo menú de consola): icono pixel de la consola en
/// su "pantalla", nombre en mayúsculas y estado del núcleo.
class ConsoleCard extends StatelessWidget {
  const ConsoleCard({
    super.key,
    required this.console,
    required this.onTap,
    this.gameCount,
  });

  final ConsoleDescriptor console;
  final VoidCallback onTap;

  /// Juegos de esta consola en la biblioteca (null si no se conoce).
  final int? gameCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RetroPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: retroScreen(),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: ConsoleArt(console.id, background: false),
                  ),
                ),
                if (gameCount != null && gameCount! > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Text(
                      '$gameCount',
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            console.shortName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Center(child: CoreStatusChip(console.status)),
        ],
      ),
    );
  }
}

/// Icono pixel de la consola en una "pantalla" cuadrada (listas).
class ConsoleMonogram extends StatelessWidget {
  const ConsoleMonogram({super.key, required this.console, this.size = 48});

  final ConsoleDescriptor console;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size * 1.3,
        height: size,
        padding: const EdgeInsets.all(3),
        decoration: retroScreen(),
        child: ConsoleArt(console.id, background: false),
      );
}
