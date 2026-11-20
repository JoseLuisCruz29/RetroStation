import 'package:flutter_test/flutter_test.dart';
import 'package:retrostation/engines/core_options.dart';
import 'package:retrostation/settings/app_settings.dart';

void main() {
  test('calidad del PC: PSP a 2x/3x y PlayStation con resolución mejorada', () {
    expect(CoreOptionsRepository.effective('psp', const {})['ppsspp_internal_resolution'], '480x272');
    expect(
        CoreOptionsRepository.effective('psp', const {}, pcQuality: GraphicsQuality.alta)['ppsspp_internal_resolution'],
        '960x544');
    expect(
        CoreOptionsRepository.effective('psp', const {}, pcQuality: GraphicsQuality.maxima)['ppsspp_internal_resolution'],
        '1440x816');
    // Lo elegido a mano en Consolas > PSP manda.
    expect(
        CoreOptionsRepository.effective('psp', const {'ppsspp_internal_resolution': '480x272'},
            pcQuality: GraphicsQuality.maxima)['ppsspp_internal_resolution'],
        '480x272');
    expect(CoreOptionsRepository.effective('psx', const {}, pcQuality: GraphicsQuality.alta)['pcsx_rearmed_neon_enhancement_enable'],
        'enabled');
    expect(CoreOptionsRepository.effective('psx', const {}, pcQuality: GraphicsQuality.original), isNot(contains('pcsx_rearmed_neon_enhancement_enable')));
    expect(AppSettings.fromMap(const AppSettings(pcQuality: GraphicsQuality.maxima).toMap()).pcQuality, GraphicsQuality.maxima);
  });
}
