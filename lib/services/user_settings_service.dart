import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../utils/constants.dart';

/// Compatibility shell for the imported RecordWise settings service.
///
/// RecordWise 二开后，AI/OSS/DashScope 密钥只允许放在后端环境变量中。
/// 移动端不再读取、保存或上传任何模型/语音 API Key。
class UserSettingsService extends ChangeNotifier {
  static const _boxName = 'user_settings';
  static const _apiBaseUrlKey = 'api_base_url';

  Box<dynamic>? _box;

  String get apiBaseUrl {
    final saved = savedApiBaseUrl;
    if (saved.isNotEmpty) {
      return saved;
    }
    return normalizeApiBaseUrl(AppConstants.defaultApiBaseUrl);
  }

  String get savedApiBaseUrl {
    final value = _box?.get(_apiBaseUrlKey);
    if (value is String) {
      return normalizeApiBaseUrl(value);
    }
    return '';
  }

  bool get hasApiBaseUrl => apiBaseUrl.isNotEmpty;

  String get apiBaseUrlSource {
    if (savedApiBaseUrl.isNotEmpty) {
      return '本机设置';
    }
    if (AppConstants.defaultApiBaseUrl.isNotEmpty) {
      return '构建默认值';
    }
    return '未配置';
  }

  String get modelEndpoint => '';
  String get modelApiKey => '';
  String get modelDeployment => '';
  bool get hasCustomModelCredentials => false;

  String get speechKey => '';
  String get speechRegion => '';
  String get speechEndpoint => '';
  bool get hasCustomSpeechCredentials => false;

  Future<void> initialize() async {
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Future<void> saveApiBaseUrl(String value) async {
    final normalized = normalizeApiBaseUrl(value);
    if (normalized.isEmpty) {
      await clearApiBaseUrl();
      return;
    }
    await _box?.put(_apiBaseUrlKey, normalized);
    notifyListeners();
  }

  Future<void> clearApiBaseUrl() async {
    await _box?.delete(_apiBaseUrlKey);
    notifyListeners();
  }

  static String normalizeApiBaseUrl(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) {
      return '';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    return normalized;
  }

  Future<void> saveModelCredentials({
    required String endpoint,
    required String apiKey,
    required String deployment,
  }) async {
    notifyListeners();
  }

  Future<void> clearModelCredentials() async {
    notifyListeners();
  }

  Future<void> saveSpeechCredentials({
    required String key,
    required String region,
    required String endpoint,
  }) async {
    notifyListeners();
  }

  Future<void> clearSpeechCredentials() async {
    notifyListeners();
  }
}
