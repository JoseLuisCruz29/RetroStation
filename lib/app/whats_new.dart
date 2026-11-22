import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../settings/app_settings.dart';
import 'router.dart';
import 'version.dart';

bool _showing = false;

/// Aviso de novedades: se muestra una sola vez por versión a quien ya hizo
/// el tutorial (los usuarios nuevos las ven dentro del propio tutorial).
Future<void> showWhatsNew(BuildContext context, WidgetRef ref) async {
  if (_showing || !context.mounted) return;
  _showing = true;
  // Se marca antes de mostrarlo: si la app se cierra con el aviso abierto, no se repite.
  final controller = ref.read(settingsProvider.notifier);
  await controller.update(ref.read(settingsProvider).copyWith(seenVersion: appVersion));
  if (!context.mounted) {
    _showing = false;
    return;
  }
  final tryIt = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      Widget point(IconData icon, String title, String text) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(text,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          );
      return AlertDialog(
        title: const Text('Novedades de la $appVersion'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Multijugador LAN: juega con un amigo, cada uno en su teléfono o en '
                  'el PC, conectados a la misma Wi-Fi y sin internet.'),
              point(Icons.person_rounded, '1. Elige tu nombre',
                  'Abre «Multijugador» en Inicio. Tu nombre se guarda para la próxima vez.'),
              point(Icons.wifi_find_rounded, '2. Encuentra a tu amigo',
                  'Aparece solo si tiene la sección abierta en la misma Wi-Fi. Pulsa «Conectar».'),
              point(Icons.meeting_room_rounded, '3. Sala',
                  'Quien acepta es el anfitrión: elige el juego, los dos marcáis «Listo» y a jugar.'),
              point(Icons.gamepad_rounded, '¡Nuevo! Diseños de botones',
                  'En Ajustes > Controles táctiles elige cómo se ven los botones: Clásico, Consola, '
                      'Minimalista, Neón, Pixel o Cristal. Sirve para todas las consolas.'),
              point(Icons.phone_iphone_rounded, 'RetroStation para iPhone',
                  'La app llega al iPhone con sus emuladores, el multijugador y los mandos. '
                      'Se descarga desde la página de GitHub del proyecto.'),
              point(Icons.videogame_asset_rounded, '¡Nuevo! Sega Mega Drive / Genesis',
                  'Juegos de Mega Drive (.md, .gen, .smd) en el PC, Android e iPhone, con '
                      'multijugador por Wi-Fi.'),
              point(Icons.cable_rounded, 'Cable link de GBA',
                  'Cualquier juego de GBA con cable link (Kirby, Mario Kart...), cada uno con su '
                      'GBA y su partida. Elegid el modo multijugador dentro del juego en los dos.'),
              point(Icons.send_to_mobile_rounded, '¡Nuevo! Enviar juegos',
                  'En Multijugador, pulsa el icono de envío junto a otro dispositivo y elige los '
                      'juegos: se copian por la Wi-Fi a su biblioteca (teléfono o PC).'),
              point(Icons.wifi_tethering_rounded, '¡Nuevo! Multijugador de PSP',
                  'Ad hoc de PSP: cada uno con su juego (el mismo) y su partida. En la sala, elegid el '
                      'juego y dentro entrad los dos al modo multijugador inalámbrico.'),
              point(Icons.sports_esports_rounded, '¡Nuevo! Mandos en el PC',
                  'Pro Controller de Switch, Xbox o cualquier mando USB o Bluetooth. Muévete por los '
                      'menús con la cruceta, A para elegir y B para volver. F11: pantalla completa.'),
              point(Icons.sports_esports_rounded, 'También',
                  'Cooperativo en NES, SNES y PS1 e intercambios y combates de Pokémon.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Probar el multijugador')),
        ],
      );
    },
  );
  _showing = false;
  if (tryIt == true && context.mounted) await context.push(Routes.multiplayer);
}
