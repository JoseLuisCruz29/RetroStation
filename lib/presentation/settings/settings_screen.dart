import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/router.dart';
import '../../app/version.dart';
import '../../brand/logo.dart';
import '../../engines/console.dart';
import '../../engines/console_registry.dart';
import '../../core/format.dart';
import '../../discovery/discovery_service.dart';
import '../../emulation/bios_manager.dart';
import '../../save_manager/backup_service.dart';
import '../../storage/app_paths.dart';
import '../../settings/app_settings.dart';
import '../../storage/storage_providers.dart';
import '../player/touch_controls.dart';
import '../../controllers/touch_layout.dart';
import '../../emulation/native_bindings.dart';
import '../widgets/section_header.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionHeader('Apariencia'),
          _SegmentTile<BackgroundStyle>(
            title: 'Fondo',
            values: BackgroundStyle.values,
            selected: settings.background,
            label: (v) => v.label,
            onChanged: (v) => controller.update(settings.copyWith(background: v)),
          ),
          _SegmentTile<AccentColor>(
            title: 'Color de acento',
            values: AccentColor.values,
            selected: settings.accent,
            label: (v) => v.label,
            onChanged: (v) => controller.update(settings.copyWith(accent: v)),
          ),
          SwitchListTile(
            title: const Text('Reducir animaciones'),
            subtitle: const Text('Desactiva las transiciones y el fondo en movimiento'),
            value: settings.reduceMotion,
            onChanged: (v) => controller.update(settings.copyWith(reduceMotion: v)),
          ),
          SwitchListTile(
            title: const Text('Efecto CRT'),
            subtitle: const Text('Líneas de barrido suaves en los menús'),
            value: settings.crtEffect,
            onChanged: (v) => controller.update(settings.copyWith(crtEffect: v)),
          ),
          const SectionHeader('Audio'),
          SwitchListTile(
            title: const Text('Sonidos de la interfaz'),
            subtitle: const Text('Efectos al tocar y al abrir o cerrar pantallas'),
            value: settings.uiSounds,
            onChanged: (v) => controller.update(settings.copyWith(uiSounds: v)),
          ),
          _SliderTile(
            icon: Icons.volume_up_rounded,
            title: 'Volumen',
            value: settings.volume,
            min: 0,
            max: 1,
            label: '${(settings.volume * 100).round()} %',
            onChanged: (v) => controller.update(settings.copyWith(volume: v)),
          ),
          if (isWindowsDesktop() || isIOSDevice()) ...[
            SectionHeader(isWindowsDesktop() ? 'Teclado y mando' : 'Mando'),
            if (isWindowsDesktop())
              ListTile(
                leading: const Icon(Icons.keyboard_rounded),
                title: const Text('Cambiar las teclas de juego'),
                subtitle: Text(settings.keyboard.isEmpty ? 'Teclas de fábrica' : 'Personalizadas'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.keyboard),
              ),
            ListTile(
              leading: const Icon(Icons.sports_esports_rounded),
              title: const Text('Mando'),
              subtitle: const Text('Pro Controller de Switch, Xbox, PlayStation o cualquier mando USB/Bluetooth'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.gamepad),
            ),
          ],
          const SectionHeader('Controles táctiles'),
          _SkinPicker(
            selected: settings.controlSkin,
            opacity: settings.controlsOpacity,
            onChanged: (v) => controller.update(settings.copyWith(controlSkin: v)),
          ),
          _SliderTile(
            icon: Icons.opacity_rounded,
            title: 'Opacidad',
            value: settings.controlsOpacity,
            min: 0.15,
            max: 1,
            label: '${(settings.controlsOpacity * 100).round()} %',
            onChanged: (v) => controller.update(settings.copyWith(controlsOpacity: v)),
          ),
          _SliderTile(
            icon: Icons.open_in_full_rounded,
            title: 'Tamaño',
            value: settings.controlsScale,
            min: 0.7,
            max: 1.4,
            label: '${(settings.controlsScale * 100).round()} %',
            onChanged: (v) => controller.update(settings.copyWith(controlsScale: v)),
          ),
          ListTile(
            leading: const Icon(Icons.open_with_rounded),
            title: const Text('Editar posición y tamaño de cada botón'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.controlsEditor),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration_rounded),
            title: const Text('Vibración al pulsar'),
            value: settings.haptics,
            onChanged: (v) => controller.update(settings.copyWith(haptics: v)),
          ),
          const SectionHeader('Juego'),
          _SegmentTile<PlayerOrientation>(
            title: 'Orientación',
            values: PlayerOrientation.values,
            selected: settings.orientation,
            label: (v) => v.label,
            onChanged: (v) => controller.update(settings.copyWith(orientation: v)),
          ),
          if (isWindowsDesktop())
            _SegmentTile<GraphicsQuality>(
              title: 'Calidad gráfica (PC)',
              values: GraphicsQuality.values,
              selected: settings.pcQuality,
              label: (v) => v.label,
              onChanged: (v) => controller.update(settings.copyWith(pcQuality: v)),
            ),
          _SegmentTile<VideoFilter>(
            title: 'Filtro de imagen',
            values: VideoFilter.values,
            selected: settings.videoFilter,
            label: (v) => v.label,
            onChanged: (v) => controller.update(settings.copyWith(videoFilter: v)),
          ),
          _SegmentTile<int>(
            title: 'Velocidad de avance rápido',
            values: AppSettings.fastForwardOptions,
            selected: settings.fastForwardSpeed,
            label: (v) => 'x$v',
            onChanged: (v) => controller.update(settings.copyWith(fastForwardSpeed: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fast_rewind_rounded),
            title: const Text('Rebobinado'),
            subtitle: const Text('Guarda los últimos 20 s en memoria (usa más RAM y CPU)'),
            value: settings.rewindEnabled,
            onChanged: (v) => controller.update(settings.copyWith(rewindEnabled: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.speed_rounded),
            title: const Text('Mostrar FPS'),
            value: settings.showFps,
            onChanged: (v) => controller.update(settings.copyWith(showFps: v)),
          ),
          const SectionHeader('Fuentes de Descubrir'),
          for (final source in ref.watch(sourceAdaptersProvider))
            SwitchListTile(
              title: Text(source.name),
              subtitle: Text(source.description),
              isThreeLine: true,
              value: !settings.disabledSources.contains(source.id),
              onChanged: (on) => controller.update(settings.copyWith(
                disabledSources: on
                    ? ({...settings.disabledSources}..remove(source.id))
                    : {...settings.disabledSources, source.id},
              )),
            ),
          const SectionHeader('Consolas'),
          ListTile(
            leading: const Icon(Icons.memory_rounded),
            title: const Text('Consolas y núcleos'),
            subtitle: const Text('Estado de cada motor de emulación'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.go(Routes.consoles),
          ),
          const _BiosTile(),
          SectionHeader(
            'Almacenamiento',
            trailing: IconButton(
              tooltip: 'Recalcular',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.invalidate(storageUsageProvider),
            ),
          ),
          const _StorageSection(),
          const SectionHeader('Copias de seguridad'),
          const _BackupSection(),
          const SectionHeader('Ayuda'),
          ListTile(
            leading: const Icon(Icons.school_rounded),
            title: const Text('Ver el tutorial'),
            subtitle: const Text('Recorrido guiado por la app, paso a paso'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => controller.update(settings.copyWith(tutorialDone: false)),
          ),
          const SectionHeader('Acerca de'),
          ListTile(
            leading: const LogoMark(size: 32),
            title: const Text('RetroStation'),
            subtitle: Text(
                'Creado por $appAuthor · Versión $appVersion · ${ConsoleRegistry.availableCount} consolas · '
                'Toca para ver las licencias'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'RetroStation',
              applicationVersion: appVersion,
              applicationLegalese: 'Creado por $appAuthor',
              applicationIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: LogoMark(size: 56),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Los ajustes de cada núcleo (BIOS, saltar fotogramas, filtro de audio...) '
              'están en Consolas y núcleos > icono de ajustes de cada consola.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTile<T> extends StatelessWidget {
  const _SegmentTile({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              segments: [
                for (final v in values)
                  ButtonSegment(value: v, label: Text(label(v))),
              ],
              selected: {selected},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// BIOS opcional de GBA aportada por el usuario (se valida por SHA-1).
class _BiosTile extends ConsumerStatefulWidget {
  const _BiosTile();

  @override
  ConsumerState<_BiosTile> createState() => _BiosTileState();
}

class _BiosTileState extends ConsumerState<_BiosTile> {
  Future<void> _install() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Elige gba_bios.bin');
    final path = picked?.path;
    if (path == null) return;
    final error = await ref.read(biosManagerProvider).install(BiosManager.gba, path);
    await FilePicker.clearTemporaryFiles();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'BIOS instalada: se usará al abrir el próximo juego'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bios = ref.watch(biosManagerProvider);
    final installed = bios.isInstalled(BiosManager.gba);
    return ListTile(
      leading: const Icon(Icons.developer_board_rounded),
      title: const Text('BIOS de Game Boy Advance (opcional)'),
      subtitle: Text(installed
          ? 'Instalada y verificada'
          : 'No instalada: se usa la BIOS emulada de mGBA. '
              'Solo se acepta un volcado oficial (gba_bios.bin).'),
      isThreeLine: !installed,
      trailing: installed
          ? IconButton(
              tooltip: 'Quitar BIOS',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await bios.remove(BiosManager.gba);
                if (mounted) setState(() {});
              },
            )
          : TextButton(onPressed: _install, child: const Text('Instalar')),
    );
  }
}

class _BackupSection extends ConsumerStatefulWidget {
  const _BackupSection();

  @override
  ConsumerState<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<_BackupSection> {
  bool _busy = false;

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final (bytes, report) = await ref.read(backupServiceProvider).export();
      final now = DateTime.now();
      final name = 'retrostation-partidas-${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}.zip';
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: 'application/zip',
        dialogTitle: 'Guardar copia de seguridad',
      );
      if (!mounted) return;
      _snack(uri == null
          ? 'Copia cancelada'
          : 'Copia guardada: ${report.saves} partida(s) y ${report.states} save state(s)');
    } catch (e) {
      if (mounted) _snack('No se pudo crear la copia: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Elige una copia de RetroStation (.zip)');
    final path = picked?.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(backupServiceProvider).import(path);
      if (mounted) {
        _snack('Restaurado: ${r.saves} partida(s) y ${r.states} save state(s)'
            '${r.skipped > 0 ? ' · ${r.skipped} archivo(s) ignorado(s)' : ''}');
      }
    } catch (e) {
      if (mounted) _snack('No se pudo restaurar: $e');
    } finally {
      await FilePicker.clearTemporaryFiles();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        ListTile(
          leading: const Icon(Icons.upload_file_rounded),
          title: const Text('Exportar partidas'),
          subtitle: const Text('Partidas del cartucho y save states en un archivo ZIP'),
          enabled: !_busy,
          onTap: _export,
        ),
        ListTile(
          leading: const Icon(Icons.restore_rounded),
          title: const Text('Restaurar desde una copia'),
          subtitle: const Text('Sobrescribe las partidas con el mismo juego y ranura'),
          enabled: !_busy,
          onTap: _import,
        ),
      ]);
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Row(
        children: [
          Expanded(child: Text(title)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}

class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(storageUsageProvider);
    final paths = ref.watch(appPathsProvider);
    return usage.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => ListTile(title: Text('No se pudo calcular: $e')),
      data: (sizes) {
        final total = sizes.values.fold<int>(0, (a, b) => a + b);
        return Column(
          children: [
            for (final e in sizes.entries)
              ListTile(
                dense: true,
                title: Text(e.key),
                trailing: Text(formatBytes(e.value)),
              ),
            ListTile(
              dense: true,
              title: const Text('Total',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text(formatBytes(total),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              dense: true,
              title: const Text('Ubicación'),
              subtitle: SelectableText(paths.root.path),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('Liberar espacio'),
              subtitle: const Text(
                  'Borra la caché de bases de datos de metadatos y las copias .bak de los '
                  'save states. No toca juegos ni partidas.'),
              onTap: () async {
                final freed = await _cleanCaches(paths);
                ref.invalidate(storageUsageProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Liberados ${formatBytes(freed)}')));
                }
              },
            ),
          ],
        );
      },
    );
  }

  /// Borra solo datos regenerables: DAT de metadatos (se vuelven a descargar
  /// al identificar un juego) y copias `.bak` de save states.
  static Future<int> _cleanCaches(AppPaths paths) async {
    var freed = 0;
    Future<void> rm(File f) async {
      freed += await f.length();
      await f.delete();
    }

    final metadata = Directory(p.join(paths.root.path, 'metadata'));
    if (await metadata.exists()) {
      await for (final f in metadata.list()) {
        if (f is File) await rm(f);
      }
    }
    if (await paths.states.exists()) {
      await for (final f in paths.states.list(recursive: true)) {
        if (f is File && f.path.endsWith('.bak')) await rm(f);
      }
    }
    return freed;
  }
}

/// Diseño de los controles táctiles: una vista previa de cada uno (cruceta,
/// A/B y START) que se elige tocándola. Vale para todas las consolas.
class _SkinPicker extends StatelessWidget {
  const _SkinPicker({required this.selected, required this.opacity, required this.onChanged});

  final ControlSkin selected;
  final double opacity;
  final ValueChanged<ControlSkin> onChanged;

  static const _previewSize = Size(150, 84);

  /// Controles de muestra: cruceta a la izquierda, A y B a la derecha (con A
  /// "pulsado" para ver cómo se ve) y START abajo.
  static final _sample = [
    const ControlRegion(id: 'dpad', shape: ControlShape.dpad, center: Offset(36, 40), size: Size(56, 56)),
    const ControlRegion(
        id: 'a', shape: ControlShape.circle, center: Offset(126, 30), size: Size(30, 30),
        button: RetroButton.a, label: 'A'),
    const ControlRegion(
        id: 'b', shape: ControlShape.circle, center: Offset(96, 48), size: Size(30, 30),
        button: RetroButton.b, label: 'B'),
    const ControlRegion(
        id: 'start', shape: ControlShape.pill, center: Offset(111, 74), size: Size(46, 14),
        button: RetroButton.start, label: 'START'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Diseño de los botones', style: theme.textTheme.bodyLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Text('${selected.label}: ${selected.description}. Se usa en todas las consolas.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          SizedBox(
            height: _previewSize.height + 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: ControlSkin.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final skin = ControlSkin.values[i];
                final isSelected = skin == selected;
                return Semantics(
                  selected: isSelected,
                  button: true,
                  label: 'Diseño ${skin.label}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged(skin),
                    child: Column(
                      children: [
                        Container(
                          width: _previewSize.width,
                          height: _previewSize.height,
                          decoration: BoxDecoration(
                            // Fondo oscuro con algo de color, como la imagen de un juego.
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF1E3A4C), Color(0xFF101418)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? accent : theme.colorScheme.outlineVariant,
                              width: isSelected ? 3 : 1.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CustomPaint(
                              painter: ControlsPainter(
                                regions: _sample,
                                mask: 1 << RetroButton.a,
                                opacity: opacity,
                                accent: accent,
                                skin: skin,
                                consoleId: 'snes',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              Icon(Icons.check_rounded, size: 16, color: accent),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              skin.label,
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: isSelected ? accent : null),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
