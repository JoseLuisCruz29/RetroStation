import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../discovery/discovery_models.dart';
import '../../discovery/discovery_service.dart';
import '../../engines/console_registry.dart';
import '../widgets/empty_state.dart';

/// Game Discovery: busca en las fuentes externas activas.
class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _text = TextEditingController();
  DiscoveryQuery _query = const DiscoveryQuery();
  final _items = <DiscoveryItem>[];
  Map<String, String> _errors = const {};
  List<String> _skippedNoLanguage = const [];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = false;
  int _generation = 0; // descarta respuestas de búsquedas anteriores

  static const _consoles = ['gba', 'gbc', 'gb', 'nes', 'snes'];
  static const _tags = [
    'Puzzle', 'Platformer', 'RPG', 'Action', 'Adventure', 'Shooter',
    'Arcade', 'Strategy', 'Racing', 'Sports', 'Open Source',
  ];

  @override
  void initState() {
    super.initState();
    _search(reset: true);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _search({bool reset = false}) async {
    final generation = reset ? ++_generation : _generation;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      if (reset) {
        _items.clear();
        _errors = const {};
      }
    });
    final result = await ref.read(discoveryServiceProvider).search(_query, page);
    if (!mounted || generation != _generation) return;
    setState(() {
      _items.addAll(result.items);
      _errors = result.errors;
      _skippedNoLanguage = result.skippedNoLanguage;
      _hasMore = result.hasMore;
      _page = page;
      _loading = false;
    });
  }

  void _update(DiscoveryQuery q) {
    setState(() => _query = q);
    _search(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(enabledSourcesProvider);
    ref.listen(enabledSourcesProvider, (_, _) => _search(reset: true));
    return Scaffold(
      appBar: AppBar(title: const Text('Descubrir')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              controller: _text,
              hintText: 'Buscar por nombre',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_text.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _text.clear();
                      _update(_query.copyWith(text: ''));
                    },
                  ),
              ],
              onSubmitted: (v) => _update(_query.copyWith(text: v)),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('En español'),
                    avatar: const Icon(Icons.translate_rounded, size: 18),
                    selected: _query.spanishOnly,
                    onSelected: (v) => _update(_query.copyWith(spanishOnly: v)),
                  ),
                ),
                _menuChip<String>(
                  label: _query.consoleId == null
                      ? 'Consola'
                      : ConsoleRegistry.byId(_query.consoleId!)!.shortName,
                  active: _query.consoleId != null,
                  values: _consoles,
                  itemLabel: (c) => ConsoleRegistry.byId(c)!.name,
                  onSelected: (c) => _update(_query.copyWith(consoleId: () => c)),
                ),
                _menuChip<String>(
                  label: _query.tag ?? 'Género',
                  active: _query.tag != null,
                  values: _tags,
                  itemLabel: (t) => t,
                  onSelected: (t) => _update(_query.copyWith(tag: () => t)),
                ),
                _menuChip<int>(
                  label: _query.year?.toString() ?? 'Año',
                  active: _query.year != null,
                  values: [for (var y = DateTime.now().year; y >= 1999; y--) y],
                  itemLabel: (y) => '$y',
                  onSelected: (y) => _update(_query.copyWith(year: () => y)),
                ),
                _menuChip<Availability>(
                  label: _query.availability?.label ?? 'Disponibilidad',
                  active: _query.availability != null,
                  values: Availability.values,
                  itemLabel: (a) => a.label,
                  onSelected: (a) => _update(_query.copyWith(availability: () => a)),
                ),
              ],
            ),
          ),
          if (_skippedNoLanguage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                '${_skippedNoLanguage.join(', ')} no indica el idioma de sus juegos, así que no '
                'se incluye con este filtro. El idioma es el que declara el autor en itch.io.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          if (_errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Sin respuesta de: ${_errors.keys.join(', ')}. Se muestran las demás fuentes.',
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          Expanded(child: _results(sources.isEmpty)),
        ],
      ),
    );
  }

  Widget _results(bool noSources) {
    if (noSources) {
      return const EmptyState(
        icon: Icons.source_outlined,
        title: 'No hay fuentes activas',
        message: 'Activa al menos una fuente en Ajustes > Fuentes de Descubrir.',
      );
    }
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return EmptyState(
        icon: Icons.travel_explore_rounded,
        title: _errors.isNotEmpty ? 'No se pudo consultar' : 'Sin resultados',
        message: _errors.isNotEmpty
            ? 'Comprueba tu conexión e inténtalo de nuevo.'
            : 'Prueba con otro nombre o quita filtros.',
        action: OutlinedButton(onPressed: () => _search(reset: true), child: const Text('Reintentar')),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _hasMore
              ? OutlinedButton(onPressed: _search, child: const Text('Cargar más'))
              : const SizedBox.shrink();
        }
        final item = _items[i];
        return DiscoveryTile(
          item: item,
          sourceName: ref
                  .read(sourceAdaptersProvider)
                  .where((s) => s.id == item.sourceId)
                  .firstOrNull
                  ?.name ??
              item.sourceId,
          onTap: () => context.push(Routes.discoveryItem, extra: item),
        );
      },
    );
  }

  Widget _menuChip<T>({
    required String label,
    required bool active,
    required List<T> values,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<Object>(
        tooltip: label,
        onSelected: (v) => onSelected(v is _Clear ? null : v as T),
        itemBuilder: (_) => [
          if (active) const PopupMenuItem(value: _Clear(), child: Text('Quitar filtro')),
          for (final v in values) PopupMenuItem(value: v, child: Text(itemLabel(v))),
        ],
        child: Chip(
          label: Text(label),
          avatar: Icon(active ? Icons.check_rounded : Icons.arrow_drop_down_rounded, size: 18),
          backgroundColor: active ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25) : null,
        ),
      ),
    );
  }
}

class _Clear {
  const _Clear();
}

class DiscoveryTile extends StatelessWidget {
  const DiscoveryTile({super.key, required this.item, required this.sourceName, required this.onTap});

  final DiscoveryItem item;
  final String sourceName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              height: 84,
              child: item.coverUrl == null
                  ? const ColoredBox(color: Colors.black26, child: Icon(Icons.image_not_supported_outlined))
                  : Image.network(
                      item.coverUrl.toString(),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Colors.black26, child: Icon(Icons.broken_image_outlined)),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    Text(
                      [
                        item.platformLabel,
                        if (item.developers.isNotEmpty) item.developers.join(', '),
                        if (item.year != null) '${item.year}',
                      ].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _Badge(
                        item.availability.label,
                        item.availability == Availability.downloadable ? Colors.greenAccent : Colors.amberAccent,
                      ),
                      _Badge(sourceName, theme.colorScheme.primary),
                      if (item.price != null) _Badge(item.price!, theme.colorScheme.secondary),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
