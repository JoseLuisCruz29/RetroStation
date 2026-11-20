import 'dart:convert';

import 'package:flutter/services.dart';

import '../emulation/native_bindings.dart';

/// Un botón de la consola que se puede asignar a una tecla.
class BindableButton {
  const BindableButton(this.id, this.label, [this.hint]);

  /// Botón de [RetroButton].
  final int id;
  final String label;

  /// Equivalencia en PlayStation y PSP (botones con otro nombre).
  final String? hint;
}

/// Teclas del teclado para jugar en el PC (configurables en Ajustes).
abstract final class KeyboardBindings {
  static const buttons = [
    BindableButton(RetroButton.up, 'Arriba'),
    BindableButton(RetroButton.down, 'Abajo'),
    BindableButton(RetroButton.left, 'Izquierda'),
    BindableButton(RetroButton.right, 'Derecha'),
    BindableButton(RetroButton.a, 'A', 'PlayStation / PSP: Círculo'),
    BindableButton(RetroButton.b, 'B', 'PlayStation / PSP: Equis'),
    BindableButton(RetroButton.x, 'X', 'PlayStation / PSP: Triángulo'),
    BindableButton(RetroButton.y, 'Y', 'PlayStation / PSP: Cuadrado'),
    BindableButton(RetroButton.l, 'L'),
    BindableButton(RetroButton.r, 'R'),
    BindableButton(RetroButton.start, 'Start'),
    BindableButton(RetroButton.select, 'Select'),
  ];

  /// Teclas de fábrica: botón -> tecla.
  static final defaults = <int, LogicalKeyboardKey>{
    RetroButton.up: LogicalKeyboardKey.arrowUp,
    RetroButton.down: LogicalKeyboardKey.arrowDown,
    RetroButton.left: LogicalKeyboardKey.arrowLeft,
    RetroButton.right: LogicalKeyboardKey.arrowRight,
    RetroButton.a: LogicalKeyboardKey.keyX,
    RetroButton.b: LogicalKeyboardKey.keyZ,
    RetroButton.x: LogicalKeyboardKey.keyC,
    RetroButton.y: LogicalKeyboardKey.keyV,
    RetroButton.l: LogicalKeyboardKey.keyA,
    RetroButton.r: LogicalKeyboardKey.keyS,
    RetroButton.start: LogicalKeyboardKey.enter,
    RetroButton.select: LogicalKeyboardKey.backspace,
  };

  /// Mandos físicos: siempre activos, no se configuran aquí.
  static final gamepad = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.gameButtonA: RetroButton.a,
    LogicalKeyboardKey.gameButtonB: RetroButton.b,
    LogicalKeyboardKey.gameButtonX: RetroButton.x,
    LogicalKeyboardKey.gameButtonY: RetroButton.y,
    LogicalKeyboardKey.gameButtonLeft1: RetroButton.l,
    LogicalKeyboardKey.gameButtonRight1: RetroButton.r,
    LogicalKeyboardKey.gameButtonStart: RetroButton.start,
    LogicalKeyboardKey.gameButtonSelect: RetroButton.select,
  };

  /// Teclas que no se pueden asignar (Esc sale del juego / cancela).
  static bool reserved(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.escape || gamepad.containsKey(key);

  /// Asignación efectiva: lo personalizado ([custom], botón -> id de tecla)
  /// sobre las teclas de fábrica.
  static Map<int, LogicalKeyboardKey> resolve(Map<int, int> custom) => {
        for (final b in buttons)
          b.id: custom[b.id] != null
              ? LogicalKeyboardKey(custom[b.id]!)
              : defaults[b.id]!,
      };

  /// Tecla -> botón, para el reproductor (incluye los mandos).
  static Map<LogicalKeyboardKey, int> keyMap(Map<int, int> custom) => {
        for (final e in resolve(custom).entries) e.value: e.key,
        ...gamepad,
      };

  /// Asigna [key] a [button]. Si otra acción usaba esa tecla, se le da la que
  /// tenía [button] (intercambio), para que ninguna quede repetida.
  static Map<int, int> assign(Map<int, int> custom, int button, LogicalKeyboardKey key) {
    final current = resolve(custom);
    final previous = current[button]!;
    final next = {for (final e in current.entries) e.key: e.value.keyId};
    for (final e in current.entries) {
      if (e.key != button && e.value == key) next[e.key] = previous.keyId;
    }
    next[button] = key.keyId;
    // Solo se guarda lo que difiere de fábrica.
    next.removeWhere((b, id) => defaults[b]!.keyId == id);
    return next;
  }

  /// Nombre de la tecla para mostrarla ("X", "Flecha arriba", "Intro"...).
  static String keyName(LogicalKeyboardKey key) {
    final names = {
      LogicalKeyboardKey.arrowUp: 'Flecha arriba',
      LogicalKeyboardKey.arrowDown: 'Flecha abajo',
      LogicalKeyboardKey.arrowLeft: 'Flecha izquierda',
      LogicalKeyboardKey.arrowRight: 'Flecha derecha',
      LogicalKeyboardKey.enter: 'Intro',
      LogicalKeyboardKey.numpadEnter: 'Intro (numérico)',
      LogicalKeyboardKey.backspace: 'Retroceso',
      LogicalKeyboardKey.space: 'Espacio',
      LogicalKeyboardKey.tab: 'Tabulador',
      LogicalKeyboardKey.shiftLeft: 'Mayús izq.',
      LogicalKeyboardKey.shiftRight: 'Mayús der.',
      LogicalKeyboardKey.controlLeft: 'Ctrl izq.',
      LogicalKeyboardKey.controlRight: 'Ctrl der.',
      LogicalKeyboardKey.altLeft: 'Alt izq.',
      LogicalKeyboardKey.altRight: 'Alt der.',
    };
    final known = names[key];
    if (known != null) return known;
    final label = key.keyLabel.trim();
    if (label.isNotEmpty) return label.length == 1 ? label.toUpperCase() : label;
    return key.debugName ?? 'Tecla ${key.keyId}';
  }

  /// Texto corto para la ayuda del reproductor.
  static String guide(Map<int, int> custom) {
    final k = resolve(custom);
    String n(int b) => keyName(k[b]!);
    final dpadDefault = [RetroButton.up, RetroButton.down, RetroButton.left, RetroButton.right]
        .every((b) => k[b] == defaults[b]);
    final dpad = dpadDefault
        ? 'Flechas: cruceta'
        : 'Cruceta: ${n(RetroButton.up)}/${n(RetroButton.down)}/${n(RetroButton.left)}/${n(RetroButton.right)}';
    return '$dpad · ${n(RetroButton.a)}: A · ${n(RetroButton.b)}: B · ${n(RetroButton.x)}: X · '
        '${n(RetroButton.y)}: Y · ${n(RetroButton.l)}/${n(RetroButton.r)}: L/R · '
        '${n(RetroButton.start)}: Start · ${n(RetroButton.select)}: Select · '
        'cámbialas en Ajustes > Teclado';
  }

  static Map<int, int> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (int.tryParse(e.key) != null && e.value is int) int.parse(e.key): e.value as int,
      };
    } on Object {
      return const {};
    }
  }

  static String encode(Map<int, int> custom) =>
      jsonEncode({for (final e in custom.entries) '${e.key}': e.value});
}
