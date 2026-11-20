import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import 'adapters/homebrew_hub.dart';
import 'adapters/itch_io.dart';
import 'discovery_models.dart';
import 'source_adapter.dart';

/// Registro de fuentes. Para añadir una fuente basta con implementar
/// [SourceAdapter] y añadirla aquí; la interfaz la muestra automáticamente.
final sourceAdaptersProvider = Provider<List<SourceAdapter>>(
  (ref) => [HomebrewHubAdapter(), ItchIoAdapter()],
);

/// Fuentes activas según los ajustes del usuario.
final enabledSourcesProvider = Provider<List<SourceAdapter>>((ref) {
  final disabled = ref.watch(settingsProvider.select((s) => s.disabledSources));
  return ref.watch(sourceAdaptersProvider).where((s) => !disabled.contains(s.id)).toList();
});

/// Resultado de una búsqueda combinada: los fallos de una fuente no impiden
/// mostrar los resultados de las demás.
class SearchResult {
  const SearchResult({
    required this.items,
    required this.errors,
    required this.hasMore,
    this.skippedNoLanguage = const [],
  });

  final List<DiscoveryItem> items;
  final Map<String, String> errors; // nombre de la fuente -> motivo
  final bool hasMore;

  /// Fuentes que no se consultaron porque no publican el idioma.
  final List<String> skippedNoLanguage;
}

class DiscoveryService {
  DiscoveryService(this._sources);

  final List<SourceAdapter> _sources;

  Future<SearchResult> search(DiscoveryQuery query, int page) async {
    final skippedNoLanguage = <String>[];
    final sources = _sources.where((s) {
      if (query.spanishOnly && !s.supportsLanguage) {
        skippedNoLanguage.add(s.name);
        return false;
      }
      if (query.availability != null && s.availability != query.availability &&
          s.availability == Availability.sourcePage) {
        return false; // fuente que entrega el archivo en su web y se pide descarga directa
      }
      if (query.consoleId != null && !s.consoles.contains(query.consoleId)) return false;
      if (query.tag != null && !s.supportsTags) return false;
      return true;
    }).toList();

    final results = await Future.wait(sources.map((s) async {
      try {
        return (source: s, page: await s.search(query, page), error: null);
      } catch (e) {
        return (source: s, page: null, error: '$e');
      }
    }));

    final items = <DiscoveryItem>[];
    final errors = <String, String>{};
    var hasMore = false;
    for (final r in results) {
      if (r.page case final p?) {
        items.addAll(query.availability == null
            ? p.items
            : p.items.where((i) => i.availability == query.availability));
        hasMore |= p.hasMore;
      } else {
        errors[r.source.name] = r.error!;
      }
    }
    return SearchResult(
      items: items,
      errors: errors,
      hasMore: hasMore,
      skippedNoLanguage: skippedNoLanguage,
    );
  }
}

final discoveryServiceProvider =
    Provider<DiscoveryService>((ref) => DiscoveryService(ref.watch(enabledSourcesProvider)));
