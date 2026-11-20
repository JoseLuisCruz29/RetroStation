import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:retrostation/storage/app_paths.dart';
import 'package:retrostation/storage/database.dart';

AppDatabase memoryDatabase() {
  // Las pruebas abren varias bases en memoria; no es un error.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Future<AppPaths> tempPaths() async {
  final dir = await Directory.systemTemp.createTemp('retrostation_test_');
  final paths = AppPaths(dir);
  await paths.ensureCreated();
  return paths;
}
