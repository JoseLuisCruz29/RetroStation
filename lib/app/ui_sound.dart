import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Efectos de sonido de la interfaz (estilo RetroStation OS).
enum Sfx {
  /// Confirmar: tocar una tarjeta o un panel.
  click,

  /// Abrir una pantalla o ventana, o cambiar de pestaña.
  open,

  /// Volver o cerrar.
  back,

  /// Movimiento corto del cursor (volver a tocar la pestaña activa).
  move,

  /// Encendido, al abrir la app.
  on,
}

/// Reproduce los efectos con el SoundPool de Android (MainActivity), que los
/// tiene precargados y suenan sin retardo. En otras plataformas o en pruebas
/// no hace nada.
abstract final class UiSound {
  static const _channel = MethodChannel('retrostation/sfx');

  /// Ajustes > Sonidos de la interfaz.
  static bool enabled = true;

  /// Volumen general de la app (0..1); los efectos van algo más bajos.
  static double volume = 0.8;

  static void play(Sfx sfx) {
    if (!enabled || volume <= 0) return;
    _channel
        .invokeMethod<void>('play', {'name': sfx.name, 'volume': (volume * 0.7).clamp(0.0, 1.0)})
        .catchError((Object _) {}); // sin implementación nativa (pruebas): silencio
  }
}

/// Suena al abrir y cerrar pantallas y ventanas del navegador principal.
class UiSoundObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) UiSound.play(Sfx.open);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    UiSound.play(Sfx.back);
  }
}
