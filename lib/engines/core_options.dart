import '../settings/app_settings.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database.dart';
import 'console.dart';
import 'console_registry.dart';
import '../storage/storage_providers.dart';

/// Opción de un núcleo libretro expuesta en "Ajustes por consola".
/// Las claves, valores y valores por defecto salen del código del núcleo
/// (mGBA: `src/platform/libretro/libretro_core_options.h`).
class CoreOption {
  const CoreOption({
    required this.key,
    required this.label,
    required this.description,
    required this.values,
    required this.defaultValue,
    this.requiresRestart = false,
  });

  final String key;
  final String label;
  final String description;

  /// Valor libretro -> texto visible.
  final Map<String, String> values;
  final String defaultValue;
  final bool requiresRestart;
}

abstract final class CoreOptions {
  static const _mgba = [
    CoreOption(
      key: 'mgba_use_bios',
      label: 'Usar la BIOS si está instalada',
      description: 'Con la BIOS oficial la emulación es más exacta. Sin ella se usa la BIOS emulada.',
      values: {'ON': 'Sí', 'OFF': 'No'},
      defaultValue: 'ON',
      requiresRestart: true,
    ),
    CoreOption(
      key: 'mgba_skip_bios',
      label: 'Saltar la intro de la BIOS',
      description: 'Omite el logotipo de arranque cuando se usa la BIOS oficial.',
      values: {'OFF': 'No', 'ON': 'Sí'},
      defaultValue: 'OFF',
      requiresRestart: true,
    ),
    CoreOption(
      key: 'mgba_frameskip',
      label: 'Saltar fotogramas',
      description: 'Dibuja menos fotogramas para ganar velocidad en teléfonos lentos. '
          'El juego sigue a velocidad normal.',
      values: {'0': 'Ninguno', '1': '1', '2': '2', '3': '3'},
      defaultValue: '0',
    ),
    CoreOption(
      key: 'mgba_idle_optimization',
      label: 'Optimizar bucles de espera',
      description: 'Ahorra CPU y batería cuando el juego espera sin hacer nada.',
      values: {
        'Remove Known': 'Conocidos',
        'Detect and Remove': 'Detectar',
        "Don't Remove": 'Desactivado',
      },
      defaultValue: 'Remove Known',
      requiresRestart: true,
    ),
    CoreOption(
      key: 'mgba_audio_low_pass_filter',
      label: 'Filtro de audio',
      description: 'Suaviza el sonido agudo y metálico del altavoz original.',
      values: {'disabled': 'No', 'enabled': 'Sí'},
      defaultValue: 'disabled',
    ),
    CoreOption(
      key: 'mgba_allow_opposing_directions',
      label: 'Permitir direcciones opuestas',
      description: 'Permite pulsar izquierda+derecha a la vez. Algunos juegos fallan con ello.',
      values: {'no': 'No', 'yes': 'Sí'},
      defaultValue: 'no',
    ),
  ];

