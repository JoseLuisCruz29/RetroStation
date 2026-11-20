import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_paths.dart';
import 'database.dart';

/// Se sobrescriben en `main()` una vez abiertos la base de datos y los
/// directorios; así ninguna pantalla espera a la inicialización.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider no inicializado'),
);

final appPathsProvider = Provider<AppPaths>(
  (ref) => throw UnimplementedError('appPathsProvider no inicializado'),
);

final storageUsageProvider = FutureProvider<Map<String, int>>(
  (ref) => ref.watch(appPathsProvider).usage(),
);
