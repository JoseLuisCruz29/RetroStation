import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/gamepad.dart';
import '../controllers/keyboard_bindings.dart';
import '../controllers/touch_layout.dart';
import '../storage/database.dart';
import '../storage/storage_providers.dart';

enum BackgroundStyle {
  charcoal('Gris carbón'),
  amoled('Negro AMOLED');

  const BackgroundStyle(this.label);
  final String label;
}

enum AccentColor {
  cian('Cian'),
  ambar('Ámbar'),
  verde('Verde');

  const AccentColor(this.label);
  final String label;
}

enum PlayerOrientation {
  auto('Automática'),
  portrait('Vertical'),
  landscape('Horizontal');

  const PlayerOrientation(this.label);
  final String label;
}

/// Filtros de imagen que se aplican al escalar el fotograma.
enum VideoFilter {
  sharp('Nítido'),
  smooth('Suavizado'),
  scanlines('Líneas CRT'),
  lcd('Rejilla LCD');

  const VideoFilter(this.label);
  final String label;
}

/// Diseño de los controles táctiles (todas las consolas). [clasico] es el de
/// siempre; los demás solo cambian el dibujo, no la posición ni el tamaño.
enum ControlSkin {
  clasico('Clásico', 'Translúcido, el de siempre'),
  consola('Consola', 'Botones de colores con relieve'),
  minimalista('Minimalista', 'Solo contornos finos'),
  neon('Neón', 'Contornos brillantes del color de acento'),
  pixel('Pixel', 'Bloques cuadrados de 8 bits'),
  cristal('Cristal', 'Vidrio esmerilado con brillo');

  const ControlSkin(this.label, this.description);
  final String label;
  final String description;
}

/// Calidad gráfica en el PC: resolución interna de PSP y PlayStation.
enum GraphicsQuality {
  original('Original'),
  alta('Alta (2×)'),
  maxima('Máxima (3×)');

  const GraphicsQuality(this.label);
  final String label;
}

/// Ajustes globales. Solo contiene opciones que ya tienen efecto real.
class AppSettings {
  const AppSettings({
    this.background = BackgroundStyle.charcoal,
    this.accent = AccentColor.cian,
    this.reduceMotion = false,
    this.crtEffect = true,
    this.uiSounds = true,
    this.tutorialDone = false,
    this.volume = 0.8,
    this.controlsOpacity = 0.55,
    this.controlsScale = 1.0,
    this.haptics = true,
    this.orientation = PlayerOrientation.auto,
    this.showFps = true,
    this.fastForwardSpeed = 3,
    this.rewindEnabled = true,
    this.videoFilter = VideoFilter.sharp,
    this.disabledSources = const {},
    this.layoutPortrait = const {},
    this.layoutLandscape = const {},
    this.playerName = '',
    this.playerId = '',
    this.seenVersion = '',
    this.keyboard = const {},
    this.gamepad = const {},
    this.pcQuality = GraphicsQuality.alta,
    this.controlSkin = ControlSkin.clasico,
  });

  /// Diseño de los botones táctiles en el teléfono.
  final ControlSkin controlSkin;

  /// Solo en Windows: los juegos 3D (PSP y PlayStation) a más resolución.
  final GraphicsQuality pcQuality;

  /// Botones del mando personalizados en el PC (acción -> entrada del mando,
  /// ver [GamepadBindings]); lo que no está aquí usa los de fábrica.
  final Map<int, String> gamepad;

  /// Teclas personalizadas para jugar en el PC (botón -> id de tecla); lo que
  /// no está aquí usa las de fábrica ([KeyboardBindings.defaults]).
  final Map<int, int> keyboard;

  /// Última versión cuyas novedades vio el usuario (aviso "Novedades").
  final String seenVersion;

  /// Perfil del multijugador LAN: nombre visible para los demás (se elige una
  /// vez) e identificador fijo de este teléfono.
  final String playerName;
  final String playerId;

  /// Personalización de los controles táctiles por orientación.
  final Map<String, ControlOverride> layoutPortrait;
  final Map<String, ControlOverride> layoutLandscape;

