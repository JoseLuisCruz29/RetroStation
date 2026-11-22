import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:retrostation/app/app.dart';
import 'package:retrostation/app/version.dart';
import 'package:retrostation/discovery/discovery_models.dart';
import 'package:retrostation/discovery/discovery_service.dart';
import 'package:retrostation/download_manager/download_manager.dart';
import 'package:retrostation/game_library/game_repository.dart';
import 'package:retrostation/save_manager/save_state_repository.dart';
import 'package:retrostation/settings/app_settings.dart';
import 'package:retrostation/storage/app_paths.dart';
import 'package:retrostation/storage/database.dart';
import 'package:retrostation/storage/storage_providers.dart';

/// Repositorio de ajustes en memoria: las pruebas de widgets no abren SQLite
/// (drift usa async real, incompatible con el reloj simulado de testWidgets).
/// La persistencia real está cubierta en test/storage/database_test.dart.
class _MemorySettingsRepository implements SettingsRepository {
  AppSettings saved = const AppSettings();

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

/// Gestor de descargas sin el plugin nativo (no disponible en pruebas).
class _NoDownloads extends DownloadController {
  @override
  Map<String, DownloadEntry> build() => const {};
}

/// Fuente de Descubrir sin red.
class _OfflineDiscovery extends DiscoveryService {
  _OfflineDiscovery() : super(const []);

  @override
  Future<SearchResult> search(DiscoveryQuery query, int page) async =>
      const SearchResult(items: [], errors: {}, hasMore: false);
}

Widget _app(_MemorySettingsRepository settingsRepo,
        {AppSettings initial = const AppSettings(tutorialDone: true, seenVersion: appVersion)}) =>
    ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(initial),
        downloadsProvider.overrideWith(_NoDownloads.new),
        discoveryServiceProvider.overrideWithValue(_OfflineDiscovery()),
        appPathsProvider.overrideWithValue(AppPaths(Directory('/tmp/rs'))),
        storageUsageProvider.overrideWith((ref) async => {'ROMs': 0}),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        libraryProvider.overrideWith((ref, filter) => Stream.value(const <Game>[])),
        gameCountProvider.overrideWith((ref) => Stream.value(0)),
        saveStatesProvider
            .overrideWith((ref) => Stream.value(const <SaveStateWithGame>[])),
      ],
      child: const RetroStationApp(),
    );

/// Simula un teléfono de 360x780 dp (pantalla típica de gama media).
void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  ));
  await _settle(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('navega por las pestañas y abre Consolas', (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(_app(_MemorySettingsRepository()));
    await _settle(tester);

    expect(find.text('RETROSTATION'), findsOneWidget);
    expect(find.text('Tu biblioteca está lista'), findsOneWidget);

    await _tapTab(tester, 'Descubrir');
    expect(find.text('Buscar por nombre'), findsOneWidget);
    expect(find.text('Sin resultados'), findsOneWidget);

    await _tapTab(tester, 'Mis juegos');
    expect(find.text('Aún no tienes juegos'), findsOneWidget);
    expect(find.text('Importar juegos'), findsOneWidget);
    final favChip = find.widgetWithText(ChoiceChip, 'Favoritos');
    await tester.ensureVisible(favChip);
    await _settle(tester);
    await tester.tap(favChip);
    await _settle(tester);
    expect(find.text('Sin favoritos'), findsOneWidget);

    // Las partidas guardadas se abren desde Mis juegos.
    await tester.tap(find.byTooltip('Partidas guardadas'));
    await _settle(tester);
    expect(find.text('No hay save states'), findsOneWidget);
    await tester.pageBack();
    await _settle(tester);

    await _tapTab(tester, 'Ajustes');
    expect(find.text('APARIENCIA'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Consolas y núcleos'), 300,
        scrollable: find
            .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .last);
    await tester.tap(find.text('Consolas y núcleos'));
    await _settle(tester);
    expect(find.text('Game Boy Advance'), findsOneWidget);

    // Tocar una consola abre la biblioteca filtrada; la categoría elegida
    // antes (Favoritos) se conserva.
    await tester.tap(find.text('Game Boy Advance'));
    await _settle(tester);
    expect(find.text('Sin favoritos de Game Boy Advance'), findsOneWidget);
    expect(find.byTooltip('Quitar filtro de consola'), findsOneWidget);
  });

  testWidgets('cambiar el acento se aplica al tema y se guarda', (tester) async {
    _phoneSize(tester);
    final repo = _MemorySettingsRepository();
    await tester.pumpWidget(_app(repo));
    await _settle(tester);

    Color primary() => Theme.of(tester.element(find.byType(NavigationBar)))
        .colorScheme
        .primary;
    expect(primary(), const Color(0xFF8FDCEF)); // cian

    await _tapTab(tester, 'Ajustes');
    await tester.tap(find.text('Ámbar'));
    await _settle(tester);

    expect(primary(), const Color(0xFFFFCF6B)); // ámbar
    expect(repo.saved.accent, AccentColor.ambar);
  });

  testWidgets('en horizontal usa la barra lateral con el logo', (tester) async {
    tester.view.physicalSize = const Size(2340, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_MemorySettingsRepository()));
    await _settle(tester);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('Consolas'),
    ));
    await _settle(tester);
    expect(find.text('Game Boy Advance'), findsOneWidget);
  });

  testWidgets('el tutorial guía por la app y se puede saltar', (tester) async {
    _phoneSize(tester);
    final repo = _MemorySettingsRepository();
    await tester.pumpWidget(_app(repo, initial: const AppSettings()));
    await _settle(tester);

    expect(find.text('BIENVENIDO A RETROSTATION'), findsOneWidget);
    expect(find.text('Saltar tutorial'), findsOneWidget);

    // Paso 3: lleva a "Mis juegos" y explica cómo importar.
    await tester.tap(find.text('Siguiente'));
    await _settle(tester);
    await tester.tap(find.text('Siguiente'));
    await _settle(tester);
    expect(find.text('AÑADE TUS JUEGOS'), findsOneWidget);
    expect(find.text('Aún no tienes juegos'), findsOneWidget);

    // Atrás vuelve al paso anterior.
    await tester.tap(find.text('Atrás'));
    await _settle(tester);
    expect(find.text('INICIO'), findsOneWidget);

    await tester.tap(find.text('Saltar tutorial'));
    await _settle(tester);
    expect(find.text('Saltar tutorial'), findsNothing);
    expect(repo.saved.tutorialDone, isTrue);
    expect(repo.saved.seenVersion, appVersion, reason: 'el tutorial ya cuenta las novedades');
  });

  testWidgets('el tutorial incluye el paso del multijugador', (tester) async {
    _phoneSize(tester);
    final repo = _MemorySettingsRepository();
    await tester.pumpWidget(_app(repo, initial: const AppSettings()));
    await _settle(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Siguiente'));
      await _settle(tester);
    }
    expect(find.text('¡NUEVO! MULTIJUGADOR LAN'), findsOneWidget);
  });

  testWidgets('quien actualiza ve una vez las novedades del multijugador', (tester) async {
    _phoneSize(tester);
    final repo = _MemorySettingsRepository();
    await tester.pumpWidget(_app(repo, initial: const AppSettings(tutorialDone: true, seenVersion: '2.0.0')));
    await _settle(tester);
    expect(find.text('Novedades de la $appVersion'), findsOneWidget);
    expect(repo.saved.seenVersion, appVersion);
    await tester.tap(find.text('Ahora no'));
    await _settle(tester);
    expect(find.text('Novedades de la $appVersion'), findsNothing);
  });
}
