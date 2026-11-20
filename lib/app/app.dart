import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../controllers/gamepad_navigator.dart';
import '../download_manager/download_manager.dart';
import '../settings/app_settings.dart';
import 'router.dart';
import 'theme.dart';
import 'ui_sound.dart';

class RetroStationApp extends ConsumerStatefulWidget {
  const RetroStationApp({super.key});

  @override
  ConsumerState<RetroStationApp> createState() => _RetroStationAppState();
}

class _RetroStationAppState extends ConsumerState<RetroStationApp> {
  late final GoRouter _router = buildRouter();

  @override
  void initState() {
    super.initState();
    UiSound.play(Sfx.on); // sonido de encendido
    // F11 (pantalla completa en el PC) lo atiende windows/runner/main.cpp.
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    UiSound.enabled = settings.uiSounds;
    UiSound.volume = settings.volume;
    // Mantiene vivo el gestor de descargas para que procese las tareas que
    // terminan aunque ninguna pantalla de descargas esté abierta.
    ref.watch(downloadsProvider);
    return MaterialApp.router(
      title: 'RetroStation',
      debugShowCheckedModeBanner: false,
      theme: buildRetroTheme(settings),
      themeAnimationDuration: settings.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 250),
      routerConfig: _router,
      // Mando: moverse por los menús (cruceta), A para elegir y B para volver.
      builder: (context, child) => GamepadNavigator(
        settings: settings,
        onBack: () {
          if (_router.canPop()) _router.pop();
        },
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
