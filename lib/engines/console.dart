import 'dart:ffi' show Abi;
import 'dart:io' show File, Platform;

import 'package:material_ui/material_ui.dart';

import '../emulation/native_bindings.dart';

/// Estado de integración de un núcleo de emulación.
enum CoreStatus {
  /// Núcleo compilado, integrado y probado.
  available('Disponible'),

  /// Núcleo en integración (todavía no ejecuta juegos).
  inDevelopment('En integración'),

  /// Planificado para una etapa posterior.
  planned('Planificada'),

  /// No se puede integrar con la arquitectura actual (ver [ConsoleDescriptor.note]).
  unavailable('No disponible');

  const CoreStatus(this.label);
  final String label;
}

/// Un núcleo libretro concreto: nombre visible, licencia y biblioteca nativa.
class CoreBuild {
  const CoreBuild({required this.name, required this.license, this.library});

  final String name;
  final String license;

  /// Biblioteca nativa (null si aún no está compilado).
  final String? library;
}

/// Si la app corre como proceso ARM de 32 bits (p. ej. Galaxy A13: procesador
/// de 64 bits con Android de solo 32 bits). Se puede sustituir en pruebas.
bool Function() isArm32Process = () => Abi.current() == Abi.androidArm;

/// Si la app corre en Windows (versión de escritorio). Se puede sustituir en pruebas.
bool Function() isWindowsDesktop = () => Platform.isWindows;

/// Si la app corre en un iPhone o iPad. Se puede sustituir en pruebas.
bool Function() isIOSDevice = () => Platform.isIOS;

/// En iPhone, si el núcleo está dentro de la app (cada emulador se compila
/// por separado y alguno puede faltar). Se puede sustituir en pruebas.
bool Function(String? coreLibrary) iosHasCore = (lib) =>
    lib != null && File(RetroNative.nativeLibraryPath(lib)).existsSync();

/// Motivo común de las consolas que aún no están en iPhone.
const iosPendingNote = 'Todavía no está en la versión de iPhone: llega en una próxima '
    'actualización.';

/// Descriptor de una consola. Añadir una consola nueva significa añadir un
/// descriptor aquí y su núcleo libretro en `native/`; la interfaz se adapta sola.
class ConsoleDescriptor {
  const ConsoleDescriptor({
    required this.id,
    required this.name,
    required this.shortName,
    required this.manufacturer,
    required this.releaseYear,
    required this.extensions,
    required this.coreName,
    required this.coreLicense,
    this.coreLibrary,
    this.libretroSystem,
    this._note,
    required this._status,
    this.windowsNote,
    this.iosNote,
    required this.plannedStage,
    required this.color,
    this.supportsRewind = true,
    this.arm32Core,
    this.arm32Note,
  });

  /// Si no es null, la consola no funciona en Android de 32 bits (su núcleo
  /// solo existe para 64 bits) y este es el motivo.
  final String? arm32Note;

  final String id;
  final String name;
  final String shortName;
  final String manufacturer;
  final int releaseYear;

  /// Extensiones de archivo aceptadas, en minúsculas y sin punto.
  final List<String> extensions;
  final String coreName;
  final String coreLicense;

  /// Biblioteca nativa del núcleo libretro (null si aún no está compilado).
  final String? coreLibrary;

  /// Nombre del sistema en libretro-database / libretro-thumbnails
  /// (p. ej. "Nintendo - Game Boy Advance"). Sirve para metadatos y portadas.
  final String? libretroSystem;

  final String? _note;
  final CoreStatus _status;

  /// Si no es null, la consola no está en la versión de Windows y este es el motivo.
  final String? windowsNote;

  /// Si no es null, la consola no está en la versión de iPhone y este es el motivo.
  final String? iosNote;

  bool get _missingHere =>
      (arm32Note != null && isArm32Process()) ||
      (windowsNote != null && isWindowsDesktop()) ||
      (iosNote != null && isIOSDevice() && !iosHasCore(coreLibrary));

  /// Estado en este dispositivo (en Windows algunas consolas aún no existen).
  CoreStatus get status => _missingHere ? CoreStatus.unavailable : _status;

  /// Explicación visible cuando el núcleo no está disponible.
  String? get note => !_missingHere
      ? _note
      : arm32Note != null && isArm32Process()
          ? arm32Note
          : isIOSDevice()
              ? iosNote
              : windowsNote;

  /// Etapa del plan en la que se integra el núcleo.
  final int plannedStage;
  final Color color;

  /// Si se puede rebobinar. Rebobinar guarda el estado completo varias veces
  /// por segundo; en consolas con mucha memoria (DS) eso frena la emulación.
  final bool supportsRewind;

  /// Núcleo alternativo para procesos de 32 bits, cuando el principal no
  /// tiene recompilador para ellos y sería demasiado lento.
  final CoreBuild? arm32Core;

  /// Núcleo que se usa en este dispositivo.
  CoreBuild get activeCore => arm32Core != null && isArm32Process()
      ? arm32Core!
      : CoreBuild(name: coreName, license: coreLicense, library: coreLibrary);
}
