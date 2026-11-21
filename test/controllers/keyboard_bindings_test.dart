import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/controllers/keyboard_bindings.dart';
import 'package:retrostation/emulation/native_bindings.dart';
import 'package:retrostation/settings/app_settings.dart';

void main() {
  test('de fábrica: X es A, Z es B, Intro es Start; los mandos también', () {
    final map = KeyboardBindings.keyMap(const {});
    expect(map[LogicalKeyboardKey.keyX], RetroButton.a);
    expect(map[LogicalKeyboardKey.keyZ], RetroButton.b);
    expect(map[LogicalKeyboardKey.enter], RetroButton.start);
    expect(map[LogicalKeyboardKey.gameButtonA], RetroButton.a);
  });

  test('cambiar una tecla; si ya estaba usada, se intercambian', () {
    // A pasa a la G.
    var custom = KeyboardBindings.assign(const {}, RetroButton.a, LogicalKeyboardKey.keyG);
    var map = KeyboardBindings.keyMap(custom);
    expect(map[LogicalKeyboardKey.keyG], RetroButton.a);
    expect(map.containsKey(LogicalKeyboardKey.keyX), isFalse);

    // B pasa a la G (que tenía A): A se queda con la Z de B.
    custom = KeyboardBindings.assign(custom, RetroButton.b, LogicalKeyboardKey.keyG);
    map = KeyboardBindings.keyMap(custom);
    expect(map[LogicalKeyboardKey.keyG], RetroButton.b);
    expect(map[LogicalKeyboardKey.keyZ], RetroButton.a);
    final keys = KeyboardBindings.resolve(custom).values.toList();
    expect(keys.toSet().length, keys.length, reason: 'ninguna tecla repetida');

    // Volver a la tecla de fábrica no guarda nada.
    expect(KeyboardBindings.assign(const {}, RetroButton.a, LogicalKeyboardKey.keyX), isEmpty);
  });

  test('se guarda en los ajustes y se recupera', () {
    final custom = KeyboardBindings.assign(const {}, RetroButton.start, LogicalKeyboardKey.space);
    final back = AppSettings.fromMap(const AppSettings().copyWith(keyboard: custom).toMap());
    expect(back.keyboard, custom);
    expect(KeyboardBindings.guide(back.keyboard), contains('Espacio: Start'));
    expect(AppSettings.fromMap(const {'controls.keyboard': 'basura'}).keyboard, isEmpty);
  });

  test('Esc y los botones de mando no se pueden asignar', () {
    expect(KeyboardBindings.reserved(LogicalKeyboardKey.escape), isTrue);
    expect(KeyboardBindings.reserved(LogicalKeyboardKey.gameButtonA), isTrue);
    expect(KeyboardBindings.reserved(LogicalKeyboardKey.keyQ), isFalse);
  });
}
