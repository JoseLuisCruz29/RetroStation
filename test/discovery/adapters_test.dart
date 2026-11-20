import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/discovery/adapters/homebrew_hub.dart';
import 'package:retrostation/discovery/adapters/itch_io.dart';
import 'package:retrostation/discovery/discovery_models.dart';
import 'package:retrostation/discovery/discovery_service.dart';
import 'package:retrostation/discovery/source_adapter.dart';

final _hhJson = File('test/fixtures/discovery/hh_search_gba.json').readAsStringSync();
final _itchXml = File('test/fixtures/discovery/itch_gba.xml').readAsStringSync();

void main() {
  group('Homebrew Hub', () {
    test('construye la URL de búsqueda con los filtros de la API real', () async {
      Uri? requested;
      final hh = HomebrewHubAdapter(fetch: (u) async {
        requested = u;
        return _hhJson;
      });
      await hh.search(const DiscoveryQuery(text: ' tetris ', consoleId: 'gba', tag: 'Puzzle'), 2);
      expect(requested!.host, 'hh3.gbdev.io');
      expect(requested!.path, '/api/search');
      expect(requested!.queryParameters,
          {'platform': 'GBA', 'q': 'tetris', 'tags': 'Puzzle', 'page': '2'});
    });

    test('parsea entradas reales: archivos, capturas, desarrolladores y procedencia', () async {
      final hh = HomebrewHubAdapter(fetch: (_) async => _hhJson);
      final page = await hh.search(const DiscoveryQuery(consoleId: 'gba'), 3);
      expect(page.items, isNotEmpty);
      for (final item in page.items) {
        expect(item.sourceId, 'homebrew_hub');
        expect(item.consoleId, 'gba');
        expect(item.pageUrl.toString(), contains('/entries/${item.remoteId}'));
        for (final f in item.files) {
          expect(f.url.host, 'hh3.gbdev.io');
          expect(f.url.path, startsWith('/static/database-gba/entries/${item.remoteId}/'));
        }
        if (item.files.isNotEmpty) expect(item.availability, Availability.downloadable);
      }
      // Desarrolladores en forma de lista (entrada real "6teloiv_hive-keepers-advance").
      final multi = page.items.where((i) => i.developers.length > 1);
      expect(multi, isNotEmpty);
    });

    test('consola sin cobertura en la fuente no hace peticiones', () async {
      var calls = 0;
      final hh = HomebrewHubAdapter(fetch: (_) async {
        calls++;
        return _hhJson;
      });
      final page = await hh.search(const DiscoveryQuery(consoleId: 'psx'), 1);
      expect(page.items, isEmpty);
      expect(calls, 0);
    });
  });

  group('itch.io', () {
    test('parsea el RSS real: solo enlaces, precio y página de itch', () async {
      final itch = ItchIoAdapter(fetch: (_) async => _itchXml);
      final page = await itch.search(const DiscoveryQuery(), 1);
      expect(page.items, isNotEmpty);
      for (final item in page.items) {
        expect(item.availability, Availability.sourcePage);
        expect(item.files, isEmpty);
        expect(item.pageUrl.host, endsWith('itch.io'));
        // Se usa <plainTitle>: sin las etiquetas de precio/descuento de <title>.
        expect(item.title, isNot(contains(r'$')));
        expect(item.title, isNot(contains('% Off')));
      }
      expect(page.items.any((i) => i.price == 'Gratis'), isTrue);
    });

    test('filtra por texto en local', () async {
      final itch = ItchIoAdapter(fetch: (_) async => _itchXml);
      final all = (await itch.search(const DiscoveryQuery(), 1)).items;
      final word = all.first.title.split(' ').first;
      final filtered = (await itch.search(DiscoveryQuery(text: word.toLowerCase()), 1)).items;
      expect(filtered, isNotEmpty);
      expect(filtered.length, lessThanOrEqualTo(all.length));
    });
  });

  group('DiscoveryService', () {
    test('combina fuentes y tolera que una falle', () async {
      final service = DiscoveryService([
        HomebrewHubAdapter(fetch: (_) async => _hhJson),
        _FailingSource(),
      ]);
      final result = await service.search(const DiscoveryQuery(consoleId: 'gba'), 1);
      expect(result.items, isNotEmpty);
      expect(result.errors.keys, ['Fuente rota']);
    });

    test('pedir solo descargables excluye las fuentes de solo enlace', () async {
      var itchCalls = 0;
      final service = DiscoveryService([
        HomebrewHubAdapter(fetch: (_) async => _hhJson),
        ItchIoAdapter(fetch: (_) async {
          itchCalls++;
          return _itchXml;
        }),
      ]);
      final result = await service.search(
          const DiscoveryQuery(availability: Availability.downloadable), 1);
      expect(itchCalls, 0);
      expect(result.items.every((i) => i.availability == Availability.downloadable), isTrue);
    });

    test('"En español" usa el filtro de idioma de itch.io y excluye Homebrew Hub', () async {
      final urls = <Uri>[];
      var hhCalls = 0;
      final service = DiscoveryService([
        HomebrewHubAdapter(fetch: (_) async {
          hhCalls++;
          return _hhJson;
        }),
        ItchIoAdapter(fetch: (u) async {
          urls.add(u);
          return _itchXml;
        }),
      ]);
      final result = await service.search(const DiscoveryQuery(spanishOnly: true), 1);
      expect(hhCalls, 0);
      expect(result.skippedNoLanguage, ['Homebrew Hub']);
      expect(urls, isNotEmpty);
      expect(urls.every((u) => u.path.startsWith('/games/lang-es/')), isTrue);
    });
  });

  group('itch.io por consola', () {
    test('cada consola usa su feed y marca sus resultados', () async {
      final urls = <Uri>[];
      final itch = ItchIoAdapter(fetch: (u) async {
        urls.add(u);
        return _itchXml;
      });
      final nes = await itch.search(const DiscoveryQuery(consoleId: 'nes'), 1);
      expect(urls.single.path, '/games/tag-nes.xml');
      expect(nes.items.every((i) => i.consoleId == 'nes'), isTrue);

      urls.clear();
      final all = await itch.search(const DiscoveryQuery(), 1);
      expect(urls.map((u) => u.path), containsAll(['/games/tag-gameboy-advance.xml', '/games/made-with-gb-studio.xml']));
      // El mismo juego en varios feeds aparece una sola vez.
      expect(all.items.map((i) => i.remoteId).toSet().length, all.items.length);
    });

    test('una consola sin feed en itch.io no hace peticiones', () async {
      var calls = 0;
      final itch = ItchIoAdapter(fetch: (_) async {
        calls++;
        return _itchXml;
      });
      expect((await itch.search(const DiscoveryQuery(consoleId: 'psx'), 1)).items, isEmpty);
      expect(calls, 0);
    });
  });
}

class _FailingSource implements SourceAdapter {
  @override
  String get id => 'broken';
  @override
  String get name => 'Fuente rota';
  @override
  String get description => '';
  @override
  Availability get availability => Availability.downloadable;
  @override
  Set<String> get consoles => {'gba'};
  @override
  bool get supportsTags => false;
  @override
  bool get supportsLanguage => false;
  @override
  Future<DiscoveryPage> search(DiscoveryQuery query, int page) =>
      Future.error(const SocketException('sin red'));
}
