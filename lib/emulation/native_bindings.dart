import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Espejo de `rs_av_info` (native/frontend/rs_frontend.h).
final class RsAvInfo extends Struct {
  @Int32()
  external int baseWidth;
  @Int32()
  external int baseHeight;
  @Float()
  external double aspectRatio;
  @Double()
  external double fps;
  @Double()
  external double sampleRate;
}

/// Espejo de `rs_netplay_info` (native/frontend/rs_frontend.h).
final class RsNetplayInfo extends Struct {
  @Int32()
  external int phase;
  @Int32()
  external int mode;
  @Int32()
  external int player;
  @Int32()
  external int rttMs;
  @Int32()
  external int remotePaused;
  @Int32()
  external int stalled;
  @Int32()
  external int resyncs;
  @Int32()
  external int frame;
}

/// Fase de la conexión multijugador (`rs::net::Phase`).
enum NetPhase { off, connecting, syncing, playing, disconnected, failed }

/// Tipo de partida multijugador (`rs::net::Mode`).
enum NetMode {
  /// Los dos teléfonos ejecutan el mismo juego (jugador 1 y jugador 2).
  shared,

  /// Cable link / adaptador inalámbrico de GBA: cada uno con su juego.
  link,

  /// Cable link de GBA para cualquier juego (núcleo GBA Link): cada
  /// dispositivo emula las dos GBA y solo viajan los botones. Empieza sin
  /// estado inicial: se inicia antes de arrancar el hilo de emulación.
  gbaLink,

  /// Multijugador inalámbrico de PSP ("ad hoc"): cada uno con su juego y su
  /// partida; la red la gestiona el propio PPSSPP (no el motor de netplay).
  pspAdhoc,
}

class NetStatus {
  const NetStatus({
    required this.phase,
    required this.player,
    required this.rttMs,
    required this.remotePaused,
    required this.stalled,
    required this.resyncs,
    required this.frame,
  });
  final NetPhase phase;
  final int player;
  final int rttMs;
  final bool remotePaused;
  final bool stalled;
  final int resyncs;
  final int frame;
}

/// Bits del mando (identificadores libretro). Coinciden con `RS_BTN_*`.
abstract final class RetroButton {
  static const b = 0;
  static const y = 1;
  static const select = 2;
  static const start = 3;
  static const up = 4;
  static const down = 5;
  static const left = 6;
  static const right = 7;
  static const a = 8;
  static const x = 9;
  static const l2 = 12;
  static const r2 = 13;

  /// Botones C de la N64 (bits propios de la app, no de libretro): la sesión
  /// los convierte en el joystick derecho, que es como los lee el núcleo.
  static const cUp = 16;
  static const cDown = 17;
  static const cLeft = 18;
  static const cRight = 19;
  static const l = 10;
  static const r = 11;
}

class NativeError implements Exception {
  NativeError(this.code, this.message);
  final int code;
  final String message;

  @override
  String toString() => message.isEmpty ? 'Error nativo $code' : message;
}