  Map<String, ControlOverride> layoutFor({required bool landscape}) =>
      landscape ? layoutLandscape : layoutPortrait;

  static Map<String, ControlOverride> _decodeLayout(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (e.value is Map<String, dynamic>) e.key: ControlOverride.fromJson(e.value as Map<String, dynamic>),
      };
    } on FormatException {
      return const {};
    }
  }

  static String _encodeLayout(Map<String, ControlOverride> l) =>
      jsonEncode({for (final e in l.entries) e.key: e.value.toJson()});

  final BackgroundStyle background;
  final AccentColor accent;
  final bool reduceMotion;

  /// Líneas de barrido CRT sobre la interfaz (no sobre el juego).
  final bool crtEffect;

  /// Efectos de sonido al tocar y navegar por los menús.
  final bool uiSounds;

  /// El tutorial de bienvenida ya se completó o se saltó.
  final bool tutorialDone;
  final double volume;
  final double controlsOpacity;
  final double controlsScale;
  final bool haptics;
  final PlayerOrientation orientation;
  final bool showFps;
  final int fastForwardSpeed;
  final bool rewindEnabled;
  final VideoFilter videoFilter;

  /// Ids de fuentes de Descubrir desactivadas por el usuario.
  final Set<String> disabledSources;

  static const fastForwardOptions = [2, 3, 4];

  factory AppSettings.fromMap(Map<String, String> map) {
    T pick<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == map[key]).firstOrNull ?? fallback;
    double num(String key, double fallback, double min, double max) =>
        (double.tryParse(map[key] ?? '') ?? fallback).clamp(min, max);
    bool flag(String key, bool fallback) =>
        map[key] == null ? fallback : map[key] == 'true';
    const d = AppSettings();
    final ff = int.tryParse(map['play.ffSpeed'] ?? '') ?? d.fastForwardSpeed;
    return AppSettings(
      background: pick(BackgroundStyle.values, 'ui.background', d.background),
      accent: pick(AccentColor.values, 'ui.accent', d.accent),
      reduceMotion: flag('ui.reduceMotion', d.reduceMotion),
      crtEffect: flag('ui.crtEffect', d.crtEffect),
      uiSounds: flag('ui.sounds', d.uiSounds),
      tutorialDone: flag('ui.tutorialDone', d.tutorialDone),
      volume: num('audio.volume', d.volume, 0, 1),
      controlsOpacity: num('controls.opacity', d.controlsOpacity, 0.15, 1),
      controlsScale: num('controls.scale', d.controlsScale, 0.7, 1.4),
      haptics: flag('controls.haptics', d.haptics),
      orientation: pick(PlayerOrientation.values, 'play.orientation', d.orientation),
      showFps: flag('play.showFps', d.showFps),
      fastForwardSpeed:
          fastForwardOptions.contains(ff) ? ff : d.fastForwardSpeed,
      rewindEnabled: flag('play.rewind', d.rewindEnabled),
      videoFilter: pick(VideoFilter.values, 'video.filter', d.videoFilter),
      disabledSources: {
        for (final s in (map['discovery.disabled'] ?? '').split(','))
          if (s.trim().isNotEmpty) s.trim(),
      },
      layoutPortrait: _decodeLayout(map['controls.layout.portrait']),
      layoutLandscape: _decodeLayout(map['controls.layout.landscape']),
      playerName: map['lan.name'] ?? '',
      playerId: map['lan.id'] ?? '',
      seenVersion: map['ui.seenVersion'] ?? '',
      keyboard: KeyboardBindings.decode(map['controls.keyboard']),
      gamepad: GamepadBindings.decode(map['controls.gamepad']),
      pcQuality: pick(GraphicsQuality.values, 'video.pcQuality', d.pcQuality),
      controlSkin: pick(ControlSkin.values, 'controls.skin', d.controlSkin),
    );
  }

  Map<String, String> toMap() => {
        'ui.background': background.name,
        'ui.accent': accent.name,
        'ui.reduceMotion': '$reduceMotion',
        'ui.crtEffect': '$crtEffect',
        'ui.sounds': '$uiSounds',
        'ui.tutorialDone': '$tutorialDone',
        'audio.volume': volume.toStringAsFixed(2),
        'controls.opacity': controlsOpacity.toStringAsFixed(2),
        'controls.scale': controlsScale.toStringAsFixed(2),
        'controls.haptics': '$haptics',
        'play.orientation': orientation.name,
        'play.showFps': '$showFps',
        'play.ffSpeed': '$fastForwardSpeed',
        'play.rewind': '$rewindEnabled',
        'video.filter': videoFilter.name,
        'discovery.disabled': (disabledSources.toList()..sort()).join(','),
        'controls.layout.portrait': _encodeLayout(layoutPortrait),
        'controls.layout.landscape': _encodeLayout(layoutLandscape),
        'lan.name': playerName,
        'lan.id': playerId,
        'ui.seenVersion': seenVersion,
        'controls.keyboard': KeyboardBindings.encode(keyboard),
        'controls.gamepad': GamepadBindings.encode(gamepad),
        'video.pcQuality': pcQuality.name,
        'controls.skin': controlSkin.name,
      };

  AppSettings copyWith({
    BackgroundStyle? background,
    AccentColor? accent,
    bool? reduceMotion,
    bool? crtEffect,
    bool? uiSounds,
    bool? tutorialDone,
    double? volume,
    double? controlsOpacity,
    double? controlsScale,
    bool? haptics,
    PlayerOrientation? orientation,
    bool? showFps,
    int? fastForwardSpeed,
    bool? rewindEnabled,
    VideoFilter? videoFilter,
    Set<String>? disabledSources,
    Map<String, ControlOverride>? layoutPortrait,
    Map<String, ControlOverride>? layoutLandscape,
    String? playerName,
    String? playerId,
    String? seenVersion,
    Map<int, int>? keyboard,
    Map<int, String>? gamepad,
    GraphicsQuality? pcQuality,
    ControlSkin? controlSkin,
  }) =>
      AppSettings(
        controlSkin: controlSkin ?? this.controlSkin,
        pcQuality: pcQuality ?? this.pcQuality,
        gamepad: gamepad ?? this.gamepad,
        keyboard: keyboard ?? this.keyboard,
        seenVersion: seenVersion ?? this.seenVersion,
        playerName: playerName ?? this.playerName,
        playerId: playerId ?? this.playerId,
        disabledSources: disabledSources ?? this.disabledSources,
        layoutPortrait: layoutPortrait ?? this.layoutPortrait,
        layoutLandscape: layoutLandscape ?? this.layoutLandscape,
        background: background ?? this.background,
        accent: accent ?? this.accent,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        crtEffect: crtEffect ?? this.crtEffect,
        uiSounds: uiSounds ?? this.uiSounds,
        tutorialDone: tutorialDone ?? this.tutorialDone,
        volume: volume ?? this.volume,
        controlsOpacity: controlsOpacity ?? this.controlsOpacity,
        controlsScale: controlsScale ?? this.controlsScale,
        haptics: haptics ?? this.haptics,
        orientation: orientation ?? this.orientation,
        showFps: showFps ?? this.showFps,
        fastForwardSpeed: fastForwardSpeed ?? this.fastForwardSpeed,
        rewindEnabled: rewindEnabled ?? this.rewindEnabled,
        videoFilter: videoFilter ?? this.videoFilter,
      );
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<AppSettings> load() async {
    final rows = await _db.select(_db.settingEntries).get();
    return AppSettings.fromMap({for (final r in rows) r.key: r.value});
  }

  Future<void> save(AppSettings settings) => _db.batch((b) {
        b.insertAllOnConflictUpdate(_db.settingEntries, [
          for (final e in settings.toMap().entries)
            SettingEntriesCompanion.insert(key: e.key, value: e.value),
        ]);
      });
}

/// Ajustes leídos antes del primer frame (se sobrescribe en `main()`).
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettings next) async {
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
