import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retrostation/game_library/rom_importer.dart';
import 'package:retrostation/multiplayer/game_transfer.dart';
import 'package:retrostation/settings/app_settings.dart';
import 'package:retrostation/storage/app_paths.dart';
import 'package:retrostation/storage/database.dart';
import 'package:retrostation/storage/storage_providers.dart';

import '../support/test_env.dart';

/// Un dispositivo de prueba: su base de datos, sus carpetas y su controlador.
class _Device {
  _Device(this.db, this.paths, String name)
      : container = ProviderContainer(overrides: [
          initialSettingsProvider.overrideWithValue(AppSettings(playerName: name)),
          appPathsProvider.overrideWithValue(paths),
          romImporterProvider.overrideWithValue(RomImporter(db, paths)),
        ]);

  final AppDatabase db;
  final AppPaths paths;
  final ProviderContainer container;

  GameTransferController get transfer => container.read(gameTransferProvider.notifier);
  TransferState get state => container.read(gameTransferProvider);

  static Future<_Device> create(String name) async => _Device(memoryDatabase(), await tempPaths(), name);

  Future<void> dispose() async {
    container.dispose();
    await db.close();
    await paths.root.delete(recursive: true);
  }
}

Future<void> _until(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('tiempo agotado');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late _Device sender;
  late _Device receiver;
  late List<Game> games;

  setUp(() async {
    // Un puerto libre por prueba: sin choques con conexiones que aún se cierran.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    TransferPort.current = probe.port;
    await probe.close();
    sender = await _Device.create('Emisor');
    receiver = await _Device.create('Receptor');
    final src = Directory.systemTemp.createTempSync('rs_send_');
    // Nombre con acentos y eñe: viaja tal cual.
    File('test/fixtures/gba-tests/arm.gba').copySync(p.join(src.path, 'Pokémon Edición Año.gba'));
    File('test/fixtures/gba-tests/thumb.gba').copySync(p.join(src.path, 'thumb.gba'));
    await RomImporter(sender.db, sender.paths)
        .importFiles([for (final f in src.listSync()) f.path], moveSources: true);
    src.deleteSync(recursive: true);
    games = await sender.db.select(sender.db.games).get();
    expect(games, hasLength(2));
    await receiver.transfer.listen();
  });

  tearDown(() async {
    await receiver.transfer.stopListening();
    await sender.dispose();
    await receiver.dispose();
  });

  test('envía dos juegos y el otro los tiene en su biblioteca', () async {
    final sub = receiver.container.listen(gameTransferProvider, (prev, next) {
      if (next.offer != null && prev?.offer == null) {
        expect(next.offer!.peerName, 'Emisor');
        expect(next.offer!.games, hasLength(2));
        receiver.transfer.answerOffer(true);
      }
    });
    addTearDown(sub.close);

    await sender.transfer.send(InternetAddress.loopbackIPv4, 'Receptor', games);
    expect(sender.state.progress!.phase, TransferPhase.finished, reason: sender.state.progress!.message);
    expect(sender.state.progress!.message, contains('2 juegos'));
    await _until(() => receiver.state.progress?.phase == TransferPhase.finished);

    final got = await receiver.db.select(receiver.db.games).get();
    expect({for (final g in got) g.sha1}, {for (final g in games) g.sha1});
    expect(got.every((g) => g.sourceId == 'lan' && File(g.romPath!).existsSync()), isTrue);
    expect(got.map((g) => p.basename(g.romPath!)), contains('Pokémon Edición Año.gba'));
    // La carpeta temporal de recepción no queda.
    expect(receiver.paths.downloads.listSync().where((e) => p.basename(e.path).startsWith('recibidos_')), isEmpty);

    // Otra vez: ya los tiene.
    await sender.transfer.send(InternetAddress.loopbackIPv4, 'Receptor', games);
    expect(sender.state.progress!.message, contains('ya tenía'));
  });

  test('si el otro rechaza, no se envía nada', () async {
    final sub = receiver.container.listen(gameTransferProvider, (prev, next) {
      if (next.offer != null && prev?.offer == null) receiver.transfer.answerOffer(false);
    });
    addTearDown(sub.close);

    await sender.transfer.send(InternetAddress.loopbackIPv4, 'Receptor', games.take(1).toList());
    expect(sender.state.progress!.phase, TransferPhase.failed);
    expect(sender.state.progress!.message, contains('no aceptó'));
    expect(await receiver.db.select(receiver.db.games).get(), isEmpty);
  });

  test('sin nadie escuchando, avisa', () async {
    await receiver.transfer.stopListening();
    await sender.transfer.send(InternetAddress.loopbackIPv4, 'Receptor', games);
    expect(sender.state.progress!.phase, TransferPhase.failed);
    expect(sender.state.progress!.message, contains('No se pudo conectar'));
  });
}
