import 'package:material_ui/material_ui.dart';

import 'console.dart';

/// Registro central de consolas. Es la única fuente de verdad sobre qué
/// consolas existen, qué extensiones aceptan y en qué estado está su núcleo.
class ConsoleRegistry {
  ConsoleRegistry._();

  static const List<ConsoleDescriptor> all = [
    ConsoleDescriptor(
      id: 'gba',
      libretroSystem: 'Nintendo - Game Boy Advance',
      name: 'Game Boy Advance',
      shortName: 'GBA',
      manufacturer: 'Nintendo',
      releaseYear: 2001,
      extensions: ['gba'],
      coreName: 'mGBA 0.10.5',
      coreLicense: 'MPL-2.0',
      coreLibrary: 'libmgba_libretro.so',
      status: CoreStatus.available,
      plannedStage: 2,
      color: Color(0xFF8B5CF6),
    ),
    ConsoleDescriptor(
      id: 'gb',
      libretroSystem: 'Nintendo - Game Boy',
      name: 'Game Boy',
      shortName: 'GB',
      manufacturer: 'Nintendo',
      releaseYear: 1989,
      extensions: ['gb'],
      // mGBA también emula Game Boy y Game Boy Color.
      coreName: 'mGBA 0.10.5',
      coreLicense: 'MPL-2.0',
      coreLibrary: 'libmgba_libretro.so',
      status: CoreStatus.available,
      plannedStage: 8,
      color: Color(0xFF84CC16),
    ),
    ConsoleDescriptor(
      id: 'gbc',
      libretroSystem: 'Nintendo - Game Boy Color',
      name: 'Game Boy Color',
      shortName: 'GBC',
      manufacturer: 'Nintendo',
      releaseYear: 1998,
      extensions: ['gbc'],
      coreName: 'mGBA 0.10.5',
      coreLicense: 'MPL-2.0',
      coreLibrary: 'libmgba_libretro.so',
      status: CoreStatus.available,
      plannedStage: 8,
      color: Color(0xFFF59E0B),
    ),
    ConsoleDescriptor(
      id: 'nes',
      libretroSystem: 'Nintendo - Nintendo Entertainment System',
      name: 'Nintendo Entertainment System',
      shortName: 'NES',
      manufacturer: 'Nintendo',
      releaseYear: 1983,
      extensions: ['nes'],
      coreName: 'FCEUmm',
      coreLicense: 'GPL-2.0',
      coreLibrary: 'libfceumm_libretro.so',
      status: CoreStatus.available,
      plannedStage: 8,
      color: Color(0xFFEF4444),
    ),
    ConsoleDescriptor(
      id: 'snes',
      libretroSystem: 'Nintendo - Super Nintendo Entertainment System',
      name: 'Super Nintendo',
      shortName: 'SNES',
      manufacturer: 'Nintendo',
      releaseYear: 1990,
      extensions: ['sfc', 'smc'],
      coreName: 'Snes9x',
      coreLicense: 'Snes9x (no comercial)',
      coreLibrary: 'libsnes9x_libretro.so',
      status: CoreStatus.available,
      plannedStage: 8,
      color: Color(0xFF6366F1),
    ),
    ConsoleDescriptor(
      id: 'genesis',
      libretroSystem: 'Sega - Mega Drive - Genesis',
      name: 'Sega Mega Drive / Genesis',
      shortName: 'MD',
      manufacturer: 'Sega',
      releaseYear: 1988,
      extensions: ['md', 'gen', 'smd'],
      coreName: 'Genesis Plus GX',
      coreLicense: 'Genesis Plus GX (no comercial)',
      coreLibrary: 'libgenesis_plus_gx_libretro.so',
      status: CoreStatus.available,
      plannedStage: 9,
      color: Color(0xFF1D4ED8),
    ),
    ConsoleDescriptor(
      id: 'psx',
      iosNote: iosPendingNote,
      libretroSystem: 'Sony - PlayStation',
      name: 'PlayStation',
      shortName: 'PS1',
      manufacturer: 'Sony',
      releaseYear: 1994,
      // .exe = programa PS-X EXE (formato habitual de homebrew); se valida su cabecera.
      extensions: ['cue', 'chd', 'pbp', 'exe'],
      coreName: 'PCSX ReARMed',
      coreLicense: 'GPL-2.0',
      coreLibrary: 'libpcsx_rearmed_libretro.so',
      status: CoreStatus.available,
      plannedStage: 8,
      color: Color(0xFF3B82F6),
    ),
    ConsoleDescriptor(
      id: 'nds',
      iosNote: iosPendingNote,
      libretroSystem: 'Nintendo - Nintendo DS',
      name: 'Nintendo DS',
      shortName: 'NDS',
      manufacturer: 'Nintendo',
      releaseYear: 2004,
      extensions: ['nds'],
      coreName: 'melonDS',
      coreLicense: 'GPL-3.0',
      coreLibrary: 'libmelonds_libretro.so',
      status: CoreStatus.available,
      plannedStage: 8,
      color: Color(0xFF14B8A6),
      // El estado de la DS ocupa varios MB: copiarlo 6 veces por segundo para
      // rebobinar le quita demasiado tiempo al intérprete en móviles de 32 bits.
      supportsRewind: false,
      // melonDS solo tiene JIT en 64 bits; en Android de 32 bits su intérprete
      // no llega a la velocidad real. DeSmuME tiene JIT para ARM de 32 bits.
      arm32Core: CoreBuild(
        name: 'DeSmuME 2015 (JIT ARM)',
        license: 'GPL-2.0',
        library: 'libdesmume2015_libretro.so',
      ),
    ),
    ConsoleDescriptor(
      id: 'psp',
      iosNote: iosPendingNote,
      libretroSystem: 'Sony - PlayStation Portable',
      name: 'PlayStation Portable',
      shortName: 'PSP',
      manufacturer: 'Sony',
      releaseYear: 2004,
      extensions: ['iso', 'cso'],
      coreName: 'PPSSPP (JIT, OpenGL)',
      coreLicense: 'GPL-2.0',
      coreLibrary: 'libppsspp_libretro.so',
      status: CoreStatus.available,
      plannedStage: 8,
      color: Color(0xFF0EA5E9),
      // Estados de decenas de MB: rebobinar sería demasiado costoso.
      supportsRewind: false,
    ),
  ];

  static ConsoleDescriptor? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Consola que corresponde a una extensión de archivo (`.gba`, `GBA`...).
  static ConsoleDescriptor? byExtension(String extension) {
    final ext = extension.toLowerCase().replaceFirst('.', '');
    for (final c in all) {
      if (c.extensions.contains(ext)) return c;
    }
    return null;
  }

  static int get availableCount =>
      all.where((c) => c.status == CoreStatus.available).length;
}
