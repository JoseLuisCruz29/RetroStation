import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../engines/console.dart';
import '../storage/app_paths.dart';
import '../storage/database.dart';
import 'native_bindings.dart';
import 'ppsspp_assets.dart';

/// Una partida en curso. Envuelve el frontend nativo y la textura de vídeo.
/// Solo puede existir una sesión a la vez (el frontend es único).
class EmulatorSession {
  EmulatorSession._({
    required this.textureId,
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.targetFps,
  });

  static const _video = MethodChannel('retrostation/video');

  final int textureId;
  final int width;
  final int height;
  final double aspectRatio;
  final double targetFps;

  bool _disposed = false;
  int _buttons = 0;
  int _touchMask = 0;
  int _padMask = 0;

  static String sramPathFor(AppPaths paths, Game game) =>
      p.join(paths.saves.path, '${game.sha1 ?? 'game_${game.id}'}.srm');

  /// DeSmuME guarda la partida en `<ROM sin extensión>.dsv` dentro de la
  /// carpeta de guardados. Si aún no existe pero hay partida de melonDS (un
  /// volcado crudo de la memoria del cartucho, `.srm`), se copia como
  /// `<ROM>.sav`: DeSmuME importa ese archivo crudo la primera vez y lo
  /// convierte a `.dsv`. El `.srm` original no se toca.
  static Future<void> migrateSaveForDesmume({
    required String saveDir,
    required String romPath,
    required String sramPath,
  }) async {
    final base = p.join(saveDir, p.basenameWithoutExtension(romPath));
    final dsv = File('$base.dsv');
    final sav = File('$base.sav');
    final srm = File(sramPath);
    if (await dsv.exists() || await sav.exists() || !await srm.exists()) return;
    if (await srm.length() == 0) return;
    await srm.copy(sav.path);
  }

  /// Carga el núcleo y el ROM en un isolate aparte (lectura de archivos y
  /// arranque del núcleo) y después crea la textura y lanza el hilo nativo.
  static Future<EmulatorSession> start({
    required Game game,
    required ConsoleDescriptor console,
    required AppPaths paths,
    Map<String, String> coreOptions = const {},
    String? coreLibraryOverride,
    String? saveDirOverride,
    void Function()? beforeStart,
  }) async {
    final coreName = coreLibraryOverride ?? console.activeCore.library;
    final coreLibrary = coreName == null ? null : RetroNative.nativeLibraryPath(coreName);
    final romPath = game.romPath;
    if (coreLibrary == null) {
      throw StateError('${console.name} no tiene núcleo compilado');
    }
    if (romPath == null) {
      throw StateError('Este juego no tiene archivo ROM local');
    }
    final systemDir = paths.system.path;
    // Invitado de una partida compartida: el estado llega del anfitrión, así
    // que sus partidas guardadas van a una carpeta aparte y las suyas no se tocan.
    final saveDir = saveDirOverride ?? paths.saves.path;
    final sramPath = saveDirOverride != null
        ? p.join(saveDirOverride, 'invitado.srm')
        : sramPathFor(paths, game);
    if (saveDirOverride != null) await Directory(saveDirOverride).create(recursive: true);
    if (coreName!.startsWith('libppsspp')) {
      await PpssppAssets.ensureInstalled(systemDir);
    }
    if (coreName.startsWith('libdesmume')) {
      await migrateSaveForDesmume(saveDir: saveDir, romPath: romPath, sramPath: sramPath);
    }

    // Las opciones se guardan en el estado nativo del proceso, compartido
    // con el isolate que carga el juego.
    RetroNative.instance.setCoreOptions(coreOptions);
    final av = await Isolate.run(() {
      final native = RetroNative.instance;
      native.load(
        corePath: coreLibrary,
        romPath: romPath,
        systemDir: systemDir,
        saveDir: saveDir,
        sramPath: sramPath,
      );
      return native.avInfo();
    });

    try {
      final textureId = await _video.invokeMethod<int>(
        'create',
        {'width': av.width, 'height': av.height},
      );
      // El multijugador se inicia aquí, con el juego cargado pero antes del
      // primer fotograma: así los dos dispositivos empiezan en el mismo punto.
      beforeStart?.call();
      RetroNative.instance.start();
      return EmulatorSession._(
        textureId: textureId!,
        width: av.width,
        height: av.height,
        aspectRatio: av.aspect,
        targetFps: av.fps,
      );
    } catch (_) {
      RetroNative.instance.unload();
      rethrow;
    }
  }

