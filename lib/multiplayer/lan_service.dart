import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../emulation/native_bindings.dart';
import '../game_library/game_repository.dart';
import '../settings/app_settings.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';
import 'multiplayer_games.dart';

/// Puertos del multijugador LAN.
abstract final class LanPorts {
  /// Anuncios UDP ("estoy aquí") que ven los demás teléfonos de la red.
  static const discovery = 55436;

  /// Peticiones de conexión y mensajes de la sala (TCP, una línea JSON por mensaje).
  static const lobby = 55437;

  /// Partida en sí: lo usa el motor nativo (TCP + UDP).
  static const game = 55435;
}

const _protocol = 1;

enum PeerStatus {
  available('Buscando partida'),
  inRoom('En una sala'),
  playing('Jugando');

  const PeerStatus(this.label);
  final String label;
}

/// Otro teléfono con RetroStation abierto en la misma red.
class LanPeer {
  const LanPeer({
    required this.id,
    required this.name,
    required this.address,
    required this.status,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final InternetAddress address;
  final PeerStatus status;
  final DateTime lastSeen;
}

/// Alguien pide unirse a este teléfono (que será el anfitrión).
class JoinRequest {
  const JoinRequest({required this.peerId, required this.peerName, required this.address});
  final String peerId;
  final String peerName;
  final InternetAddress address;
}

enum RoomRole { host, guest }

/// Datos para abrir la partida, iguales en los dos teléfonos.
class RoomLaunch {
  const RoomLaunch({
    required this.experience,
    required this.token,
    required this.hostAddress,
    required this.coreOptions,
    required this.serial,
    this.peerSave,
  });

  /// Cable link de GBA: partida guardada del otro jugador (puede estar vacía).
  final Uint8List? peerSave;

  final Experience experience;
  final String token;

  /// Dirección del anfitrión (vacía en el propio anfitrión).
  final String hostAddress;

  /// Opciones del núcleo del anfitrión: el invitado usa las mismas para que
  /// los dos juegos se comporten igual.
  final Map<String, String> coreOptions;

  /// Número de partida dentro de la sala (cambia en cada inicio).
  final int serial;
}

class RoomState {
  const RoomState({
    required this.role,
    required this.peerId,
    required this.peerName,
    required this.peerAddress,
    required this.peerLibrary,
    this.myReady = false,
    this.peerReady = false,
    this.selection,
    this.launch,
    this.waitingSave = false,
  });

  /// El anfitrión pidió la partida guardada del invitado y la está esperando.
  final bool waitingSave;

  final RoomRole role;
  final String peerId;
  final String peerName;
  final InternetAddress peerAddress;
  final List<LanGame> peerLibrary;
  final bool myReady;
  final bool peerReady;
  final Experience? selection;
  final RoomLaunch? launch;

  bool get isHost => role == RoomRole.host;

  RoomState copyWith({
    bool? myReady,
    bool? peerReady,
    Experience? selection,
    bool clearSelection = false,
    RoomLaunch? launch,
    bool clearLaunch = false,
    bool? waitingSave,
  }) =>
      RoomState(
        role: role,
        peerId: peerId,
        peerName: peerName,
        peerAddress: peerAddress,
        peerLibrary: peerLibrary,
        myReady: myReady ?? this.myReady,
        peerReady: peerReady ?? this.peerReady,
        selection: clearSelection ? null : selection ?? this.selection,
        launch: clearLaunch ? null : launch ?? this.launch,
        waitingSave: waitingSave ?? this.waitingSave,
      );
}

class LanState {
  const LanState({
    this.running = false,
    this.addresses = const [],
    this.peers = const [],
    this.request,
    this.connectingTo,
    this.room,
    this.notice,
    this.library = const [],
  });

  final bool running;

  /// IPv4 de este teléfono en la red local (para conectarse a mano).
  final List<String> addresses;
  final List<LanPeer> peers;
  final JoinRequest? request;

  /// Id del jugador al que se ha pedido unirse (esperando respuesta).
  final String? connectingTo;
  final RoomState? room;

  /// Aviso puntual para mostrar al usuario (se borra con [LanController.clearNotice]).
  final String? notice;
  final List<LanGame> library;

  LanState copyWith({
    bool? running,
    List<String>? addresses,
    List<LanPeer>? peers,
    JoinRequest? request,
    bool clearRequest = false,
    String? connectingTo,
    bool clearConnecting = false,
    RoomState? room,
    bool clearRoom = false,
    String? notice,
    bool clearNotice = false,
    List<LanGame>? library,
  }) =>
      LanState(
        running: running ?? this.running,
        addresses: addresses ?? this.addresses,
        peers: peers ?? this.peers,
        request: clearRequest ? null : request ?? this.request,
        connectingTo: clearConnecting ? null : connectingTo ?? this.connectingTo,
        room: clearRoom ? null : room ?? this.room,
        notice: clearNotice ? null : notice ?? this.notice,
        library: library ?? this.library,
      );
}

/// Conexión TCP con mensajes JSON de una línea.
class _Link {
  _Link(this.socket, {required this.onMessage, required this.onClosed}) {
    _sub = utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _closed, onError: (_) => _closed(), cancelOnError: true);
  }

  final Socket socket;
  void Function(Map<String, dynamic> message) onMessage;
  void Function() onClosed;
  late final StreamSubscription<String> _sub;
  bool _done = false;

  void _onLine(String line) {
    try {
      final m = jsonDecode(line);
      if (m is Map<String, dynamic>) onMessage(m);
    } on FormatException {
      // Línea no válida: se ignora.
    }
  }

  void _closed() {
    if (_done) return;
    _done = true;
    onClosed();
  }

  void send(Map<String, Object?> message) {
    if (_done) return;
    try {
      socket.write('${jsonEncode(message)}\n');
    } on Object {
      _closed();
    }
  }

  void close() {
    _done = true;
    unawaited(_sub.cancel());
    socket.destroy();
  }
}

/// Multijugador LAN: anuncia este teléfono, encuentra a los demás, gestiona
/// las peticiones de conexión y la sala privada de dos jugadores.
class LanController extends Notifier<LanState> {
  static const _channel = MethodChannel('retrostation/lan');