/// Bindings escritos a mano de la API C del frontend. Son pocas funciones y
/// así no hace falta LLVM para generarlos.
class RetroNative {
  RetroNative._(DynamicLibrary lib)
      : _load = lib.lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>,
                Pointer<Utf8>, Pointer<Utf8>),
            int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>,
                Pointer<Utf8>, Pointer<Utf8>)>('rs_load'),
        _getAvInfo = lib.lookupFunction<Int32 Function(Pointer<RsAvInfo>),
            int Function(Pointer<RsAvInfo>)>('rs_get_av_info'),
        _start = lib.lookupFunction<Int32 Function(), int Function()>('rs_start'),
        _setPaused = lib.lookupFunction<Void Function(Int32), void Function(int)>(
            'rs_set_paused'),
        _setButtons = lib.lookupFunction<Void Function(Uint32),
            void Function(int)>('rs_set_buttons'),
        _reset = lib.lookupFunction<Void Function(), void Function()>('rs_reset'),
        _setAnalog = lib.lookupFunction<Void Function(Int32, Int32, Int32),
            void Function(int, int, int)>('rs_set_analog'),
        _setPointer = lib.lookupFunction<Void Function(Int32, Int32, Int32),
            void Function(int, int, int)>('rs_set_pointer'),
        _saveSram =
            lib.lookupFunction<Int32 Function(), int Function()>('rs_save_sram'),
        _getFps =
            lib.lookupFunction<Double Function(), double Function()>('rs_get_fps'),
        _getFrameCount = lib.lookupFunction<Uint64 Function(), int Function()>(
            'rs_get_frame_count'),
        _unload = lib.lookupFunction<Void Function(), void Function()>('rs_unload'),
        _setCoreOption = lib.lookupFunction<Void Function(Pointer<Utf8>, Pointer<Utf8>),
            void Function(Pointer<Utf8>, Pointer<Utf8>)>('rs_set_core_option'),
        _clearCoreOptions =
            lib.lookupFunction<Void Function(), void Function()>('rs_clear_core_options'),
        _setVolume = lib.lookupFunction<Void Function(Float), void Function(double)>(
            'rs_set_volume'),
        _setSpeed = lib.lookupFunction<Void Function(Float), void Function(double)>(
            'rs_set_speed'),
        _supportsStates = lib.lookupFunction<Int32 Function(), int Function()>(
            'rs_supports_states'),
        _saveState = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
            int Function(Pointer<Utf8>)>('rs_save_state'),
        _loadState = lib.lookupFunction<Int32 Function(Pointer<Utf8>),
            int Function(Pointer<Utf8>)>('rs_load_state'),
        _copyFrame = lib.lookupFunction<
            Int32 Function(Pointer<Uint8>, Int32, Pointer<Int32>, Pointer<Int32>),
            int Function(Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>)>(
            'rs_copy_frame'),
        _setRewindEnabled = lib.lookupFunction<Void Function(Int32, Int32),
            void Function(int, int)>('rs_set_rewind_enabled'),
        _setRewinding = lib.lookupFunction<Void Function(Int32), void Function(int)>(
            'rs_set_rewinding'),
        _rewindAvailable = lib.lookupFunction<Int32 Function(), int Function()>(
            'rs_rewind_available'),
        _lastError = lib.lookupFunction<Pointer<Utf8> Function(),
            Pointer<Utf8> Function()>('rs_last_error'),
        _netplayStart = lib.lookupFunction<
            Int32 Function(Int32, Int32, Pointer<Utf8>, Int32, Int32, Pointer<Utf8>,
                Pointer<Utf8>),
            int Function(int, int, Pointer<Utf8>, int, int, Pointer<Utf8>,
                Pointer<Utf8>)>('rs_netplay_start'),
        _netplayStop =
            lib.lookupFunction<Void Function(), void Function()>('rs_netplay_stop'),
        _netplayStatus = lib.lookupFunction<Int32 Function(Pointer<RsNetplayInfo>),
            int Function(Pointer<RsNetplayInfo>)>('rs_netplay_status'),
        _netplayMessage = lib.lookupFunction<Pointer<Utf8> Function(),
            Pointer<Utf8> Function()>('rs_netplay_message');

  static RetroNative? _instance;

  /// El motor está compilado para Android, Windows e iPhone.
  static RetroNative get instance {
    if (Platform.isAndroid) {
      return _instance ??= RetroNative._(DynamicLibrary.open('libretrostation_native.so'));
    }
    if (Platform.isWindows) {
      return _instance ??= RetroNative._(DynamicLibrary.open(nativeLibraryPath('retrostation_native.dll')));
    }
    if (Platform.isIOS) {
      return _instance ??= RetroNative._(DynamicLibrary.open(nativeLibraryPath('retrostation_native')));
    }
    throw UnsupportedError('El motor de emulación no está compilado para este sistema');
  }

  /// Ruta de una biblioteca nativa. En Android el sistema las encuentra por
  /// su nombre (vienen en el APK); en Windows están junto al .exe, y los
  /// núcleos se llaman igual pero terminan en .dll (libmgba_libretro.dll).
  ///
  /// En iPhone cada biblioteca va como framework dentro de la app:
  /// Runner.app/Frameworks/libmgba_libretro.framework/libmgba_libretro.
  static String nativeLibraryPath(String name) {
    if (Platform.isIOS) {
      var base = name;
      for (final ext in const ['.so', '.dll', '.dylib']) {
        if (base.endsWith(ext)) base = base.substring(0, base.length - ext.length);
      }
      if (base == 'libretrostation_native') base = 'retrostation_native';
      final app = File(Platform.resolvedExecutable).parent.path;
      return '$app/Frameworks/$base.framework/$base';
    }
    if (!Platform.isWindows) return name;
    final dll = name.endsWith('.so') ? '${name.substring(0, name.length - 3)}.dll' : name;
    final dir = File(Platform.resolvedExecutable).parent.path;
    return '$dir${Platform.pathSeparator}$dll';
  }

  final int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>,
      Pointer<Utf8>) _load;
  final int Function(Pointer<RsAvInfo>) _getAvInfo;
  final int Function() _start;
  final void Function(int) _setPaused;
  final void Function(int) _setButtons;
  final void Function() _reset;
  final void Function(int, int, int) _setAnalog;
  final void Function(int, int, int) _setPointer;
  final int Function() _saveSram;

  /// Pantalla táctil: [nx], [ny] en 0..1 sobre la imagen completa.
  void setPointer(double nx, double ny, bool pressed) => _setPointer(
        ((nx.clamp(0, 1) * 2 - 1) * 0x7FFF).round(),
        ((ny.clamp(0, 1) * 2 - 1) * 0x7FFF).round(),
        pressed ? 1 : 0,
      );
  final double Function() _getFps;
  final int Function() _getFrameCount;
  final void Function() _unload;
  final void Function(Pointer<Utf8>, Pointer<Utf8>) _setCoreOption;
  final void Function() _clearCoreOptions;
  final void Function(double) _setVolume;
  final void Function(double) _setSpeed;

  /// Fija las opciones del núcleo (sustituye a las anteriores).
  void setCoreOptions(Map<String, String> options) {
    _clearCoreOptions();
    using((arena) {
      options.forEach((k, v) => _setCoreOption(
          k.toNativeUtf8(allocator: arena), v.toNativeUtf8(allocator: arena)));
    });
  }
  final int Function() _supportsStates;
  final int Function(Pointer<Utf8>) _saveState;
  final int Function(Pointer<Utf8>) _loadState;
  final int Function(Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>) _copyFrame;
  final void Function(int, int) _setRewindEnabled;
  final void Function(int) _setRewinding;
  final int Function() _rewindAvailable;
  final Pointer<Utf8> Function() _lastError;
  final int Function(int, int, Pointer<Utf8>, int, int, Pointer<Utf8>, Pointer<Utf8>)
      _netplayStart;
  final void Function() _netplayStop;
  final int Function(Pointer<RsNetplayInfo>) _netplayStatus;
  final Pointer<Utf8> Function() _netplayMessage;

  /// Inicia el multijugador con el juego ya en marcha. El anfitrión escucha en
  /// [port]; el invitado se conecta a [address].
  void netplayStart({
    required bool host,
    required NetMode mode,
    required String address,
    required int port,
    required int delay,
    required String token,
    required String gameKey,
  }) =>
      using((arena) => _check(_netplayStart(
            host ? 1 : 0,
            mode.index,
            address.toNativeUtf8(allocator: arena),
            port,
            delay,
            token.toNativeUtf8(allocator: arena),
            gameKey.toNativeUtf8(allocator: arena),
          )));

  void netplayStop() => _netplayStop();

  NetStatus netplayStatus() => using((arena) {
        final info = arena<RsNetplayInfo>();
        _netplayStatus(info);
        final r = info.ref;
        return NetStatus(
          phase: NetPhase.values[r.phase.clamp(0, NetPhase.values.length - 1)],
          player: r.player,
          rttMs: r.rttMs,
          remotePaused: r.remotePaused != 0,
          stalled: r.stalled != 0,
          resyncs: r.resyncs,
          frame: r.frame,
        );
      });

  String get netplayMessage => _netplayMessage().toDartString();

  void setVolume(double volume) => _setVolume(volume);
  void setSpeed(double speed) => _setSpeed(speed);
  bool get supportsStates => _supportsStates() == 1;

  void saveState(String path) =>
      using((arena) => _check(_saveState(path.toNativeUtf8(allocator: arena))));

  void loadState(String path) =>
      using((arena) => _check(_loadState(path.toNativeUtf8(allocator: arena))));

  /// Último fotograma en RGBA8888 (para miniaturas). Null si aún no hay imagen.
  ({Uint8List pixels, int width, int height})? copyFrame() => using((arena) {
        final w = arena<Int32>();
        final h = arena<Int32>();
        final needed = _copyFrame(nullptr, 0, w, h);
        if (needed <= 0) return null;
        final buffer = arena<Uint8>(needed);
        if (_copyFrame(buffer, needed, w, h) != 0) return null;
        return (
          pixels: Uint8List.fromList(buffer.asTypedList(needed)),
          width: w.value,
          height: h.value,
        );
      });

  void setRewindEnabled(bool enabled, {int seconds = 20}) =>
      _setRewindEnabled(enabled ? 1 : 0, seconds);
  void setRewinding(bool rewinding) => _setRewinding(rewinding ? 1 : 0);
  int get rewindAvailable => _rewindAvailable();

  void load({
    required String corePath,
    required String romPath,
    required String systemDir,
    required String saveDir,
    required String sramPath,
  }) {
    using((arena) {
      final code = _load(
        corePath.toNativeUtf8(allocator: arena),
        romPath.toNativeUtf8(allocator: arena),
        systemDir.toNativeUtf8(allocator: arena),
        saveDir.toNativeUtf8(allocator: arena),
        sramPath.toNativeUtf8(allocator: arena),
      );
      _check(code);
    });
  }

  ({int width, int height, double aspect, double fps, double sampleRate})
      avInfo() => using((arena) {
            final info = arena<RsAvInfo>();
            _check(_getAvInfo(info));
            final r = info.ref;
            return (
              width: r.baseWidth,
              height: r.baseHeight,
              aspect: r.aspectRatio,
              fps: r.fps,
              sampleRate: r.sampleRate,
            );
          });

  void start() => _check(_start());
  void setPaused(bool paused) => _setPaused(paused ? 1 : 0);
  void setButtons(int mask) => _setButtons(mask);
  void reset() => _reset();
  void setAnalog(int stick, int x, int y) => _setAnalog(stick, x, y);
  void saveSram() => _check(_saveSram());
  double get fps => _getFps();
  int get frameCount => _getFrameCount();
  void unload() => _unload();

  void _check(int code) {
    if (code != 0) throw NativeError(code, _lastError().toDartString());
  }
}
