import 'package:flutter/foundation.dart';

/// Compatibility shell for the imported RecordWise settings service.
///
/// RecordWise 二开后，AI/OSS/DashScope 密钥只允许放在后端环境变量中。
/// 移动端不再读取、保存或上传任何模型/语音 API Key。
class UserSettingsService extends ChangeNotifier {
  String get modelEndpoint => '';
  String get modelApiKey => '';
  String get modelDeployment => '';
  bool get hasCustomModelCredentials => false;

  String get speechKey => '';
  String get speechRegion => '';
  String get speechEndpoint => '';
  bool get hasCustomSpeechCredentials => false;

  Future<void> initialize() async {}

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