  double get fps => RetroNative.instance.fps;
  int get frameCount => RetroNative.instance.frameCount;

  /// Teclado o mando físico (botón a botón).
  void setButton(int button, bool pressed) {
    final next = pressed ? _buttons | (1 << button) : _buttons & ~(1 << button);
    if (next == _buttons) return;
    _buttons = next;
    _send();
  }

  /// Controles táctiles (máscara completa). Se combina con el teclado.
  void setTouchMask(int mask) {
    if (mask == _touchMask) return;
    _touchMask = mask;
    _send();
  }

  /// Mandos del PC (máscara completa). Se combina con el teclado y lo táctil.
  void setPadMask(int mask) {
    if (mask == _padMask) return;
    _padMask = mask;
    _send();
  }

  /// Pantalla táctil (DS): posición normalizada 0..1 sobre la imagen.
  void setPointer(double nx, double ny, bool pressed) =>
      RetroNative.instance.setPointer(nx, ny, pressed);

  /// Joystick analógico izquierdo (PSP): -1..1, y hacia abajo.
  void setAnalog(Offset v) => RetroNative.instance.setAnalog(
        0,
        (v.dx.clamp(-1.0, 1.0) * 32767).round(),
        (v.dy.clamp(-1.0, 1.0) * 32767).round(),
      );

  void releaseAllButtons() {
    _buttons = 0;
    _touchMask = 0;
    _padMask = 0;
    _send();
  }

  void _send() {
    final all = _buttons | _touchMask | _padMask;
    RetroNative.instance.setButtons(all & 0xFFFF);
    // Botones C de la N64 -> joystick derecho (solo si cambian).
    final c = all >> 16;
    if (c != _cButtons) {
      _cButtons = c;
      bool on(int b) => all & (1 << b) != 0;
      final x = on(RetroButton.cRight) ? 32767 : (on(RetroButton.cLeft) ? -32767 : 0);
      final y = on(RetroButton.cDown) ? 32767 : (on(RetroButton.cUp) ? -32767 : 0);
      RetroNative.instance.setAnalog(1, x, y);
    }
  }

  int _cButtons = 0;

  /// Joystick derecho de un mando (botones C en N64): -1..1, y hacia abajo.
  void setRightAnalog(Offset v) => RetroNative.instance.setAnalog(
        1,
        (v.dx.clamp(-1.0, 1.0) * 32767).round(),
        (v.dy.clamp(-1.0, 1.0) * 32767).round(),
      );

  bool get supportsStates => RetroNative.instance.supportsStates;
  void saveState(String path) => RetroNative.instance.saveState(path);
  void loadState(String path) => RetroNative.instance.loadState(path);
  ({Uint8List pixels, int width, int height})? copyFrame() =>
      RetroNative.instance.copyFrame();

  /// Cambia opciones durante el juego (las que requieren reinicio se aplican
  /// la próxima vez que se abra).
  void setCoreOptions(Map<String, String> options) =>
      RetroNative.instance.setCoreOptions(options);

  void setVolume(double volume) => RetroNative.instance.setVolume(volume);
  void setSpeed(double speed) => RetroNative.instance.setSpeed(speed);
  void setRewindEnabled(bool enabled) =>
      RetroNative.instance.setRewindEnabled(enabled);
  void setRewinding(bool rewinding) => RetroNative.instance.setRewinding(rewinding);

  /// Pausar también guarda la SRAM (se llama al pasar a segundo plano).
  void pause() => RetroNative.instance.setPaused(true);
  void resume() => RetroNative.instance.setPaused(false);
  void reset() => RetroNative.instance.reset();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Detiene el hilo y guarda la SRAM antes de soltar la superficie.
    RetroNative.instance.unload();
    await _video.invokeMethod<void>('release');
  }
}
