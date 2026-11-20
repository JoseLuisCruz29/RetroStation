import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../game_library/rom_importer.dart';
import '../game_library/rom_inspector.dart';
import '../settings/app_settings.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';

/// Envío de juegos (ROMs) a otro dispositivo de la misma red, entre teléfonos
/// o entre el PC y un teléfono. Usa el mismo descubrimiento que el
/// multijugador; la transferencia va por su propio puerto TCP:
///
/// 1. El que envía conecta y manda una línea JSON con la oferta (`offer`).
/// 2. El que recibe la acepta o la rechaza (`accept` / `reject`).
/// 3. Se envían los archivos seguidos, en bruto, con los tamaños de la oferta.
/// 4. El que recibe los importa como cualquier ROM y responde `done`.
abstract final class TransferPort {
  static const value = 55438;

  /// Puerto en uso (las pruebas usan otro para no chocar con envíos anteriores).
  static int current = value;
}

const _transferProtocol = 1;
const _maxFiles = 64;
const _maxTotal = 8 * 1024 * 1024 * 1024; // 8 GB
const _maxHeader = 256 * 1024;

/// Un juego de la oferta (lo que ve quien recibe).
class OfferedGame {
  const OfferedGame({required this.title, required this.consoleId, required this.size});
  final String title;
  final String consoleId;
  final int size;
}

/// Alguien quiere enviarnos juegos.
class IncomingOffer {
  const IncomingOffer({required this.peerName, required this.games, required this.total});
  final String peerName;
  final List<OfferedGame> games;
  final int total;
}

enum TransferPhase { waiting, sending, receiving, importing, finished, failed }

class TransferProgress {
  const TransferProgress({
    required this.outgoing,
    required this.peerName,
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.message,
  });

  final bool outgoing;
  final String peerName;
  final TransferPhase phase;
  final int done;
  final int total;
  final String? message;

  bool get active =>
      phase == TransferPhase.waiting ||
      phase == TransferPhase.sending ||
      phase == TransferPhase.receiving ||
      phase == TransferPhase.importing;

  double? get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : null;

  TransferProgress copyWith({TransferPhase? phase, int? done, int? total, String? message}) =>
      TransferProgress(
        outgoing: outgoing,
        peerName: peerName,
        phase: phase ?? this.phase,
        done: done ?? this.done,
        total: total ?? this.total,
        message: message ?? this.message,
      );
}

class TransferState {
  const TransferState({this.offer, this.progress});
  final IncomingOffer? offer;
  final TransferProgress? progress;
}

/// Archivos que forman un juego: el ROM y, en discos `.cue`, sus pistas.
List<File> gameFiles(Game game) {
  final path = game.romPath;
  if (path == null) return const [];
  final main = File(path);
  if (p.extension(path).toLowerCase() != '.cue') return [main];
  try {
    final dir = p.dirname(path);
    return [
      main,
      for (final track in RomInspector.cueTrackFiles(main.readAsStringSync(encoding: latin1)))
        File(p.join(dir, track)),
    ];
  } on Object {
    return [main];
  }
}

/// Nombre de archivo seguro (sin carpetas ni caracteres raros).
String _safeName(String name) {
  final base = p.basename(name.replaceAll('\\', '/')).replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  return base.isEmpty || base == '.' || base == '..' ? 'juego' : base;
}

class GameTransferController extends Notifier<TransferState> {
  ServerSocket? _server;
  Socket? _incoming; // conexión de la oferta pendiente o en curso
  Completer<bool>? _decision;
  bool _cancelled = false;

  @override
  TransferState build() {
    ref.onDispose(() {
      unawaited(_server?.close());
      _incoming?.destroy();
    });
    return const TransferState();
  }

  String get _myName {
    final n = ref.read(settingsProvider).playerName.trim();
    return n.isEmpty ? 'Jugador' : n;
  }

