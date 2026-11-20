import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:retrostation/controllers/gamepad.dart';
import 'package:retrostation/controllers/gamepad_navigator.dart';
import 'package:retrostation/settings/app_settings.dart';

Map<Object?, Object?> pro({int buttons = 0, int pov = -1}) => {
      'id': 0,
      'connected': true,
      'name': 'Pro Controller',
      'vid': 0x057e,
      'pid': 0x2009,
      'buttons': buttons,
      'pov': pov,
      'axes': const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    };

void main() {
  testWidgets('cruceta para moverse, A para elegir, B para volver; no actúa durante el juego', (tester) async {
    final pads = Gamepads.instance;
    addTearDown(() {
      pads.debugReceive({'id': 0, 'connected': false});
      pads.gameCapture = false;
    });
    final tapped = <String>[];
    var back = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => GamepadNavigator(
        settings: const AppSettings(),
        onBack: () => back++,
        child: child!,
      ),
      home: Scaffold(
        body: Column(children: [
          for (final name in ['Mis juegos', 'Descubrir', 'Ajustes'])
            TextButton(onPressed: () => tapped.add(name), child: Text(name)),
        ]),
      ),
    ));

    Future<void> press({int buttons = 0, int pov = -1}) async {
      pads.debugReceive(pro(buttons: buttons, pov: pov));
      await tester.pump();
      pads.debugReceive(pro());
      await tester.pump();
    }

    await press(pov: 18000); // abajo: elige el primero
    await press(pov: 18000); // abajo: el segundo
    await press(buttons: 1 << 1); // A
    expect(tapped, ['Descubrir']);

    await press(buttons: 1 << 0); // B: no hay nada que cerrar
    expect(back, 1);

    pads.gameCapture = true; // jugando: el mando es del juego
    await press(buttons: 1 << 1);
    expect(tapped, ['Descubrir']);
  });
}
