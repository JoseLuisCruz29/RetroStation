import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/storage/path_relocation.dart';

void main() {
  const newRoot = '/var/mobile/Containers/Data/Application/9EE6/Library/Application Support/retrostation';
  const oldRom = '/var/mobile/Containers/Data/Application/F9F0/Library/Application Support/retrostation/roms/DBZ.iso';

  test('una ruta de una instalación anterior pasa a la carpeta actual', () {
    expect(relocatedPath(oldRom, newRoot), '$newRoot/roms/DBZ.iso');
  });

  test('las rutas ya correctas, vacías o ajenas no cambian', () {
    expect(relocatedPath('$newRoot/roms/DBZ.iso', newRoot), isNull);
    expect(relocatedPath(null, newRoot), isNull);
    expect(relocatedPath('', newRoot), isNull);
    expect(relocatedPath('/otra/carpeta/juego.iso', newRoot), isNull);
  });

  test('rutas de Windows con barras invertidas', () {
    const root = r'C:\Users\x\AppData\Roaming\Jose Cruz\RetroStation\retrostation';
    expect(relocatedPath(r'C:\Users\x\AppData\Roaming\Jose Cruz\RetroStation\retrostation\roms\a.gba', root),
        isNull);
  });
}
