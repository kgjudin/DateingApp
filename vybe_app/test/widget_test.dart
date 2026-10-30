import 'package:flutter_test/flutter_test.dart';
import 'package:vybe_app/core/constants/app_constants.dart';
import 'package:vybe_app/core/theme/app_colors.dart';

void main() {
  test('VYBE Constants and Design Tokens Test', () {
    expect(AppConstants.appName, 'VYBE');
    expect(AppConstants.appTagline, 'Voice-First Social Discovery');
    expect(AppColors.primaryBackground.value, 0xFF0B0B14);
    expect(AppColors.primaryAccent.value, 0xFFA855F7);
    expect(AppColors.secondaryAccent.value, 0xFFEC4899);
    expect(AppColors.online.value, 0xFF22C55E);
  });
}
