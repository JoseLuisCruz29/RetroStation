import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:retrostation/controllers/touch_layout.dart';
import 'package:retrostation/emulation/native_bindings.dart';
import 'package:retrostation/presentation/player/touch_controls.dart';
import 'package:retrostation/settings/app_settings.dart';

/// Todos los diseños de botones se dibujan sin errores en todas las consolas
/// (con un botón pulsado y el joystick movido). Con RS_PREVIEW=<ruta.png>
/// guarda una imagen con todos para revisarlos a ojo.
void main() {
  const consoles = ['gba', 'nes', 'snes', 'psx', 'psp', 'genesis', 'n64', 'nds'];
  const cell = Size(360, 300);

  test('cada diseño se dibuja en todas las consolas', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final full = Size(cell.width * consoles.length, cell.height * ControlSkin.values.length);
    canvas.drawRect(Offset.zero & full, Paint()..color = const Color(0xFF203040));
    for (final (row, skin) in ControlSkin.values.indexed) {
      for (final (col, console) in consoles.indexed) {
        canvas.save();
        canvas.translate(col * cell.width, row * cell.height);
        final regions = TouchLayout.forConsole(console, cell, landscape: false);
        ControlsPainter(
          regions: regions,
          mask: (1 << RetroButton.a) | (1 << RetroButton.up) | (1 << RetroButton.start),
          opacity: 0.55,
          accent: const Color(0xFF8FDCEF),
          analog: const Offset(0.6, -0.4),
          skin: skin,
          consoleId: console,
        ).paint(canvas, cell);
        canvas.restore();
      }
    }
    final out = Platform.environment['RS_PREVIEW'];
    if (out == null) return;
    final image = await recorder.endRecording().toImage(full.width.toInt(), full.height.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File(out).writeAsBytesSync(png!.buffer.asUint8List());
  });

  test('el diseño se guarda y se lee de los ajustes', () {
    const s = AppSettings(controlSkin: ControlSkin.neon);
    expect(AppSettings.fromMap(s.toMap()).controlSkin, ControlSkin.neon);
    expect(AppSettings.fromMap(const {}).controlSkin, ControlSkin.clasico);
  });
}