  /// Empieza a aceptar ofertas (mientras la sección de red está abierta).
  Future<void> listen() async {
    if (_server != null) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, TransferPort.current, shared: true);
      _server!.listen(_onConnection);
    } on SocketException {
      // Puerto ocupado: se podrá enviar, pero no recibir.
    }
  }

  /// Deja de aceptar ofertas nuevas (lo que esté en curso sigue).
  Future<void> stopListening() async {
    final server = _server;
    _server = null;
    await server?.close();
  }

  void clearFinished() {
    if (state.progress?.active ?? false) return;
    state = TransferState(offer: state.offer);
  }

  // --- Enviar -------------------------------------------------------------------

  Future<void> send(InternetAddress address, String peerName, List<Game> games) async {
    if (state.progress?.active ?? false) return;
    _cancelled = false;
    final files = <File>[];
    final offered = <Map<String, Object?>>[];
    for (final g in games) {
      final list = gameFiles(g);
      var size = 0;
      for (final f in list) {
        if (!f.existsSync()) continue;
        files.add(f);
        size += f.lengthSync();
      }
      offered.add({'title': g.title, 'console': g.consoleId, 'size': size});
    }
    final total = files.fold<int>(0, (a, f) => a + f.lengthSync());
    var progress = TransferProgress(outgoing: true, peerName: peerName, phase: TransferPhase.waiting, total: total);
    state = TransferState(offer: state.offer, progress: progress);
    void update(TransferProgress next) {
      progress = next;
      state = TransferState(offer: state.offer, progress: next);
    }

    if (files.isEmpty) {
      update(progress.copyWith(phase: TransferPhase.failed, message: 'No se encontraron los archivos de esos juegos.'));
      return;
    }
    Socket socket;
    try {
      socket = await Socket.connect(address, TransferPort.current, timeout: const Duration(seconds: 5));
    } on Object {
      update(progress.copyWith(
          phase: TransferPhase.failed, message: 'No se pudo conectar con $peerName. ¿Tiene abierta la sección?'));
      return;
    }
    final lines = StreamIterator(utf8.decoder.bind(socket).transform(const LineSplitter()));
    Future<Map<String, dynamic>?> next(Duration timeout) async {
      try {
        if (!await lines.moveNext().timeout(timeout)) return null;
        final m = jsonDecode(lines.current);
        return m is Map<String, dynamic> ? m : null;
      } on Object {
        return null;
      }
    }

    try {
      socket.write('${jsonEncode({
            't': 'offer',
            'v': _transferProtocol,
            'name': _myName,
            'games': offered,
            'files': [
              for (final f in files) {'name': _safeName(f.path), 'size': f.lengthSync()}
            ],
          })}\n');
      await socket.flush();
      final answer = await next(const Duration(minutes: 2));
      if (answer?['t'] != 'accept') {
        update(progress.copyWith(
          phase: TransferPhase.failed,
          message: answer?['t'] == 'busy'
              ? '$peerName está recibiendo otros juegos. Prueba en un momento.'
              : answer?['t'] == 'reject'
                  ? '$peerName no aceptó los juegos.'
                  : '$peerName no respondió.',
        ));
        return;
      }
      update(progress.copyWith(phase: TransferPhase.sending));
      var sent = 0;
      var lastUpdate = DateTime.now();
      for (final f in files) {
        await socket.addStream(f.openRead().map((chunk) {
          if (_cancelled) throw const SocketException('cancelado');
          sent += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastUpdate) > const Duration(milliseconds: 150)) {
            lastUpdate = now;
            update(progress.copyWith(done: sent));
          }
          return chunk;
        }));
      }
      await socket.flush();
      update(progress.copyWith(done: total, phase: TransferPhase.importing));
      final done = await next(const Duration(minutes: 10));
      if (done?['t'] != 'done') {
        update(progress.copyWith(phase: TransferPhase.failed, message: 'Se cortó la conexión con $peerName.'));
        return;
      }
      final added = done!['added'] as int? ?? 0;
      final rejected = (done['rejected'] as List?)?.cast<Object?>().length ?? 0;
      update(progress.copyWith(
        phase: TransferPhase.finished,
        message: added == 0
            ? '$peerName ya tenía ${games.length == 1 ? 'ese juego' : 'esos juegos'}.'
            : 'Enviado${added == 1 ? '' : 's'} $added juego${added == 1 ? '' : 's'} a $peerName'
                '${rejected > 0 ? ' ($rejected ya los tenía o no eran válidos)' : ''}.',
      ));
    } on Object {
      update(progress.copyWith(
          phase: TransferPhase.failed,
          message: _cancelled ? 'Envío cancelado.' : 'Se cortó la conexión con $peerName.'));
    } finally {
      await lines.cancel();
      socket.destroy();
    }
  }

  /// Cancela el envío o la recepción en curso.
  void cancel() {
    _cancelled = true;
    _incoming?.destroy();
  }

  // --- Recibir ------------------------------------------------------------------

  void _onConnection(Socket socket) {
    if (_incoming != null || (state.progress?.active ?? false)) {
      socket.write('${jsonEncode({'t': 'busy'})}\n');
      unawaited(socket.flush().whenComplete(socket.destroy));
      return;
    }
    _incoming = socket;
    _cancelled = false;
    unawaited(_receive(socket).whenComplete(() {
      if (_incoming == socket) _incoming = null;
      socket.destroy();
    }));
  }

  /// Respuesta del usuario a la oferta pendiente.
  void answerOffer(bool accept) {
    final d = _decision;
    _decision = null;
    state = TransferState(progress: state.progress);
    if (d != null && !d.isCompleted) d.complete(accept);
  }

  Future<void> _receive(Socket socket) async {
    final paths = ref.read(appPathsProvider);
    final buffer = BytesBuilder(copy: false);
    final chunks = StreamIterator<Uint8List>(socket);
    Uint8List pending = Uint8List(0); // bytes ya leídos y no usados

    // 1. Oferta: una línea JSON.
    Map<String, dynamic>? offer;
    try {
      while (offer == null) {
        if (!await chunks.moveNext().timeout(const Duration(seconds: 10))) return;
        buffer.add(chunks.current);
        final all = buffer.takeBytes();
        final nl = all.indexOf(10);
        if (nl < 0) {
          if (all.length > _maxHeader) return;
          buffer.add(all);
          continue;
        }
        final m = jsonDecode(utf8.decode(all.sublist(0, nl)));
        if (m is! Map<String, dynamic> || m['t'] != 'offer' || m['v'] != _transferProtocol) return;
        offer = m;
        pending = Uint8List.sublistView(all, nl + 1);
      }
    } on Object {
      return;
    }

    // Archivos anunciados (nombres saneados y tamaños razonables).
    final files = <({String name, int size})>[];
    final used = <String>{};
    for (final f in (offer['files'] as List? ?? const [])) {
      if (f is! Map) return;
      final size = f['size'];
      if (size is! int || size < 0) return;
      var name = _safeName('${f['name']}');
      // Dos archivos con el mismo nombre: el segundo se renombra.
      for (var i = 2; !used.add(name.toLowerCase()); i++) {
        name = '${p.basenameWithoutExtension(name)} ($i)${p.extension(name)}';
      }
      files.add((name: name, size: size));
    }
    final total = files.fold<int>(0, (a, f) => a + f.size);
    if (files.isEmpty || files.length > _maxFiles || total > _maxTotal) {
      socket.write('${jsonEncode({'t': 'reject'})}\n');
      await socket.flush();
      return;
    }
    final peerName = '${offer['name'] ?? 'Alguien'}'.trim().isEmpty ? 'Alguien' : '${offer['name']}'.trim();
    final games = [
      for (final g in (offer['games'] as List? ?? const []))
        if (g is Map)
          OfferedGame(
            title: '${g['title'] ?? 'Juego'}',
            consoleId: '${g['console'] ?? ''}',
            size: g['size'] is int ? g['size'] as int : 0,
          ),
    ];

    // 2. Se pregunta al usuario.
    final decision = Completer<bool>();
    _decision = decision;
    state = TransferState(
      offer: IncomingOffer(peerName: peerName, games: games, total: total),
      progress: state.progress,
    );
    // Si el que envía cancela mientras tanto, la pregunta desaparece.
    final accepted = await Future.any([
      decision.future,
      Future.delayed(const Duration(minutes: 2), () => false),
    ]);
    if (_decision == decision) _decision = null;
    if (state.offer != null) state = TransferState(progress: state.progress);
    if (!accepted) {
      try {
        socket.write('${jsonEncode({'t': 'reject'})}\n');
        await socket.flush();
      } on Object {
        // Ya no estaba.
      }
      return;
    }

    var progress = TransferProgress(
        outgoing: false, peerName: peerName, phase: TransferPhase.receiving, total: total);
    void update(TransferProgress next) {
      progress = next;
      state = TransferState(offer: state.offer, progress: next);
    }

    update(progress);
    final dir = Directory(p.join(paths.downloads.path, 'recibidos_${DateTime.now().millisecondsSinceEpoch}'));
    try {
      await dir.create(recursive: true);
      socket.write('${jsonEncode({'t': 'accept'})}\n');
      await socket.flush();

      // 3. Archivos, uno detrás de otro.
      var received = 0;
      var lastUpdate = DateTime.now();
      final written = <String>[];
      for (final f in files) {
        final path = p.join(dir.path, f.name);
        final sink = File(path).openWrite();
        var left = f.size;
        var sinceFlush = 0;
        try {
          while (left > 0) {
            Uint8List data;
            if (pending.isNotEmpty) {
              data = pending;
              pending = Uint8List(0);
            } else {
              if (!await chunks.moveNext().timeout(const Duration(seconds: 30))) {
                throw const SocketException('conexión cerrada');
              }
              data = chunks.current;
            }
            if (data.length > left) {
              pending = Uint8List.sublistView(data, left);
              data = Uint8List.sublistView(data, 0, left);
            }
            sink.add(data);
            left -= data.length;
            received += data.length;
            sinceFlush += data.length;
            if (sinceFlush > 8 * 1024 * 1024) {
              sinceFlush = 0;
              await sink.flush(); // no acumular cientos de MB en memoria
            }
            final now = DateTime.now();
            if (now.difference(lastUpdate) > const Duration(milliseconds: 150)) {
              lastUpdate = now;
              update(progress.copyWith(done: received));
            }
          }
        } finally {
          await sink.close();
        }
        written.add(path);
      }

      // 4. Se importan como cualquier ROM (validación, duplicados, portadas...).
      update(progress.copyWith(done: total, phase: TransferPhase.importing));
      final report = await ref.read(romImporterProvider).importFiles(
            written,
            sourceId: 'lan',
            moveSources: true,
          );
      socket.write('${jsonEncode({
            't': 'done',
            'added': report.added.length,
            'rejected': [for (final (name, reason) in report.rejected) '$name: $reason'],
          })}\n');
      await socket.flush();
      // La carpeta temporal se borra antes de dar el envío por terminado.
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } on Object {
        // Se reintenta en el finally.
      }
      final added = report.added.length;
      update(progress.copyWith(
        phase: TransferPhase.finished,
        message: added == 0
            ? (report.rejected.isNotEmpty
                ? 'No se añadió nada: ${report.rejected.first.$2.toLowerCase()}.'
                : 'No se añadió nada.')
            : 'Recibido${added == 1 ? '' : 's'} $added juego${added == 1 ? '' : 's'} de $peerName. '
                'Ya está${added == 1 ? '' : 'n'} en Mis juegos.',
      ));
    } on Object {
      update(progress.copyWith(
          phase: TransferPhase.failed,
          message: _cancelled ? 'Recepción cancelada.' : 'Se cortó la conexión con $peerName.'));
    } finally {
      await chunks.cancel();
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } on Object {
        // Se limpiará en otra ocasión.
      }
    }
  }
}

final gameTransferProvider =
    NotifierProvider<GameTransferController, TransferState>(GameTransferController.new);

/// "1,5 GB", "320 MB"...
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes >= 100 * 1024 * 1024 ? 0 : 1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}
