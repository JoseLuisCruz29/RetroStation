import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../app/version.dart';
import '../../app/theme.dart';
import '../../brand/logo.dart';
import '../../brand/retro.dart';
import '../../core/format.dart';
import '../../download_manager/download_manager.dart';
import '../../engines/console.dart';
import '../../engines/console_registry.dart';
import '../../game_library/game_repository.dart';
import '../../storage/database.dart';
import '../tutorial/tutorial_overlay.dart';
import '../widgets/console_card.dart';
import '../widgets/game_card.dart';
import '../widgets/section_header.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _all = LibraryFilter();
  static const _recent = LibraryFilter(category: LibraryCategory.recent);
  static const _installed = LibraryFilter(category: LibraryCategory.installed);
  static const _favorites = LibraryFilter(category: LibraryCategory.favorites);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameCount = ref.watch(gameCountProvider).value ?? 0;
    final all = ref.watch(libraryProvider(_all)).value ?? const <Game>[];
    final recent = ref.watch(libraryProvider(_recent));
    final installed = ref.watch(libraryProvider(_installed)).value ?? const <Game>[];
    final favorites = ref.watch(libraryProvider(_favorites)).value ?? const <Game>[];
    final activeDownloads = ref.watch(downloadsProvider
        .select((m) => m.values.where((e) => e.phase.isActive).length));

    final perConsole = <String, int>{};
    for (final g in all) {
      perConsole[g.consoleId] = (perConsole[g.consoleId] ?? 0) + 1;
    }
    final recentGames = recent.value ?? const <Game>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _TopBar(activeDownloads: activeDownloads),
            ),
            SliverToBoxAdapter(
              child: recent.isLoading && !recent.hasValue
                  ? const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _Fade(
                      id: gameCount == 0 ? 'welcome' : recentGames.firstOrNull?.id,
                      child: gameCount == 0
                          ? const _Welcome()
                          : recentGames.isEmpty
                              ? const _NoRecentGames()
                              : _ContinueHero(game: recentGames.first),
                    ),
            ),
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: TutorialTargets.quickAccess,
                child: _QuickAccess(
                  gameCount: gameCount,
                  activeDownloads: activeDownloads,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _LanCard()),
            if (recentGames.length > 1)
              ..._carousel(
                context,
                ref,
                title: 'Jugados recientemente',
                games: recentGames.skip(1).toList(),
              ),
            if (installed.isNotEmpty)
              ..._carousel(
                context,
                ref,
                title: 'Juegos instalados',
                subtitle: '${installed.length} listos para jugar sin conexión',
                games: installed,
                seeAll: () => context.go(Routes.library),
              ),
            if (favorites.isNotEmpty)
              ..._carousel(context, ref, title: 'Favoritos', games: favorites),
            SliverToBoxAdapter(
              child: SectionHeader(
                'Consolas',
                subtitle:
                    '${ConsoleRegistry.availableCount} de ${ConsoleRegistry.all.length} con núcleo listo',
                trailing: TextButton(
                  onPressed: () => context.go(Routes.consoles),
                  child: const Text('Ver todas'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 176,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: ConsoleRegistry.all.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final console = ConsoleRegistry.all[i];
                    return SizedBox(
                      width: 152,
                      child: ConsoleCard(
                        console: console,
                        gameCount: perConsole[console.id] ?? 0,
                        onTap: () =>
                            context.go(Routes.libraryForConsole(console.id)),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<Widget> _carousel(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    String? subtitle,
    required List<Game> games,
    VoidCallback? seeAll,
  }) =>
      [
        SliverToBoxAdapter(
          child: SectionHeader(
            title,
            subtitle: subtitle,
            trailing: seeAll == null
                ? null
                : TextButton(onPressed: seeAll, child: const Text('Ver todos')),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 236,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: games.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(
                width: 140,
                child: GameCard(
                  game: games[i],
                  onTap: () => context.push(Routes.game(games[i].id)),
                  onToggleFavorite: () => ref
                      .read(gameRepositoryProvider)
                      .setFavorite(games[i].id, !games[i].isFavorite),
                ),
              ),
            ),
          ),
        ),
      ];
}

/// Logo y acceso a las descargas en curso.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.activeDownloads});

  final int activeDownloads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: RetroPanel(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            const LogoMark(size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RETROSTATION',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(height: 1.1)),
                  Text('SISTEMA OPERATIVO · V$appVersion',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Descargas',
              onPressed: () => context.push(Routes.downloads),
              icon: Badge(
                isLabelVisible: activeDownloads > 0,
                label: Text('$activeDownloads'),
                child: const Icon(Icons.download_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Juego destacado: el último jugado, con su portada a gran tamaño.
class _ContinueHero extends StatelessWidget {
  const _ContinueHero({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final console = ConsoleRegistry.byId(game.consoleId);
    final canPlay = game.status == GameStatus.installed &&
        console?.status == CoreStatus.available;
    final cover = game.coverPath;
    final hasCover = cover != null && File(cover).existsSync();
    final accent = console?.color ?? theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: RetroPanel(
        onTap: () => context.push(Routes.game(game.id)),
        padding: const EdgeInsets.all(6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 210,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Fondo: la portada decodificada a muy poca resolución y
                // ampliada queda desenfocada sin el coste de un filtro.
                if (hasCover)
                  Image.file(
                    File(cover),
                    fit: BoxFit.cover,
                    cacheWidth: 40,
                    filterQuality: FilterQuality.medium,
                  )
                else
                  ColoredBox(color: Color.lerp(accent, RetroColors.charcoal, 0.6)!),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.82),
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                    border: Border.all(color: RetroColors.outline),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CONTINUAR JUGANDO',
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w700,
                                color: Color.lerp(accent, Colors.white, 0.45),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              game.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(color: Colors.white, height: 1.15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                console?.name ?? game.consoleId,
                                formatPlayTime(game.playTimeSeconds),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: canPlay
                                  ? () => context.push(Routes.player(game.id))
                                  : null,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(canPlay ? 'Continuar' : 'No disponible'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      AspectRatio(
                        aspectRatio: 3 / 4,
                        child: GameCover(game: game, borderRadius: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Primera vez: la biblioteca está vacía.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: DecoratedBox(
        decoration: retroFrame(),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LogoMark(size: 48),
              const SizedBox(height: 14),
              Text('Tu biblioteca está lista', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Importa tus ROMs o ZIP desde el teléfono, o busca juegos de '
                'libre distribución en Descubrir.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(
                  onPressed: () => context.go(Routes.library),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Añadir juegos'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go(Routes.discovery),
                  icon: const Icon(Icons.travel_explore_rounded, size: 18),
                  label: const Text('Descubrir'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hay juegos pero ninguno se ha abierto todavía.
class _NoRecentGames extends StatelessWidget {
  const _NoRecentGames();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.sports_esports_rounded,
                    size: 28, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Todavía no has jugado nada',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'El último juego que abras aparecerá aquí para retomarlo.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: () => context.go(Routes.library),
                      icon: const Icon(Icons.sports_esports_rounded, size: 18),
                      label: const Text('Elegir un juego'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Accesos directos a las secciones principales.
class _QuickAccess extends StatelessWidget {
  const _QuickAccess({required this.gameCount, required this.activeDownloads});

  final int gameCount;
  final int activeDownloads;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.sports_esports_rounded, 'Juegos', '$gameCount',
          () => context.go(Routes.library)),
      (Icons.save_rounded, 'Partidas', null, () => context.push(Routes.saves)),
      (Icons.download_rounded, 'Descargas',
          activeDownloads > 0 ? '$activeDownloads' : null,
          () => context.push(Routes.downloads)),
      // Consolas ya está en la barra inferior.
      (Icons.wifi_tethering_rounded, 'Multijugador', null, () => context.push(Routes.multiplayer)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          for (final (i, (icon, label, count, onTap)) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _QuickTile(icon: icon, label: label, count: count, onTap: onTap),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final String? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RetroPanel(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Badge(
                isLabelVisible: count != null,
                label: Text(count ?? ''),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 6),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
    );
  }
}

/// Aparición suave al cambiar el contenido destacado.
class _Fade extends StatelessWidget {
  const _Fade({required this.id, required this.child});

  final Object? id;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        child: KeyedSubtree(key: ValueKey(id), child: child),
      );
}

/// Acceso destacado al multijugador LAN (novedad de la 3.0).
class _LanCard extends StatelessWidget {
  const _LanCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: RetroPanel(
        onTap: () => context.push(Routes.multiplayer),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: retroScreen(),
              child: Icon(Icons.wifi_tethering_rounded, color: theme.colorScheme.primary, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: RetroColors.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: RetroColors.success.withValues(alpha: 0.7), width: 2),
                    ),
                    child: Text('NUEVO', style: theme.textTheme.labelSmall?.copyWith(color: RetroColors.success)),
                  ),
                  const SizedBox(height: 6),
                  Text('MULTIJUGADOR LOCAL (LAN)', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    'Juega con amigos en la misma Wi-Fi, sin internet: cooperativo en NES, '
                    'SNES y PS1, y cable link de GBA (Kirby, Pokémon...). También desde el PC',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
