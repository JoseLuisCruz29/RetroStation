import 'dart:async';

import 'package:retrostation/engines/console.dart';

/// Las pruebas simulan la app del teléfono aunque se ejecuten en un PC con
/// Windows: las que necesitan la versión de escritorio lo indican ellas mismas
/// cambiando [isWindowsDesktop].
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  isWindowsDesktop = () => false;
  await testMain();
}
