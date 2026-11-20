import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../brand/logo.dart';
import '../brand/retro.dart';
import '../settings/app_settings.dart';
import '../presentation/tutorial/tutorial_overlay.dart';
import 'ui_sound.dart';
import 'version.dart';
import 'whats_new.dart';

/// Estructura principal. En pantallas estrechas usa una barra inferior; en
/// horizontal o en tablet, una barra lateral con el logo. Cada pestaña
/// conserva su propio historial y posición de scroll.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Ancho a partir del cual se usa la barra lateral.
  static const railBreakpoint = 600.0;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'Inicio'),
    (Icons.sports_esports_outlined, Icons.sports_esports_rounded, 'Mis juegos'),
    (Icons.travel_explore_outlined, Icons.travel_explore_rounded, 'Descubrir'),
    (Icons.memory_outlined, Icons.memory_rounded, 'Consolas'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Ajustes'),
  ];

  void _select(int index) {
    UiSound.play(index == shell.currentIndex ? Sfx.move : Sfx.open);
    shell.goBranch(
      index,
      // Volver a tocar la pestaña activa regresa a su raíz.
      initialLocation: index == shell.currentIndex,
    );
  }

  /// Pestañas sobre el fondo de circuitos: sus pantallas son transparentes
  /// y encima van, opcionalmente, las líneas CRT.
  Widget _backdrop(BuildContext context, AppSettings settings, Widget child) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        RetroBackground(animate: !settings.reduceMotion),
        Theme(
          data: theme.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            appBarTheme: theme.appBarTheme.copyWith(backgroundColor: Colors.transparent),
          ),
          child: child,
        ),
        if (settings.crtEffect) const Scanlines(),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final wide = MediaQuery.sizeOf(context).width >= railBreakpoint;
    final layout = _layout(context, settings, wide);
    if (settings.tutorialDone) {
      // Quien ya hizo el tutorial y actualiza la app ve una vez las novedades.
      if (settings.seenVersion != appVersion) {
        WidgetsBinding.instance.addPostFrameCallback((_) => showWhatsNew(context, ref));
      }
      return layout;
    }
    // Primera vez (o "Ver el tutorial" en Ajustes): recorrido guiado encima.
    return Stack(
      children: [
        layout,
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: TutorialOverlay(
              shell: shell,
              railMode: wide,
              onFinish: () {
                final controller = ref.read(settingsProvider.notifier);
                // El tutorial ya incluye las novedades de esta versión.
                controller.update(
                    ref.read(settingsProvider).copyWith(tutorialDone: true, seenVersion: appVersion));
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _layout(BuildContext context, AppSettings settings, bool wide) {
    if (!wide) {
      return Scaffold(
        body: _backdrop(context, settings, shell),
        bottomNavigationBar: DecoratedBox(
          key: TutorialTargets.navigation,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: RetroPalette.line, width: 3)),
          ),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _select,
            destinations: [
              for (final (icon, selected, label) in _tabs)
                NavigationDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selected),
                  label: label,
                ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            key: TutorialTargets.navigation,
            right: false,
            // En un teléfono en horizontal la barra no cabe entera: se
            // desplaza, y ocupa todo el alto cuando sí cabe.
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: shell.currentIndex,
                      onDestinationSelected: _select,
                      groupAlignment: -1,
                      leading: const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 4),
                        child: LogoMark(size: 32),
                      ),
                      destinations: [
                        for (final (icon, selected, label) in _tabs)
                          NavigationRailDestination(
                            icon: Icon(icon),
                            selectedIcon: Icon(selected),
                            label: Text(label),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 3, thickness: 3),
          Expanded(child: _backdrop(context, settings, shell)),
        ],
      ),
    );
  }
}
