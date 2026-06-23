import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/api_service.dart';
import '../services/log_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/toast_utils.dart';
import '../widgets/file_upload_widget.dart';
import 'results_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  bool _isProcessing = false;
  String _selectedLanguage = 'zh';
  String _selectedMeetingType = 'meeting';
  bool _hasInitialized = false;

  static const _meetingTypes = [
    {'value': 'meeting', 'label': '会议', 'icon': CupertinoIcons.group},
    {'value': 'interview', 'label': '访谈', 'icon': CupertinoIcons.person_2},
    {'value': 'lecture', 'label': '讲座', 'icon': CupertinoIcons.book},
    {'value': 'call', 'label': '通话', 'icon': CupertinoIcons.phone},
    {'value': 'chat', 'label': '聊天', 'icon': CupertinoIcons.chat_bubble_2},
    {'value': 'brainstorm', 'label': '头脑风暴', 'icon': CupertinoIcons.lightbulb},
  ];

  static const _languageOptions = <String, String>{
    'zh': '普通话',
    'yue': '粤语',
    'en': '英语',
    'ja': '日语',
    'fr': '法语',
    'auto': '自动',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialized) {
        final audio = context.read<AudioService>();
        if (audio.seconds > 0 || audio.filePath != null) {
          audio.resetRecording();
        }
        audio.onTimeLimitReached = (recordedPath) async {
          if (!mounted) return;
          AppToast.show(context,
              '录音已停止：达到 ${AppConstants.maxRecordingMinutes} 分钟上限，正在处理...');
          if (recordedPath != null) {
            setState(() => _isProcessing = true);
            await _processRecording(recordedPath);
          }
        };
        _hasInitialized = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('录音'),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Language Selection ─────────────────────────────────────
              _buildSectionTitle('语种'),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: _selectedLanguage,
                  onValueChanged: (value) {
                      LogService().info(LogSource.user, '选择语种: $value');
                      setState(() => _selectedLanguage = value!);
                  },
                  children: {
                    for (final entry in _languageOptions.entries)
                      entry.key: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Text(
                          entry.value,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  },
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _selectedLanguage == 'auto'
                      ? '自动识别适合不确定语种的录音。'
                      : '建议选择主要发言语种，转写和说话人分离会更稳定。',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Meeting Type Selection ─────────────────────────────────
              _buildSectionTitle('会议类型'),
              const SizedBox(height: 10),
              _buildMeetingTypeList(),

              const SizedBox(height: 28),

              // ── Live Recording ─────────────────────────────────────────
              _buildSectionTitle('现场录音'),
              const SizedBox(height: 16),
              _buildRecordingArea(audio),

              const SizedBox(height: 24),

              // ── File Upload (web only) ─────────────────────────────────
              if (kIsWeb)
                FileUploadWidget(
                  isProcessing: _isProcessing,
                  onFileSelected: (audioData, fileName) async {
                    setState(() => _isProcessing = true);
                    await _processUploadedFile(audioData, fileName);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section title ────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
        decoration: TextDecoration.none,
      ),
    );
  }

  // ── Meeting type list (iOS-style) ────────────────────────────────────────

  Widget _buildMeetingTypeList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: List.generate(_meetingTypes.length, (index) {
          final type = _meetingTypes[index];
          final value = type['value'] as String;
          final label = type['label'] as String;
          final icon = type['icon'] as IconData;
          final isSelected = _selectedMeetingType == value;
          final isLast = index == _meetingTypes.length - 1;

          return GestureDetector(
            onTap: () => setState(() => _selectedMeetingType = value),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(
                          color: AppColors.separator,
                          width: 0.5,
                        ),
                      ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.primaryBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.textDark,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      CupertinoIcons.checkmark_alt,
                      color: AppColors.primaryBlue,
                      size: 20,
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Recording area ───────────────────────────────────────────────────────

  Widget _buildRecordingArea(AudioService audio) {
    return Center(
      child: Column(
        children: [
          if (!audio.isRecording) ...[
            Text(
              '最长录音：${AppConstants.maxRecordingMinutes} 分钟',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textLight,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Timer display
          Text(
            audio.duration,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w200,
              fontFeatures: [FontFeature.tabularFigures()],
              color: AppColors.textDark,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 12),

          // Progress & remaining time
          if (audio.isRecording) ...[
            Text(
              '剩余：${audio.remainingTime}',
              style: TextStyle(
                fontSize: 14,
                color: audio.isNearTimeLimit
                    ? AppColors.errorRed
                    : AppColors.textLight,
                fontWeight: audio.isNearTimeLimit
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: LinearProgressIndicator(
                value: audio.seconds / AudioService.maxRecordingSeconds,
                backgroundColor: AppColors.separator,
                valueColor: AlwaysStoppedAnimation<Color>(
                  audio.isNearTimeLimit
                      ? AppColors.errorRed
                      : AppColors.primaryBlue,
                ),
                minHeight: 3,
              ),
            ),
            if (audio.isNearTimeLimit) ...[
              const SizedBox(height: 10),
              Text(
                '${audio.remainingTime} 后自动停止',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.errorRed,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],

          const SizedBox(height: 28),

          // Recording button or processing indicator
          if (_isProcessing)
            const Column(
              children: [
                CupertinoActivityIndicator(radius: 16),
                SizedBox(height: 16),
                Text(
                  '正在处理录音...',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            )
          else
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                try {
                  if (audio.isRecording) {
                    LogService().info(LogSource.user, '点击录音按钮');
                    final path = await audio.stopRecording();
                    if (path != null && mounted) {
                      setState(() => _isProcessing = true);
                      await _processRecording(path);
                    }
                  } else {
                    LogService().info(LogSource.user, '点击录音按钮');
                    await audio.startRecording();
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  setState(() => _isProcessing = false);
                  AppToast.show(context, '录音失败：$e', isError: true);
                }
              },
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: audio.isRecording
                      ? AppColors.errorRed
                      : AppColors.primaryBlue,
                ),
                child: Icon(
                  audio.isRecording
                      ? CupertinoIcons.stop_fill
                      : CupertinoIcons.mic_fill,
                  color: CupertinoColors.white,
                  size: 32,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Process live recording ───────────────────────────────────────────────

  Future<void> _processRecording(String path) async {
    final apiService = context.read<ApiService>();
    final storageService = context.read<StorageService>();
    final navigator = Navigator.of(context);

    try {
      dynamic fileToTranscribe;
      Uint8List? audioData;

      if (kIsWeb) {
        final audio = context.read<AudioService>();
        audioData = audio.audioData;
        if (audioData == null) fileToTranscribe = path;
      } else {
        fileToTranscribe = File(path);
      }

      final res = audioData != null
          ? await apiService.transcribeWithAudioData(
              audioData, _selectedMeetingType,
              language: _selectedLanguage,
            )
          : await apiService.transcribe(
              fileToTranscribe, _selectedMeetingType,
              language: _selectedLanguage,
            );

      await storageService.save(res);

      if (mounted) {
        context.read<AudioService>().resetRecording();
        setState(() => _isProcessing = false);
        LogService().info(LogSource.user, '录音处理完成，导航到结果页');
        navigator.push(
            CupertinoPageRoute(builder: (_) => ResultsScreen(result: res)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        context.read<AudioService>().resetRecording();
        AppToast.show(context, '录音处理失败：$e', isError: true);
      }
    }
  }

  // ── Process uploaded file ────────────────────────────────────────────────

  Future<void> _processUploadedFile(
      Uint8List audioData, String fileName) async {
    final apiService = context.read<ApiService>();
    final storageService = context.read<StorageService>();
    final navigator = Navigator.of(context);

    try {
      final res = await apiService.transcribeUploadedFile(
        audioData, fileName, _selectedMeetingType,
        language: _selectedLanguage,
      );
      await storageService.save(res);

      if (mounted) {
        context.read<AudioService>().resetRecording();
        setState(() => _isProcessing = false);
        navigator.push(
            CupertinoPageRoute(builder: (_) => ResultsScreen(result: res)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        context.read<AudioService>().resetRecording();
        AppToast.show(context, '上传处理失败：$e', isError: true);
      }
    }
  }
}
