import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/api_service.dart';
import 'services/audio_service.dart';
import 'services/log_service.dart';
import 'services/storage_service.dart';
import 'services/user_settings_service.dart';
import 'screens/home_screen.dart';
import 'screens/launch_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/results_history_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/constants.dart';
import 'models/transcription_models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Hive
  await Hive.initFlutter();

  // Register each adapter individually. Hive throws if you re-register the
  // same typeId, so guard each one with its own check (typeIds match the
  // values defined in transcription_models.g.dart).
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(TranscriptionResultAdapter());
  }
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(LanguageInfoAdapter());
  }

  final storageService = StorageService();
  await storageService.initialize();
  final userSettingsService = UserSettingsService();
  await userSettingsService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LogService()),
        ChangeNotifierProvider(create: (_) => AudioService()),
        ChangeNotifierProvider.value(value: storageService),
        ChangeNotifierProvider.value(value: userSettingsService),
        Provider(
            create: (context) =>
                ApiService(context.read<UserSettingsService>())),
      ],
      child: const RecordWiseApp(),
    ),
  );

  LogService().info(LogSource.system, 'RecordWise \u542f\u52a8');
}

class RecordWiseApp extends StatelessWidget {
  const RecordWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: AppColors.primaryBlue,
        scaffoldBackgroundColor: AppColors.paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryBlue,
          primary: AppColors.primaryBlue,
          surface: AppColors.paper,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.paper,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          centerTitle: true,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const LaunchGate(),
    );
  }
}

class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key});

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  bool _showApp = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _showApp = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: _showApp
          ? const RecordWiseHomePage(key: ValueKey('home'))
          : const LaunchScreen(key: ValueKey('launch')),
    );
  }
}

class RecordWiseHomePage extends StatelessWidget {
  const RecordWiseHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        activeColor: AppColors.primaryBlue,
        inactiveColor: AppColors.textLight,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.home),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.mic),
            label: '录音',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.doc_text),
            label: '记录',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: '设置',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) {
            switch (index) {
              case 0:
                return const HomeScreen();
              case 1:
                return const RecordingScreen();
              case 2:
                return const ResultsHistoryScreen();
              case 3:
                return const SettingsScreen();
              default:
                return const HomeScreen();
            }
          },
        );
      },
    );
  }
}
