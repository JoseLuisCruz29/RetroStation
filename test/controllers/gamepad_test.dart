import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/controllers/gamepad.dart';
import 'package:retrostation/emulation/native_bindings.dart';
import 'package:retrostation/settings/app_settings.dart';

Map<Object?, Object?> pro({int buttons = 0, int pov = -1, List<double> axes = const [0, 0, -1, 0, 0, -1]}) => {
      'id': 0,
      'connected': true,
      'name': 'Controla. Microsoft PC-joystick',
      'vid': 0x057e,
      'pid': 0x2009,
      'buttons': buttons,
      'pov': pov,
      'axes': axes,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pads = Gamepads.instance;
  tearDown(() => pads.debugReceive({'id': 0, 'connected': false}));

  test('Pro Controller: A, B, + y la cruceta; Home abre el menú', () {
    pads.debugReceive(pro(buttons: (1 << 1) | (1 << 9) | (1 << 12), pov: 9000));
    expect(pads.connected.single.displayName, 'Pro Controller de Switch');
    final r = pads.read(GamepadBindings.resolve(const {}, pads.connected.single), analogStick: false);
    expect(r.mask, (1 << RetroButton.a) | (1 << RetroButton.start) | (1 << RetroButton.right));
    expect(r.menu, isTrue);
  });

  test('joystick: cruceta en las consolas sin joystick y analógico en PSP', () {
    pads.debugReceive(pro(axes: const [-0.9, 0.0, -1, 0, 0, -1]));
    final bindings = GamepadBindings.resolve(const {}, pads.connected.single);
    expect(pads.read(bindings, analogStick: false).mask, 1 << RetroButton.left);
    final psp = pads.read(bindings, analogStick: true);
    expect(psp.mask, 0);
    expect(psp.stick.dx, closeTo(-0.9, 1e-9));
  });

  test('cambiar un botón y guardarlo en los ajustes', () {
    pads.debugReceive(pro(buttons: 1));
    final pad = pads.connected.single;
    // A en el botón B físico: B se queda con el botón A físico (se intercambian).
    final custom = GamepadBindings.assign(const {}, RetroButton.a, 'b0', pad);
    final back = AppSettings.fromMap(const AppSettings().copyWith(gamepad: custom).toMap());
    expect(back.gamepad, {RetroButton.a: 'b0', RetroButton.b: 'b1'});
    final map = GamepadBindings.resolve(back.gamepad, pad);
    expect(map['b0'], RetroButton.a);
    expect(map['b1'], RetroButton.b);
    expect(GamepadBindings.inputName('b0', pad), 'B');
    // Volver a dejarlo como de fábrica no guarda nada.
    expect(GamepadBindings.assign(back.gamepad, RetroButton.a, 'b1', pad), isEmpty);
  });

  test('desconectar lo quita de la lista', () {
    pads.debugReceive(pro());
    expect(pads.connected, hasLength(1));
    pads.debugReceive({'id': 0, 'connected': false});
    expect(pads.connected, isEmpty);
  });
}
