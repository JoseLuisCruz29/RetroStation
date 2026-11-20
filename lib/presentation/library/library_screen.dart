import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/router.dart';
import '../../download_manager/download_manager.dart';
import '../../engines/console_registry.dart';
import '../../game_library/game_repository.dart';
import '../../game_library/rom_importer.dart';
import '../../game_library/rom_scanner.dart';
import '../../metadata/metadata_service.dart';
import '../tutorial/tutorial_overlay.dart';
import '../widgets/empty_state.dart';
import '../widgets/game_card.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.consoleId});

  /// Filtro por consola recibido desde la URL (`/library?console=gba`).
  final String? consoleId;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  LibraryCategory _category = LibraryCategory.all;
  bool _scanning = false;

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final result = await ref.read(romScannerProvider).scan();
      if (!mounted) return;
      final parts = [
        if (result.added.isEmpty) 'No hay ROMs nuevos'
        else '${result.added.length} juego(s) añadido(s)',
        if (result.rejected.isNotEmpty)
          '${result.rejected.length} archivo(s) rechazado(s): '
              '${result.rejected.first.reason}',
      ];
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  bool _importing = false;

  /// Elige ROMs o ZIP del teléfono, los valida e importa, y después intenta
  /// identificarlos y descargar su portada.
  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.any, // los filtros por extensión de SAF no reconocen .gba
      dialogTitle: 'Elige ROMs o archivos ZIP',
    );
    final paths = <String>[
      for (final f in picked)
        if (f.path != null) f.path!,
    ];
    if (paths.isEmpty || !mounted) return;
    setState(() => _importing = true);
    try {
      // En Android el selector entrega copias en la caché de la app: se mueven
      // (no hace falta el doble de espacio con juegos de varios GB). Si alguna
      // ruta no está en la caché, se copia y el original no se toca.
      final cache = (await getTemporaryDirectory()).path;
      final report = await ref.read(romImporterProvider).importFiles(
            paths,
            moveSources: paths.every((x) => p.isWithin(cache, x)),
          );
      // Los archivos que entrega el selector son copias temporales.
      await FilePicker.clearTemporaryFiles();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => _ImportReportDialog(report: report),
      );
      // Identificación en segundo plano (necesita red; si falla, se puede
      // reintentar desde la ficha del juego).
      final metadata = ref.read(metadataServiceProvider);
      final repo = ref.read(gameRepositoryProvider);
      for (final id in report.added) {
        final game = await repo.watchById(id).first;
        if (game != null) await metadata.enrich(game);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final console =
        widget.consoleId == null ? null : ConsoleRegistry.byId(widget.consoleId!);
    final filter = LibraryFilter(category: _category, consoleId: console?.id);
    final games = ref.watch(libraryProvider(filter));

    return Scaffold(
      // Con la biblioteca vacía, el estado vacío ya ofrece "Importar juegos".
      floatingActionButton: (games.value?.isEmpty ?? true) && _category == LibraryCategory.all
          ? null
          : FloatingActionButton.extended(
              key: TutorialTargets.importButton,
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_rounded),
        label: Text(_importing ? 'Importando…' : 'Importar'),
      ),
      appBar: AppBar(
        title: const Text('Mis juegos'),
        actions: [
          Consumer(builder: (context, ref, _) {
            final active = ref.watch(downloadsProvider.select(
                (m) => m.values.where((e) => e.phase.isActive).length));
            return IconButton(
              tooltip: 'Descargas',
              onPressed: () => context.push(Routes.downloads),
              icon: Badge(
                isLabelVisible: active > 0,
                label: Text('$active'),
                child: const Icon(Icons.download_rounded),
              ),
            );
          }),
          IconButton(
            tooltip: 'Buscar ROMs nuevos',
            icon: _scanning
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _scanning ? null : _scan,
          ),
          IconButton(
            tooltip: 'Partidas guardadas',
            icon: const Icon(Icons.save_rounded),
            onPressed: () => context.push(Routes.saves),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                // El filtro de consola queda fijo para que siempre sea visible.
                if (console != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: InputChip(
                      label: Text(console.shortName),
                      avatar: Icon(Icons.memory_rounded,
                          size: 16, color: console.color),
                      onDeleted: () => context.go(Routes.library),
                      deleteButtonTooltipMessage: 'Quitar filtro de consola',
                    ),
                  ),
                Expanded(child: _categoryChips()),
              ],
            ),
          ),
          Expanded(
            key: TutorialTargets.library,
            child: games.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error al leer la biblioteca: $e')),
              data: (list) => list.isEmpty
                  ? _empty(console?.name)
                  : GridView.builder(
                      // Espacio inferior para que el botón Importar no tape
                      // la última fila.
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.6,
                      ),
                      itemCount: list.length,
                      itemBuilder: (_, i) => GameCard(
                        game: list[i],
                        onTap: () => context.push(Routes.game(list[i].id)),
                        onToggleFavorite: () => ref
                            .read(gameRepositoryProvider)
                            .setFavorite(list[i].id, !list[i].isFavorite),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChips() => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in LibraryCategory.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.label),
                selected: c == _category,
                onSelected: (_) => setState(() => _category = c),
              ),
            ),
        ],
      );

  Widget _empty(String? consoleName) {
    final where = consoleName == null ? '' : ' de $consoleName';
    final (title, message) = switch (_category) {
      LibraryCategory.all => (
          'Aún no tienes juegos',
          'No hay juegos$where. Importa ROMs o ZIP desde el teléfono, o busca '
              'juegos de libre distribución en Descubrir.',
        ),
      LibraryCategory.installed => (
          'Sin juegos instalados$where',
          'Aquí aparecerán los juegos cuyo archivo ya está en RetroStation.',
        ),
      LibraryCategory.favorites => (
          'Sin favoritos$where',
          'Toca el corazón de un juego para añadirlo a favoritos.',
        ),
      LibraryCategory.recent => (
          'Sin partidas recientes$where',
          'Los juegos que abras aparecerán aquí ordenados por fecha.',
        ),
      LibraryCategory.pending => (
          'Nada pendiente$where',
          'Aquí verás juegos guardados desde Descubrir que aún no tienen archivo.',
        ),
    };
    return EmptyState(
      icon: Icons.sports_esports_outlined,
      title: title,
      message: message,
      action: _category == LibraryCategory.all
          ? FilledButton.icon(
              key: TutorialTargets.importButton,
              onPressed: _importing ? null : _import,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Importar juegos'),
            )
          : null,
      secondaryAction: _category == LibraryCategory.all
          ? OutlinedButton.icon(
              onPressed: () => context.go(Routes.discovery),
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text('Descubrir'),
            )
          : null,
    );
  }
}

class _ImportReportDialog extends StatelessWidget {
  const _ImportReportDialog({required this.report});

  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(report.added.isEmpty
          ? 'No se importó ningún juego'
          : '${report.added.length} juego(s) importado(s)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (report.added.isNotEmpty)
              const Text('Se buscará su nombre oficial y su portada si hay conexión.'),
            if (report.rejected.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Descartados:', style: theme.textTheme.titleSmall),
              for (final (name, reason) in report.rejected)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('• $name — $reason', style: theme.textTheme.bodySmall),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              'Importa solo copias de juegos que tengas derecho a usar.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar')),
      ],
    );
  }
}
