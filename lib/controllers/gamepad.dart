import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../emulation/native_bindings.dart';

/// Estado de un mando conectado al PC (lo envía `windows/runner/gamepad_input.cpp`).
class PadState {
  const PadState({
    required this.id,
    required this.name,
    required this.vid,
    required this.pid,
    required this.buttons,
    required this.pov,
    required this.axes,
  });

  final int id;
  final String name;
  final int vid;
  final int pid;

  /// Botón i pulsado = bit i.
  final int buttons;

  /// Cruceta (POV) en centésimas de grado (0 = arriba, 9000 = derecha), -1 = suelta.
  final int pov;

  /// Ejes en -1..1: x, y (joystick izquierdo), z, r, u, v.
  final List<double> axes;

  bool get isNintendo => vid == 0x057e;

  /// Nombre para mostrar (Windows llama "PC-joystick" a muchos mandos).
  String get displayName => switch ((vid, pid)) {
        (0x057e, 0x2009) => 'Pro Controller de Switch',
        (0x057e, 0x2006) => 'Joy-Con (izquierdo)',
        (0x057e, 0x2007) => 'Joy-Con (derecho)',
        (0x045e, _) => 'Mando de Xbox',
        (0x054c, _) => 'Mando de PlayStation',
        _ => name.isEmpty ? 'Mando' : name,
      };

  Offset get leftStick => Offset(axes.isNotEmpty ? axes[0] : 0, axes.length > 1 ? axes[1] : 0);

  /// Entradas pulsadas: "b0".."b31" (botones) y "up"/"down"/"left"/"right" (cruceta).
  Set<String> get pressed => {
        for (var i = 0; i < 32; i++)
          if (buttons & (1 << i) != 0) 'b$i',
        ...povDirections(pov),
      };

  static Set<String> povDirections(int pov) {
    if (pov < 0) return const {};
    final a = pov / 100.0;
    return {
      if (a >= 292.5 || a <= 67.5) 'up',
      if (a >= 22.5 && a <= 157.5) 'right',
      if (a >= 112.5 && a <= 247.5) 'down',
      if (a >= 202.5 && a <= 337.5) 'left',
    };
  }

  static PadState? fromMap(Map<Object?, Object?> m) {
    if (m['connected'] != true) return null;
    return PadState(
      id: m['id'] as int? ?? 0,
      name: m['name'] as String? ?? '',
      vid: m['vid'] as int? ?? 0,
      pid: m['pid'] as int? ?? 0,
      buttons: m['buttons'] as int? ?? 0,
      pov: m['pov'] as int? ?? -1,
      axes: [for (final a in (m['axes'] as List? ?? const [])) (a as num).toDouble()],
    );
  }
}

/// Mandos conectados al PC. En Android los mandos llegan como teclas.
class Gamepads extends ChangeNotifier {
  Gamepads._() {
    if (Platform.isWindows) _channel.setMethodCallHandler(_onCall);
  }

  static final instance = Gamepads._();
  static const _channel = MethodChannel('retrostation/gamepad');

  /// Mientras se juega (y sin el menú del juego abierto) el mando es del
  /// juego; si no, sirve para moverse por la app.
  bool gameCapture = false;

  final _pads = <int, PadState>{};
  final _changes = StreamController<PadState>.broadcast();

  List<PadState> get connected => _pads.values.toList();

  /// Cada cambio de cualquier mando (botones, cruceta o joystick).
  Stream<PadState> get changes => _changes.stream;

  /// Para pruebas: simula el mensaje del lado nativo.
  @visibleForTesting
  void debugReceive(Map<Object?, Object?> message) => _receive(message);

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'state' && call.arguments is Map) _receive(call.arguments as Map<Object?, Object?>);
  }

  void _receive(Map<Object?, Object?> m) {
    final id = m['id'] as int? ?? 0;
    final pad = PadState.fromMap(m);
    final known = _pads.containsKey(id);
    if (pad == null) {
      if (_pads.remove(id) != null) notifyListeners();
      _changes.add(PadState(id: id, name: '', vid: 0, pid: 0, buttons: 0, pov: -1, axes: const []));
      return;
    }
    _pads[id] = pad;
    if (!known) notifyListeners();
    _changes.add(pad);
  }

  /// Botones de consola pulsados en todos los mandos (para el juego).
  ({int mask, bool menu, Offset stick}) read(Map<String, int> bindings, {required bool analogStick}) {
    var mask = 0;
    var menu = false;
    var stick = Offset.zero;
    for (final pad in _pads.values) {
      for (final input in pad.pressed) {
        final action = bindings[input];
        if (action == null) continue;
        if (action == GamepadBindings.menu) {
          menu = true;
        } else {
          mask |= 1 << action;
        }
      }
      final s = pad.leftStick;
      if (analogStick) {
        if (s.distance > 0.15) stick = s;
      } else {
        // Sin joystick en la consola: el joystick también mueve la cruceta.
        if (s.dy < -0.5) mask |= 1 << RetroButton.up;
        if (s.dy > 0.5) mask |= 1 << RetroButton.down;
        if (s.dx < -0.5) mask |= 1 << RetroButton.left;
        if (s.dx > 0.5) mask |= 1 << RetroButton.right;
      }
    }
    return (mask: mask, menu: menu, stick: stick);
  }
}

