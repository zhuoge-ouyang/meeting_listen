// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:recordwise/main.dart';
import 'package:recordwise/services/api_service.dart';
import 'package:recordwise/services/audio_service.dart';
import 'package:recordwise/services/storage_service.dart';
import 'package:recordwise/models/transcription_models.dart';

void main() {
  testWidgets('RecordWise app smoke test', (WidgetTester tester) async {
    // Initialize Hive for testing
    await Hive.initFlutter();
    
    // Register adapters only if not already registered
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(TranscriptionResultAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(LanguageInfoAdapter());
    }

    final storageService = StorageService();
    await storageService.initialize();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AudioService()),
          ChangeNotifierProvider(create: (_) => storageService),
          Provider(create: (_) => ApiService()),
        ],
        child: const RecordWiseApp(),
      ),
    );

    // Verify that the app starts with the home screen
    expect(find.text('RecordWise'), findsOneWidget);
    expect(find.text('暂无会议记录'), findsOneWidget);
  });
}
