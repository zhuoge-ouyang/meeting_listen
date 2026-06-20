import 'package:flutter/material.dart';

class AppColors {
  static const primaryBlue = Color(0xFF355C4A);
  static const textDark = Color(0xFF2E2A25);
  static const textLight = Color(0xFF716A60);
  static const successGreen = Color(0xFF3F7A52);
  static const errorRed = Color(0xFFB34A3F);
  static const paper = Color(0xFFF6F4EF);
  static const surface = Color(0xFFFCFBF8);
}

class AppConstants {
  static const appName = 'RecordWise';

  // Backend API base URL.
  // Override at build/run time without editing source, e.g.:
  //   flutter run --dart-define=API_BASE_URL=https://api.example.com
  //   flutter build web --dart-define=API_BASE_URL=https://api.example.com
  // Falls back to localhost:8000 for local development.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const sampleRate = 16000;
  // The in-app recorder keeps long meetings manageable before the backend
  // uploads audio for DashScope ASR.
  static const maxRecordingMinutes = 120;
  // Backend upload guard; large audio is handled server-side through OSS URLs.
  static const maxUploadFileSizeMb = 500;

  // Speech-to-text is performed by Aliyun DashScope Fun-ASR/Paraformer.
  // The summary stage uses Qwen by default and translation uses Qwen-MT/TTS.
  static const chatEngine = 'qwen-plus';

  // Qwen text model presets used by backend deployments.
  static const chatModelPresets = [
    ('qwen-plus', 'Qwen Plus', 'Recommended minutes model'),
    ('qwen-max', 'Qwen Max', 'Higher quality summary'),
    ('qwen-turbo', 'Qwen Turbo', 'Lower latency'),
  ];
}