  /// Opciones que la app necesita y no se muestran al usuario.
  static Map<String, String> required(String consoleId) =>
      switch ((consoleId, ConsoleRegistry.byId(consoleId)?.activeCore.library)) {
        // DeSmuME (Android de 32 bits): JIT, pantalla táctil por "pointer" y
        // pantallas una encima de otra.
        ('nds', final lib?) when lib.startsWith('libdesmume') => const {
            'desmume_cpu_mode': 'jit',
            // Bloques del JIT de hasta 100 instrucciones (el valor del propio
            // DeSmuME). La lista de opciones empieza por 12, y con bloques tan
            // cortos el JIT sale de su código traducido cada pocas
            // instrucciones: era el principal coste del hilo de emulación.
            'desmume_jit_block_size': '100',
            'desmume_pointer_mouse': 'enabled',
            'desmume_pointer_type': 'touch',
            'desmume_screens_layout': 'top/bottom',
            'desmume_screens_gap': '0',
            'desmume_internal_resolution': '256x192',
            // Hilos para el 3D por software (el teléfono tiene 8 núcleos).
            'desmume_num_cores': '4',
            // Leer el ROM del archivo: cargarlo entero duplicaría la memoria
            // en un proceso de 32 bits con juegos de 128 MB o más.
            'desmume_load_to_memory': 'disabled',
            // Se compila sin temporización avanzada (ver native/cores/desmume.cmake).
            'desmume_advanced_timing': 'disabled',
          },
        // PPSSPP: JIT (en iPhone, su intérprete IR: iOS no permite JIT),
        // resolución nativa de la PSP (la GPU del móvil escala la imagen) y
        // OpenGL ES, que es lo que ofrece el frontend.
        ('psp', _) => {
            'ppsspp_cpu_core': isIOSDevice() ? 'IR JIT' : 'JIT',
            'ppsspp_backend': 'opengl',
            'ppsspp_internal_resolution': '480x272',
            'ppsspp_fast_memory': 'enabled',
            'ppsspp_button_preference': 'Cross',
            'ppsspp_language': 'Spanish',
            'ppsspp_io_timing_method': 'Fast',
            // No esperar a la GPU para leer imágenes: gran ahorro en móviles.
            'ppsspp_skip_gpu_readbacks': 'enabled',
          },
        // Mupen64Plus-Next: GLideN64 por GPU, RSP en HLE y sin el renderizador
        // en otro hilo (el motor ya ejecuta el núcleo en su propio hilo).
        ('n64', _) => const {
            'mupen64plus-rdp-plugin': 'gliden64',
            'mupen64plus-rsp-plugin': 'hle',
            'mupen64plus-cpucore': 'cached_interpreter',
            'mupen64plus-ThreadedRenderer': 'False',
            'mupen64plus-43screensize': '640x480',
          },
        // melonDS: pantalla táctil por "pointer" (por defecto viene desactivada)
        // y las dos pantallas una encima de otra.
        ('nds', _) => const {
            'melonds_touch_mode': 'Touch',
            'melonds_screen_layout': 'Top/Bottom',
            // Sin BIOS/firmware reales no hay menú de consola: arrancar el juego.
            'melonds_boot_directly': 'enabled',
            // El 3D por software se dibuja en otro hilo (el teléfono tiene
            // varios núcleos y la emulación de la CPU ocupa uno entero).
            'melonds_threaded_renderer': 'enabled',
          },
        // Azahar: OpenGL (lo que ofrece el frontend), pantallas una encima de
        // otra y pantalla táctil con el dedo (pointer). El joystick derecho
        // es el C-Stick, no un puntero.
        ('3ds', _) => {
            // En iPhone Azahar solo tiene Vulkan (MoltenVK).
            'citra_graphics_api': isIOSDevice() ? 'Vulkan' : 'OpenGL',
            'citra_layout_option': 'default',
            'citra_enable_touch_touchscreen': 'enabled',
            'citra_enable_mouse_touchscreen': 'disabled',
            'citra_analog_function': 'c_stick',
            'citra_use_virtual_sd': 'enabled',
            'citra_use_libretro_save_path': 'LibRetro Default',
            'citra_language_value': 'Spanish',
            'citra_resolution_factor': '1',
            // Sombreadores ya compilados en disco: el juego no se traba la
            // segunda vez que aparece un efecto.
            'citra_use_disk_shader_cache': 'enabled',
            if (isIOSDevice()) 'citra_use_fastinterp': 'enabled',
          },
        _ => const {},
      };

  /// Opciones de DeSmuME que el usuario puede cambiar en Consolas > NDS.
  static const _desmume = [
    CoreOption(
      key: 'desmume_frameskip',
      label: 'Saltar fotogramas',
      description: 'Dibuja menos imágenes por segundo para que el juego vaya a su '
          'velocidad real y el sonido no se corte. 1 = dibuja la mitad.',
      values: {'0': 'No', '1': '1', '2': '2', '3': '3'},
      defaultValue: '1',
    ),
  ];

