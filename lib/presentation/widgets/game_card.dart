import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../brand/retro.dart';
import '../../core/format.dart';
import '../../engines/console.dart';
import '../../engines/console_registry.dart';
import '../../storage/database.dart';

/// Portada de un juego dentro de una "pantalla" oscura con marco. Si no hay
/// portada descargada, muestra el icono pixel de su consola (no una imagen
/// inventada). La imagen se decodifica al tamaño en pantalla.
class GameCover extends StatelessWidget {
  const GameCover({
    super.key,
    required this.game,
    // Completa (sin recortar): las portadas tienen proporciones distintas
    // según la consola, y recortarlas cortaba el título del juego.
    this.fit = BoxFit.contain,
    this.borderRadius = 6,
  });

  final Game game;
  final BoxFit fit;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final console = ConsoleRegistry.byId(game.consoleId);
    final cover = game.coverPath;
    final hasCover = cover != null && File(cover).existsSync();
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: RetroPalette.lineDark, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: LayoutBuilder(builder: (context, box) {
          if (hasCover) {
            final dpr = MediaQuery.devicePixelRatioOf(context);
            return ColoredBox(
              color: RetroPalette.screen,
              child: Image.file(
                File(cover),
                fit: fit,
                width: box.maxWidth,
                height: box.maxHeight,
                cacheWidth: box.maxWidth.isFinite ? (box.maxWidth * dpr).round() : null,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => CoverPlaceholder(console: console),
              ),
            );
          }
          return CoverPlaceholder(console: console);
        }),
      ),
    );
  }
}

/// Fondo para juegos sin portada: el icono pixel de la consola sobre la
/// "pantalla" oscura, con un leve tono de su color.
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({super.key, required this.console});

  final ConsoleDescriptor? console;

  @override
  Widget build(BuildContext context) {
    final accent = console?.color ?? RetroPalette.line;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(RetroPalette.screen, accent, 0.18)!, RetroPalette.screen],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: console == null
            ? const Icon(Icons.videogame_asset_rounded, color: RetroPalette.muted)
            : ConsoleArt(console!.id, background: false),
      ),
    );
  }
}

/// Tarjeta de juego (estilo menú de consola): panel con marco, la portada
/// en su "pantalla" y el título en mayúsculas debajo.
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final Game game;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final console = ConsoleRegistry.byId(game.consoleId);
    final installed = game.status == GameStatus.installed;

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
                GameCover(game: game),
                Positioned(
                  left: 6,
                  top: 6,
                  child: ConsoleBadge(console: console, fallback: game.consoleId),
                ),
                if (!installed)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: _StatusPill(
                      icon: game.status == GameStatus.downloading
                          ? Icons.downloading_rounded
                          : Icons.cloud_outlined,
                      label: game.status == GameStatus.downloading
                          ? 'Descargando'
                          : 'Sin archivo',
                    ),
                  ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    tooltip: game.isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
                    onPressed: onToggleFavorite,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                    ),
                    icon: Icon(
                      game.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: game.isFavorite ? RetroColors.favorite : Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
            child: Text(
              game.title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 1, 2, 2),
            child: Text(
              formatPlayTime(game.playTimeSeconds),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Siglas de la consola sobre la portada.
class ConsoleBadge extends StatelessWidget {
  const ConsoleBadge({super.key, required this.console, required this.fallback});

  final ConsoleDescriptor? console;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final color = console?.color ?? RetroPalette.line;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          console?.shortName ?? fallback.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Color.lerp(color, Colors.white, 0.4),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: Colors.white70),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
          ]),
        ),
      );
}