  RawDatagramSocket? _udp;
  ServerSocket? _server;
  Timer? _beacon;
  _Link? _pending; // petición entrante o saliente sin responder
  _Link? _roomLink;
  final _peers = <String, LanPeer>{};
  bool _playing = false;
  int _launchSerial = 0;

  @override
  LanState build() {
    ref.onDispose(_shutdown);
    return const LanState();
  }

  AppSettings get _settings => ref.read(settingsProvider);

  /// Nombre e id del perfil (el id se crea la primera vez).
  Future<({String id, String name})> _profile() async {
    var s = _settings;
    if (s.playerId.isEmpty) {
      final r = Random.secure();
      final id = List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
      s = s.copyWith(playerId: id);
      await ref.read(settingsProvider.notifier).update(s);
    }
    final name = s.playerName.trim().isEmpty ? 'Jugador' : s.playerName.trim();
    return (id: s.playerId, name: name);
  }

  /// Empieza a anunciarse y a buscar jugadores. Se puede llamar varias veces.
  Future<void> start() async {
    await _profile();
    final library = await loadLanLibrary(ref.read(gameRepositoryProvider));
    state = state.copyWith(library: library);
    if (state.running) return;
    try {
      await _channel.invokeMethod<void>('discovery', {'enabled': true});
    } on Object {
      // Sin canal (pruebas) o sin Wi-Fi: el resto sigue funcionando.
    }
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, LanPorts.discovery, reuseAddress: true)
        ..broadcastEnabled = true;
      _udp!.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = _udp?.receive()) != null) {
          _onBeacon(d!);
        }
      });
    } on SocketException {
      state = state.copyWith(notice: 'No se pudo buscar jugadores en la red (puerto ocupado).');
    }
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, LanPorts.lobby, shared: true);
      _server!.listen(_onIncoming);
    } on SocketException {
      state = state.copyWith(notice: 'No se pueden recibir peticiones (puerto ocupado).');
    }
    _beacon = Timer.periodic(const Duration(milliseconds: 1500), (_) => _tick());
    state = state.copyWith(running: true, addresses: await localAddresses());
    _tick();
  }

  /// Deja de buscar jugadores (al salir de la sección). La sala, si existe, sigue.
  Future<void> stopDiscovery() async {
    if (state.room != null) return;
    _shutdown();
    state = state.copyWith(running: false, peers: const [], clearRequest: true, clearConnecting: true);
  }

  void _shutdown() {
    _beacon?.cancel();
    _beacon = null;
    _udp?.close();
    _udp = null;
    unawaited(_server?.close());
    _server = null;
    _pending?.close();
    _pending = null;
    _roomLink?.close();
    _roomLink = null;
    _peers.clear();
    unawaited(_channel.invokeMethod<void>('discovery', {'enabled': false}).catchError((_) {}));
  }

  void clearNotice() => state = state.copyWith(clearNotice: true);

  PeerStatus get _myStatus => _playing
      ? PeerStatus.playing
      : state.room != null
          ? PeerStatus.inRoom
          : PeerStatus.available;

  List<int> _beaconBytes() {
    final s = _settings;
    return utf8.encode(jsonEncode({
      'rs': _protocol,
      'id': s.playerId,
      'name': s.playerName.trim().isEmpty ? 'Jugador' : s.playerName.trim(),
      'st': _myStatus.name,
    }));
  }

  void _tick() {
    final udp = _udp;
    if (udp != null) {
      final msg = _beaconBytes();
      // Difusión en cada red, y además directo a los jugadores ya conocidos:
      // en un PC con varias tarjetas (VPN, Ethernet...) la difusión puede salir
      // por otra red y no llegar al teléfono.
      final targets = {
        '255.255.255.255',
        ...state.addresses.map(_broadcastOf),
        for (final p in _peers.values) p.address.address,
      };
      for (final target in targets) {
        try {
          udp.send(msg, InternetAddress(target), LanPorts.discovery);
        } on Object {
          // Red sin difusión: se prueba con la siguiente dirección.
        }
      }
    }
    // Quien no se anuncia en 6 s ya no está.
    final now = DateTime.now();
    final before = _peers.length;
    _peers.removeWhere((_, p) => now.difference(p.lastSeen) > const Duration(seconds: 6));
    if (_peers.length != before) _publishPeers();
  }

  static String _broadcastOf(String ip) {
    final parts = ip.split('.');
    return parts.length == 4 ? '${parts[0]}.${parts[1]}.${parts[2]}.255' : '255.255.255.255';
  }

  void _onBeacon(Datagram d) {
    try {
      final m = jsonDecode(utf8.decode(d.data));
      if (m is! Map<String, dynamic> || m['rs'] != _protocol) return;
      final id = m['id'] as String?;
      if (id == null || id == _settings.playerId) return;
      // Un jugador nuevo: se le responde directamente para que también nos vea.
      if (!_peers.containsKey(id)) {
        try {
          _udp?.send(_beaconBytes(), d.address, LanPorts.discovery);
        } on Object {
          // Sin respuesta directa: llegará con el siguiente anuncio.
        }
      }
      _peers[id] = LanPeer(
        id: id,
        name: (m['name'] as String?)?.trim().isNotEmpty == true ? m['name'] as String : 'Jugador',
        address: d.address,
        status: PeerStatus.values.where((s) => s.name == m['st']).firstOrNull ?? PeerStatus.available,
        lastSeen: DateTime.now(),
      );
      _publishPeers();
    } on Object {
      // Paquete de otra aplicación: se ignora.
    }
  }

  void _publishPeers() {
    final list = _peers.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = state.copyWith(peers: list);
  }

  // --- Peticiones de conexión -------------------------------------------------

  /// Pide unirse a [peer]. Si acepta, este teléfono entra en su sala como invitado.
  Future<void> requestJoin(LanPeer peer) => requestJoinAddress(peer.address, peerId: peer.id);

  Future<void> requestJoinAddress(InternetAddress address, {String? peerId}) async {
    if (state.room != null || state.connectingTo != null) return;
    state = state.copyWith(connectingTo: peerId ?? address.address);
    final me = await _profile();
    Socket socket;
    try {
      socket = await Socket.connect(address, LanPorts.lobby, timeout: const Duration(seconds: 4));
    } on Object {
      state = state.copyWith(
          clearConnecting: true, notice: 'No se pudo conectar con ${address.address}. ¿Estáis en la misma Wi-Fi?');
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    late final _Link link;
    link = _Link(
      socket,
      onMessage: (m) {
        switch (m['t']) {
          case 'accept':
            _pending = null;
            _enterRoom(
              link,
              RoomState(
                role: RoomRole.guest,
                peerId: m['id'] as String? ?? '',
                peerName: m['name'] as String? ?? 'Anfitrión',
                peerAddress: address,
                peerLibrary: LanGame.listFromJson(m['library']),
              ),
            );
          case 'reject':
            _pending = null;
            link.close();
            state = state.copyWith(clearConnecting: true, notice: '${m['name'] ?? 'El jugador'} rechazó la conexión.');
          case 'busy':
            _pending = null;
            link.close();
            state = state.copyWith(clearConnecting: true, notice: 'Ese jugador está ocupado en otra sala.');
        }
      },
      onClosed: () {
        if (_pending == link) {
          _pending = null;
          state = state.copyWith(clearConnecting: true, notice: 'El otro jugador no respondió.');
        }
      },
    );
    _pending = link;
    link.send({
      't': 'join',
      'v': _protocol,
      'id': me.id,
      'name': me.name,
      'library': LanGame.listToJson(state.library),
    });
  }

  void cancelRequest() {
    _pending?.close();
    _pending = null;
    state = state.copyWith(clearConnecting: true);
  }

  void _onIncoming(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    late final _Link link;
    List<LanGame> theirLibrary = const [];
    link = _Link(
      socket,
      onMessage: (m) {
        if (m['t'] != 'join') return;
        if (m['v'] != _protocol) {
          link.send({'t': 'reject', 'name': _settings.playerName});
          link.close();
          return;
        }
        if (state.room != null || state.request != null || _pending != null) {
          link.send({'t': 'busy'});
          link.close();
          return;
        }
        theirLibrary = LanGame.listFromJson(m['library']);
        _pending = link;
        _pendingLibrary = theirLibrary;
        state = state.copyWith(
          request: JoinRequest(
            peerId: m['id'] as String? ?? '',
            peerName: (m['name'] as String?)?.trim().isNotEmpty == true ? m['name'] as String : 'Jugador',
            address: socket.remoteAddress,
          ),
        );
      },
      onClosed: () {
        if (_pending == link) {
          _pending = null;
          state = state.copyWith(clearRequest: true, notice: 'El jugador canceló la petición.');
        }
      },
    );
  }

  List<LanGame> _pendingLibrary = const [];

  /// Acepta la petición pendiente: este teléfono es el anfitrión de la sala.
  Future<void> acceptRequest() async {
    final req = state.request;
    final link = _pending;
    if (req == null || link == null) return;
    final me = await _profile();
    _pending = null;
    link.send({
      't': 'accept',
      'id': me.id,
      'name': me.name,
      'library': LanGame.listToJson(state.library),
    });
    state = state.copyWith(clearRequest: true);
    _enterRoom(
      link,
      RoomState(
        role: RoomRole.host,
        peerId: req.peerId,
        peerName: req.peerName,
        peerAddress: req.address,
        peerLibrary: _pendingLibrary,
      ),
    );
  }

  void rejectRequest() {
    _pending?.send({'t': 'reject', 'name': _settings.playerName});
    _pending?.close();
    _pending = null;
    state = state.copyWith(clearRequest: true);
  }

  // --- Sala ----------------------------------------------------------------------

  void _enterRoom(_Link link, RoomState room) {
    _roomLink = link;
    link.onMessage = _onRoomMessage;
    link.onClosed = () {
      if (_roomLink != link) return;
      _roomLink = null;
      final name = state.room?.peerName ?? 'El otro jugador';
      state = state.copyWith(clearRoom: true, notice: 'Se perdió la conexión con $name.');
    };
    state = state.copyWith(room: room, clearConnecting: true);
    _tick();
  }

  void _onRoomMessage(Map<String, dynamic> m) {
    final room = state.room;
    if (room == null) return;
    switch (m['t']) {
      case 'ready':
        state = state.copyWith(room: room.copyWith(peerReady: m['v'] == true));
      case 'select' when !room.isHost:
        state = state.copyWith(room: room.copyWith(selection: Experience.fromJson(m['exp'])));
      case 'start' when !room.isHost:
        final exp = Experience.fromJson(m['exp']);
        if (exp == null) return;
        state = state.copyWith(
          room: room.copyWith(
            selection: exp,
            launch: RoomLaunch(
              experience: exp,
              token: m['token'] as String? ?? '',
              hostAddress: room.peerAddress.address,
              coreOptions: {
                for (final e in ((m['options'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
              },
              serial: ++_launchSerial,
              peerSave: _decodeSave(m['save']),
            ),
          ),
        );
      // Cable link de GBA: el anfitrión pide la partida guardada antes de empezar.
      case 'savereq' when !room.isHost:
        final sha1 = m['sha1'] as String? ?? '';
        unawaited(_localSave(sha1).then((bytes) =>
            _roomLink?.send({'t': 'save', 'sha1': sha1, 'data': base64Encode(bytes)})));
      case 'save' when room.isHost:
        final pending = _pendingLinkStart;
        if (pending == null || m['sha1'] != pending.sha1) return;
        _pendingLinkStart = null;
        unawaited(_launchGbaLink(pending, _decodeSave(m['data']) ?? Uint8List(0)));
      case 'leave':
        _roomLink?.close();
        _roomLink = null;
        state = state.copyWith(clearRoom: true, notice: '${room.peerName} salió de la sala.');
    }
  }

  void setReady(bool ready) {
    final room = state.room;
    if (room == null) return;
    _roomLink?.send({'t': 'ready', 'v': ready});
    state = state.copyWith(room: room.copyWith(myReady: ready));
  }

  /// El anfitrión elige qué jugar.
  void select(Experience exp) {
    final room = state.room;
    if (room == null || !room.isHost) return;
    _roomLink?.send({'t': 'select', 'exp': exp.toJson()});
    state = state.copyWith(room: room.copyWith(selection: exp));
  }

  /// El anfitrión inicia la partida: los dos teléfonos abren el juego.
  void startGame({required Map<String, String> coreOptions}) {
    final room = state.room;
    final exp = room?.selection;
    if (room == null || exp == null || !room.isHost || !room.peerReady) return;
    if (exp.mode == NetMode.gbaLink) {
      // Primero la partida guardada del invitado; al llegar se empieza.
      _pendingLinkStart = exp;
      _roomLink?.send({'t': 'savereq', 'sha1': exp.sha1});
      state = state.copyWith(room: room.copyWith(waitingSave: true));
      return;
    }
    final r = Random.secure();
    final token = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
    _roomLink?.send({'t': 'start', 'exp': exp.toJson(), 'token': token, 'options': coreOptions});
    state = state.copyWith(
      room: room.copyWith(
        launch: RoomLaunch(
          experience: exp,
          token: token,
          hostAddress: '',
          coreOptions: coreOptions,
          serial: ++_launchSerial,
        ),
      ),
    );
  }

  Experience? _pendingLinkStart;

  static Uint8List? _decodeSave(Object? data) {
    if (data is! String) return null;
    try {
      return base64Decode(data);
    } on FormatException {
      return null;
    }
  }

  /// Partida guardada de este dispositivo para un juego (la misma que usa al
  /// jugar solo: `saves/<sha1>.srm`). Vacía si aún no hay.
  Future<Uint8List> _localSave(String sha1) async {
    final file = File(p.join(ref.read(appPathsProvider).saves.path, '$sha1.srm'));
    try {
      if (await file.exists()) return await file.readAsBytes();
    } on FileSystemException {
      // Sin acceso: se empieza sin partida.
    }
    return Uint8List(0);
  }

  Future<void> _launchGbaLink(Experience exp, Uint8List guestSave) async {
    final room = state.room;
    if (room == null) return;
    final r = Random.secure();
    final token = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
    final hostSave = await _localSave(exp.sha1);
    _roomLink?.send({
      't': 'start',
      'exp': exp.toJson(),
      'token': token,
      'options': const <String, String>{},
      'save': base64Encode(hostSave),
    });
    state = state.copyWith(
      room: room.copyWith(
        waitingSave: false,
        launch: RoomLaunch(
          experience: exp,
          token: token,
          hostAddress: '',
          coreOptions: const {},
          serial: ++_launchSerial,
          peerSave: guestSave,
        ),
      ),
    );
  }

  /// La partida se abrió (o terminó): limpia el inicio pendiente y el "Listo".
  void consumeLaunch() {
    final room = state.room;
    if (room == null) return;
    state = state.copyWith(room: room.copyWith(clearLaunch: true, myReady: false, peerReady: false));
  }

  void setPlaying(bool playing) {
    _playing = playing;
    _tick();
  }

  void leaveRoom() {
    _roomLink?.send({'t': 'leave'});
    _roomLink?.close();
    _roomLink = null;
    state = state.copyWith(clearRoom: true);
  }

  /// Direcciones IPv4 privadas de este teléfono (Wi-Fi o zona Wi-Fi).
  static Future<List<String>> localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLoopback && _isPrivate(a.address)) a.address,
      ];
    } on Object {
      return const [];
    }
  }

  static bool _isPrivate(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.contains(null)) return false;
    return p[0] == 10 || (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31) || (p[0] == 192 && p[1] == 168);
  }
}

final lanProvider = NotifierProvider<LanController, LanState>(LanController.new);

/// Datos que la pantalla de juego necesita para una partida multijugador.
class NetplayArgs {
  const NetplayArgs({
    required this.host,
    required this.mode,
    required this.hostAddress,
    required this.token,
    required this.peerName,
    required this.coreOptions,
  });

  final bool host;

  final NetMode mode;
  final String hostAddress;
  final String token;
  final String peerName;

  /// Del anfitrión (las usa el invitado en juego compartido).
  final Map<String, String> coreOptions;
}

/// Útil para pruebas: Game -> LanGame sin leer el disco.
LanGame lanGameOf(Game g, {bool pokemon = false}) =>
    LanGame(id: g.id, sha1: g.sha1 ?? '', title: g.title, consoleId: g.consoleId, pokemonLink: pokemon);