  /// Opciones de PPSSPP que el usuario puede cambiar en Consolas > PSP.
  static const _ppsspp = [
    CoreOption(
      key: 'ppsspp_frameskip',
      label: 'Saltar fotogramas',
      description: 'Dibuja menos imágenes si el juego va lento. Automático salta solo cuando hace falta.',
      values: {'disabled': 'No', '1': '1', '2': '2', '3': '3'},
      defaultValue: 'disabled',
    ),
    CoreOption(
      key: 'ppsspp_auto_frameskip',
      label: 'Salto automático',
      description: 'Salta fotogramas solo cuando el juego no llega a su velocidad.',
      values: {'disabled': 'No', 'enabled': 'Sí'},
      defaultValue: 'enabled',
    ),
    CoreOption(
      key: 'ppsspp_internal_resolution',
      label: 'Resolución interna',
      description: 'Más resolución se ve más nítido pero exige más a la GPU.',
      values: {'480x272': '1x (original)', '960x544': '2x', '1440x816': '3x'},
      defaultValue: '480x272',
      requiresRestart: true,
    ),
  ];

  /// Opciones por consola (mGBA también emula GB/GBC).
  static List<CoreOption> forConsole(String consoleId) => switch (consoleId) {
        'gba' || 'gb' || 'gbc' => _mgba,
        'nds' when ConsoleRegistry.byId('nds')?.activeCore.library?.startsWith('libdesmume') ?? false =>
          _desmume,
        'psp' => _ppsspp,
        _ => const [],
      };
}

/// Valores elegidos por el usuario, guardados como `core.<consola>.<clave>`.
class CoreOptionsRepository {
  CoreOptionsRepository(this._db);

  final AppDatabase _db;

  static String _prefix(String consoleId) => 'core.$consoleId.';

  Stream<Map<String, String>> watch(String consoleId) {
    final prefix = _prefix(consoleId);
    return (_db.select(_db.settingEntries)..where((s) => s.key.like('$prefix%')))
        .watch()
        .map((rows) => {for (final r in rows) r.key.substring(prefix.length): r.value});
  }

  Future<Map<String, String>> load(String consoleId) => watch(consoleId).first;

  Future<void> set(String consoleId, String key, String? value) async {
    final full = '${_prefix(consoleId)}$key';
    if (value == null) {
      await (_db.delete(_db.settingEntries)..where((s) => s.key.equals(full))).go();
    } else {
      await _db.into(_db.settingEntries).insertOnConflictUpdate(
          SettingEntriesCompanion.insert(key: full, value: value));
    }
  }

  /// Valores efectivos: los obligatorios de la consola y los elegidos por el
  /// usuario, solo si siguen siendo válidos.
  ///
  /// [pcQuality] (solo en el PC): sube la resolución de PSP y PlayStation,
  /// salvo que el usuario haya elegido otra en Consolas.
  static Map<String, String> effective(String consoleId, Map<String, String> chosen,
          {GraphicsQuality? pcQuality}) =>
      {
        ...CoreOptions.required(consoleId),
        ...?switch ((consoleId, pcQuality)) {
          ('psp', GraphicsQuality.alta) => const {'ppsspp_internal_resolution': '960x544'},
          ('psp', GraphicsQuality.maxima) => const {'ppsspp_internal_resolution': '1440x816'},
          ('3ds', GraphicsQuality.alta) => const {'citra_resolution_factor': '2'},
          ('3ds', GraphicsQuality.maxima) => const {'citra_resolution_factor': '3'},
          ('psx', GraphicsQuality.alta || GraphicsQuality.maxima) => const {
              'pcsx_rearmed_neon_enhancement_enable': 'enabled',
            },
          _ => null,
        },
        // El valor elegido si sigue siendo válido; si no, el predeterminado
        // de la app (que puede diferir del del núcleo).
        for (final o in CoreOptions.forConsole(consoleId))
          if (pcQuality == null || chosen.containsKey(o.key) || o.key != 'ppsspp_internal_resolution')
            o.key: switch (chosen[o.key]) {
              final v? when o.values.containsKey(v) => v,
              _ => o.defaultValue,
            },
      };
}

final coreOptionsRepositoryProvider =
    Provider<CoreOptionsRepository>((ref) => CoreOptionsRepository(ref.watch(databaseProvider)));

final coreOptionsProvider = StreamProvider.family<Map<String, String>, String>(
  (ref, consoleId) => ref.watch(coreOptionsRepositoryProvider).watch(consoleId),
);
