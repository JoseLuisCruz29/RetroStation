import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../download_manager/download_manager.dart';
import '../../engines/console.dart';
import '../../engines/console_registry.dart';
import '../../game_library/game_repository.dart';
import '../../metadata/metadata_service.dart';
import '../../save_manager/save_state_service.dart';
import '../../storage/database.dart';
import '../../storage/storage_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/game_card.dart';
import '../widgets/section_header.dart';

class GameDetailScreen extends ConsumerStatefulWidget {
  const GameDetailScreen({super.key, required this.gameId});

  final int gameId;

  @override
  ConsumerState<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends ConsumerState<GameDetailScreen> {
  bool _enriching = false;

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _enrich(Game game) async {
    setState(() => _enriching = true);
    final result = await ref.read(metadataServiceProvider).enrich(game);
    if (!mounted) return;
    setState(() => _enriching = false);
    _snack(switch (result) {
      EnrichResult.updated => 'Juego identificado y datos actualizados',
      EnrichResult.notInDatabase =>
        'No figura en No-Intro: puede ser homebrew, un hack o un volcado modificado',
      EnrichResult.unsupported => 'No hay base de datos para esta consola',
      EnrichResult.offline => 'Sin conexión: inténtalo más tarde',
    });
  }

  Future<void> _rename(Game game) async {
    final controller = TextEditingController(text: game.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 255,
          decoration: const InputDecoration(labelText: 'Título'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title != null && title.trim().isNotEmpty) {
      await ref.read(gameRepositoryProvider).rename(game.id, title);
    }
  }

  Future<void> _delete(Game game) async {
    var deleteSaves = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Eliminar juego'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Se borrará "${game.title}" y su archivo ROM.'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteSaves,
                onChanged: (v) => setLocal(() => deleteSaves = v ?? false),
                title: const Text('Borrar también partidas y save states'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RetroColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await ref
        .read(gameRepositoryProvider)
        .delete(game, ref.read(appPathsProvider), deleteSaves: deleteSaves);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameByIdProvider(widget.gameId));
    return Scaffold(
      body: game.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (g) => g == null
            ? const SafeArea(
                child: EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Juego no encontrado',
                  message: 'Este juego ya no está en la biblioteca.',
                ),
              )
            : _content(g),
      ),
    );
  }

  Widget _content(Game game) {
    final theme = Theme.of(context);
    final console = ConsoleRegistry.byId(game.consoleId);
    final canPlay = game.status == GameStatus.installed &&
        console?.status == CoreStatus.available;
    final cover = game.coverPath;
    final states = ref.watch(gameSaveStatesProvider(game.id)).value ?? const [];
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 320,
          actions: [
            IconButton(
              tooltip: game.isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
              icon: Icon(game.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: game.isFavorite ? RetroColors.favorite : null),
              onPressed: () =>
                  ref.read(gameRepositoryProvider).setFavorite(game.id, !game.isFavorite),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'rename' => _rename(game),
                'delete' => _delete(game),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: _Hero(game: game, hasCover: cover != null && File(cover).existsSync()),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(game.title, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(label: Text(console?.name ?? game.consoleId)),
                  if (game.verified)
                    const Chip(
                      avatar: Icon(Icons.verified_rounded, size: 18, color: RetroColors.success),
                      label: Text('Verificado (No-Intro)'),
                    ),
                  if (game.genre != null) Chip(label: Text(game.genre!)),
                  if (game.releaseYear != null) Chip(label: Text('${game.releaseYear}')),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canPlay ? () => context.push(Routes.player(game.id)) : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(canPlay ? 'Jugar' : 'No disponible'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                if (game.status != GameStatus.installed && game.downloadUrl != null) ...[
                  const SizedBox(height: 8),
                  _DownloadButton(game: game),
                ],
                if (!canPlay && console != null && console.status != CoreStatus.available)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        console.note ?? 'El núcleo de ${console.name} llega en la Etapa ${console.plannedStage}.',
                        style: muted),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _enriching ? null : () => _enrich(game),
                    icon: _enriching
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_search_rounded),
                    label: const Text('Identificar y buscar portada'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (states.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Save states')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: states.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final s = states[i];
                  final thumb = s.thumbnailPath;
                  return InkWell(
                    onTap: canPlay ? () => context.push(Routes.player(game.id, slot: s.slot)) : null,
                    child: SizedBox(
                      width: 135,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: 3 / 2,
                            child: thumb != null && File(thumb).existsSync()
                                ? Image.file(File(thumb), fit: BoxFit.cover, filterQuality: FilterQuality.none)
                                : const ColoredBox(color: Colors.black26),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Ranura ${s.slot}', style: theme.textTheme.labelMedium),
                        Text(formatDateTime(s.createdAt),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SectionHeader('Información')),
        SliverList.list(children: [
          _info('Tiempo jugado', formatPlayTime(game.playTimeSeconds)),
          _info('Última partida', game.lastPlayedAt == null ? 'Nunca' : formatDateTime(game.lastPlayedAt!)),
          _info('Añadido', formatDateTime(game.addedAt)),
          _info('Tamaño', game.fileSize == null ? '—' : formatBytes(game.fileSize!)),
          _info('Procedencia', switch (game.sourceId) {
            'local' => 'Importado desde el teléfono',
            'homebrew_hub' => 'Homebrew Hub',
            'itch_io' => 'itch.io',
            'bundled' => 'Incluido en RetroStation (Ajustes > Acerca de > licencias)',
            null => 'Desconocida',
            final s => s,
          }),
          if (game.sourceUrl != null) _info('Origen', game.sourceUrl!, selectable: true),
          if (game.sha1 != null) _info('SHA-1', game.sha1!, selectable: true),
          const SizedBox(height: 32),
        ]),
      ],
    );
  }

  Widget _info(String label, String value, {bool selectable = false}) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: selectable ? SelectableText(value) : Text(value),
      );
}

/// Descarga de un juego pendiente, con su progreso si ya está en curso.
class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(downloadsProvider.select((m) =>
        m.values.where((e) => e.gameId == game.id && e.phase.isActive).firstOrNull));
    if (entry != null) {
      return Column(children: [
        LinearProgressIndicator(value: entry.phase == DownloadPhase.running ? entry.progress : null),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => context.push(Routes.downloads),
          child: Text('${entry.phase.label} · ${(entry.progress * 100).toStringAsFixed(0)} % · Ver descargas'),
        ),
      ]);
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: () async {
          try {
            await ref.read(downloadManagerProvider).enqueueForGame(game.id);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
            }
          }
        },
        icon: const Icon(Icons.download_rounded),
        label: const Text('Descargar'),
      ),
    );
  }
}

/// Cabecera de la ficha: la portada desenfocada de fondo y nítida al frente.
class _Hero extends StatelessWidget {
  const _Hero({required this.game, required this.hasCover});

  final Game game;
  final bool hasCover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final console = ConsoleRegistry.byId(game.consoleId);
    final accent = console?.color ?? theme.colorScheme.primary;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Decodificada a muy poca resolución: se ve desenfocada sin filtros.
        if (hasCover)
          Image.file(
            File(game.coverPath!),
            fit: BoxFit.cover,
            cacheWidth: 40,
            filterQuality: FilterQuality.medium,
          )
        else
          ColoredBox(color: Color.lerp(accent, RetroColors.charcoal, 0.55)!),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.25),
                theme.scaffoldBackgroundColor,
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 56, 0, 20),
            child: Center(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 10)),
                    ],
                  ),
                  child: GameCover(game: game, borderRadius: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
