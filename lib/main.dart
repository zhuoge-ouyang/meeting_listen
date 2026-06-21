import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/api_service.dart';
import 'services/audio_service.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';
import 'screens/launch_screen.dart';
import 'screens/recording_screen.dart';
import 'screens/results_history_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/constants.dart';
import 'models/transcription_models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => storageService),
        Provider(create: (_) => ApiService()),
      ],
      child: const RecordWiseApp(),
    ),
  );
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
          surface: AppColors.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
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

class RecordWiseHomePage extends StatefulWidget {
  const RecordWiseHomePage({super.key});

  @override
  State<RecordWiseHomePage> createState() => _RecordWiseHomePageState();
}

class _RecordWiseHomePageState extends State<RecordWiseHomePage> {
  int _selectedIndex = 0;

  final _screens = [
    const HomeScreen(),
    const RecordingScreen(),
    const ResultsHistoryScreen(),
    const SettingsScreen()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: AppColors.primaryBlue,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.mic), label: '录音'),
          BottomNavigationBarItem(icon: Icon(Icons.article), label: '记录'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
