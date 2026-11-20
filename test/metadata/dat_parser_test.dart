import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/metadata/dat_parser.dart';

// Extractos reales de libretro-database (metadat/no-intro, genre, releaseyear).
const _noIntro = '''
clrmamepro (
	name "Nintendo - Game Boy Advance"
	description "Nintendo - Game Boy Advance"
)

game (
	name "007 - Everything or Nothing (Japan)"
	region "Japan"
	serial "BJBJ"
	rom ( name "007 - Everything or Nothing (Japan).gba" size 8388608 crc CAF2E99F md5 55354D9E3BC9C1FA682B5110E5ED1544 sha1 6E4E9BE9A07580EF267BE9C2EA1BD0730B3BE44A serial "BJBJ" )
)

game (
	name "007 - Everything or Nothing (USA, Europe) (En,Fr,De)"
	region "USA / Europe"
	rom ( name "007 - Everything or Nothing (USA, Europe) (En,Fr,De).gba" size 8388608 crc 9D4F1E18 md5 B63B2244EDC2385AE1EAB9C8EE448C6F sha1 FC6163F99B71B05C10686A0D29010B31274E1DC4 serial "BJBE" )
)
''';

const _genres = '''
game (
	comment "007 - Everything or Nothing (Japan)"
	genre "Shooter"
	rom ( crc CAF2E99F )
)
''';

const _years = '''
game (
	comment "007 - Everything or Nothing (Japan)"
	releaseyear "2004"
	rom ( crc CAF2E99F )
)
''';

void main() {
  test('parsea juegos con nombre, región, CRC, SHA-1 y tamaño', () {
    final entries = parseDat(_noIntro);
    expect(entries, hasLength(2)); // la cabecera clrmamepro no es un juego
    final first = entries.first;
    expect(first.name, '007 - Everything or Nothing (Japan)');
    expect(first.region, 'Japan');
    expect(first.crc, 'CAF2E99F');
    expect(first.sha1, '6e4e9be9a07580ef267be9c2ea1bd0730b3be44a');
    expect(first.size, 8388608);
  });

  test('el índice combina No-Intro, género y año', () {
    final index = MetadataIndex.fromDats(noIntro: _noIntro, genres: _genres, years: _years);
    expect(index.size, 2);
    final meta = index.lookup('6E4E9BE9A07580EF267BE9C2EA1BD0730B3BE44A')!;
    expect(meta.name, '007 - Everything or Nothing (Japan)');
    expect(meta.genre, 'Shooter');
    expect(meta.releaseYear, 2004);

    final other = index.lookup('fc6163f99b71b05c10686a0d29010b31274e1dc4')!;
    expect(other.genre, isNull);
    expect(index.lookup('0' * 40), isNull);
  });

  test('nombre de portada de libretro-thumbnails', () {
    expect(thumbnailFileName('Mario & Luigi - Superstar Saga (USA)'),
        'Mario _ Luigi - Superstar Saga (USA).png');
    expect(thumbnailFileName('A/B: C?'), 'A_B_ C_.png');
  });
}
