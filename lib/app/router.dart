import 'package:go_router/go_router.dart';

import '../presentation/consoles/console_settings_screen.dart';
import '../presentation/consoles/consoles_screen.dart';
import '../presentation/settings/controls_editor_screen.dart';
import '../presentation/settings/gamepad_screen.dart';
import '../presentation/settings/keyboard_screen.dart';
import '../discovery/discovery_models.dart';
import '../presentation/discovery/discovery_item_screen.dart';
import '../presentation/discovery/discovery_screen.dart';
import '../presentation/downloads/downloads_screen.dart';
import '../presentation/game_detail/game_detail_screen.dart';
import '../presentation/home/home_screen.dart';
import '../presentation/library/library_screen.dart';
import '../multiplayer/lan_service.dart';
import '../presentation/multiplayer/multiplayer_screen.dart';
import '../presentation/multiplayer/room_screen.dart';
import '../presentation/player/player_screen.dart';
import '../presentation/saves/saves_screen.dart';
import '../presentation/settings/settings_screen.dart';
import 'shell.dart';
import 'ui_sound.dart';

abstract final class Routes {
  static const home = '/';
  static const discovery = '/discovery';
  static const library = '/library';
  static const saves = '/saves';
  static const settings = '/settings';
  static const consoles = '/consoles';

  static String libraryForConsole(String consoleId) =>
      '$library?console=$consoleId';
  static const discoveryItem = '/discover/item';
  static const downloads = '/downloads';
  static const controlsEditor = '/controls-editor';
  static const keyboard = '/keyboard';
  static const gamepad = '/gamepad';
  static const multiplayer = '/multiplayer';
  static const multiplayerRoom = '/multiplayer/room';
  static String consoleSettings(String id) => '/console/$id/settings';
  static String game(int gameId) => '/game/$gameId';
  static String player(int gameId, {int? slot}) =>
      slot == null ? '/play/$gameId' : '/play/$gameId?slot=$slot';
}

GoRouter buildRouter() => GoRouter(
      initialLocation: Routes.home,
      observers: [UiSoundObserver()],
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: Routes.home,
                builder: (_, _) => const HomeScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: Routes.library,
                builder: (_, state) => LibraryScreen(
                  consoleId: state.uri.queryParameters['console'],
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: Routes.discovery,
                builder: (_, _) => const DiscoveryScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: Routes.consoles,
                builder: (_, _) => const ConsolesScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: Routes.settings,
                builder: (_, _) => const SettingsScreen(),
              ),
            ]),
          ],
        ),
        GoRoute(
          path: Routes.saves,
          builder: (_, _) => const SavesScreen(),
        ),
        GoRoute(
          path: Routes.discoveryItem,
          builder: (_, state) => DiscoveryItemScreen(item: state.extra! as DiscoveryItem),
        ),
        GoRoute(
          path: '/console/:id/settings',
          builder: (_, state) => ConsoleSettingsScreen(consoleId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: Routes.controlsEditor,
          builder: (_, _) => const ControlsEditorScreen(),
        ),
        GoRoute(
          path: Routes.gamepad,
          builder: (_, _) => const GamepadScreen(),
        ),
        GoRoute(
          path: Routes.keyboard,
          builder: (_, _) => const KeyboardScreen(),
        ),
        GoRoute(
          path: Routes.multiplayer,
          builder: (_, _) => const MultiplayerScreen(),
        ),
        GoRoute(
          path: Routes.multiplayerRoom,
          builder: (_, _) => const RoomScreen(),
        ),
        GoRoute(
          path: Routes.downloads,
          builder: (_, _) => const DownloadsScreen(),
        ),
        GoRoute(
          path: '/game/:gameId',
          builder: (_, state) => GameDetailScreen(
            gameId: int.parse(state.pathParameters['gameId']!),
          ),
        ),
        GoRoute(
          path: '/play/:gameId',
          builder: (_, state) => PlayerScreen(
            gameId: int.parse(state.pathParameters['gameId']!),
            loadSlot: int.tryParse(state.uri.queryParameters['slot'] ?? ''),
            netplay: state.extra is NetplayArgs ? state.extra! as NetplayArgs : null,
          ),
        ),
      ],
    );
