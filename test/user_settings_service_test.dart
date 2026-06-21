import 'package:flutter_test/flutter_test.dart';
import 'package:recordwise/services/user_settings_service.dart';

void main() {
  group('UserSettingsService.normalizeApiBaseUrl', () {
    test('adds http scheme and removes trailing slashes', () {
      expect(
        UserSettingsService.normalizeApiBaseUrl(' 192.168.1.33:8000/// '),
        'http://192.168.1.33:8000',
      );
    });

    test('keeps existing https scheme', () {
      expect(
        UserSettingsService.normalizeApiBaseUrl('https://api.example.com/'),
        'https://api.example.com',
      );
    });

    test('returns empty string for blank input', () {
      expect(UserSettingsService.normalizeApiBaseUrl('   '), '');
    });
  });
}