/// Qué botón del mando hace cada cosa (Ajustes > Mando).
abstract final class GamepadBindings {
  /// Acción especial: abrir el menú del juego (pausa, estados, salir).
  static const menu = -1;

  static const actions = <(int, String)>[
    (RetroButton.a, 'A'),
    (RetroButton.b, 'B'),
    (RetroButton.x, 'X'),
    (RetroButton.y, 'Y'),
    (RetroButton.l, 'L'),
    (RetroButton.r, 'R'),
    (RetroButton.start, 'Start'),
    (RetroButton.select, 'Select'),
    (menu, 'Menú del juego'),
  ];

  /// La cruceta del mando siempre es la cruceta.
  static const _dpad = {
    'up': RetroButton.up,
    'down': RetroButton.down,
    'left': RetroButton.left,
    'right': RetroButton.right,
  };

  /// Pro Controller de Switch por Bluetooth (orden de Windows):
  /// B, A, Y, X, L, R, ZL, ZR, −, +, L3, R3, Home, Captura.
  static const nintendo = <int, List<String>>{
    RetroButton.b: ['b0'],
    RetroButton.a: ['b1'],
    RetroButton.y: ['b2'],
    RetroButton.x: ['b3'],
    RetroButton.l: ['b4', 'b6'], // L y ZL
    RetroButton.r: ['b5', 'b7'], // R y ZR
    RetroButton.select: ['b8'],
    RetroButton.start: ['b9'],
    menu: ['b12'], // Home
  };

  /// Mandos tipo Xbox (y la mayoría de genéricos): botones por posición.
  static const generic = <int, List<String>>{
    RetroButton.b: ['b0'], // abajo
    RetroButton.a: ['b1'], // derecha
    RetroButton.y: ['b2'], // izquierda
    RetroButton.x: ['b3'], // arriba
    RetroButton.l: ['b4'],
    RetroButton.r: ['b5'],
    RetroButton.select: ['b6'],
    RetroButton.start: ['b7'],
    menu: ['b8'],
  };

  static Map<int, List<String>> defaultsFor(PadState? pad) => pad?.isNintendo ?? true ? nintendo : generic;

  /// Entrada -> acción. [custom] (acción -> entrada) sustituye a lo de fábrica.
  static Map<String, int> resolve(Map<int, String> custom, PadState? pad) {
    final result = <String, int>{..._dpad};
    for (final (action, _) in actions) {
      for (final input in inputsFor(action, custom, pad)) {
        result[input] = action;
      }
    }
    return result;
  }

  /// Entradas que usa cada acción: la personalizada, o las de fábrica que no
  /// se hayan dado a otra acción.
  static List<String> inputsFor(int action, Map<int, String> custom, PadState? pad) {
    if (custom[action] case final input?) return [input];
    final taken = custom.values.toSet();
    return [
      for (final input in defaultsFor(pad)[action] ?? const <String>[])
        if (!taken.contains(input)) input,
    ];
  }

  /// Asigna [input] a [action]. Si otra acción lo usaba, se queda con el botón
  /// que tenía [action] (se intercambian), para que ninguna se quede sin botón.
  static Map<int, String> assign(Map<int, String> custom, int action, String input, PadState? pad) {
    final previous = inputsFor(action, custom, pad).firstOrNull;
    final next = Map<int, String>.of(custom);
    for (final (other, _) in actions) {
      if (other == action || !inputsFor(other, custom, pad).contains(input)) continue;
      if (previous != null && previous != input) {
        next[other] = previous;
      } else {
        next.remove(other);
      }
    }
    next[action] = input;
    // Lo que coincide con fábrica no hace falta guardarlo.
    next.removeWhere((a, i) {
      final d = defaultsFor(pad)[a] ?? const <String>[];
      return d.length == 1 && d.first == i;
    });
    return next;
  }

  /// Nombre de una entrada del mando.
  static String inputName(String input, PadState? pad) {
    const dirs = {'up': 'Cruceta ↑', 'down': 'Cruceta ↓', 'left': 'Cruceta ←', 'right': 'Cruceta →'};
    if (dirs[input] case final d?) return d;
    final n = int.tryParse(input.substring(1)) ?? 0;
    if (pad?.isNintendo ?? false) {
      const names = ['B', 'A', 'Y', 'X', 'L', 'R', 'ZL', 'ZR', '−', '+', 'L3', 'R3', 'Home', 'Captura'];
      if (n < names.length) return names[n];
    }
    if (pad != null && !pad.isNintendo) {
      const names = ['A', 'B', 'X', 'Y', 'LB', 'RB', 'Back', 'Start', 'L3', 'R3'];
      if (n < names.length) return names[n];
    }
    return 'Botón ${n + 1}';
  }

  static Map<int, String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (int.tryParse(e.key) != null && e.value is String) int.parse(e.key): e.value as String,
      };
    } on Object {
      return const {};
    }
  }

  static String encode(Map<int, String> custom) =>
      jsonEncode({for (final e in custom.entries) '${e.key}': e.value});
}
