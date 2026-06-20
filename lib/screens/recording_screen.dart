import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../widgets/file_upload_widget.dart';
import 'results_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  bool _isProcessing = false;
  String _selectedLanguage   = 'zh';
  String _selectedMeetingType = 'meeting';
  bool _hasInitialized = false;

  static const _meetingTypes = [
    {'value': 'meeting',    'label': '会议',    'icon': Icons.groups},
    {'value': 'interview',  'label': '访谈',    'icon': Icons.person_search},
    {'value': 'lecture',    'label': '讲座',    'icon': Icons.school},
    {'value': 'call',       'label': '通话',    'icon': Icons.phone},
    {'value': 'chat',       'label': '聊天',    'icon': Icons.chat},
    {'value': 'brainstorm', 'label': '头脑风暴', 'icon': Icons.lightbulb},
  ];

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '录音已停止：达到 ${AppConstants.maxRecordingMinutes} 分钟上限，正在处理...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
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

    return Scaffold(
      appBar: AppBar(title: const Text('录音')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/textures/audio_wave_texture.png'),
            fit: BoxFit.cover,
            opacity: 0.06,
          ),
        ),
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Language Selection ─────────────────────────────────────
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.language, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('语种',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildLanguageButton('zh', '普通话', Icons.translate),
                          _buildLanguageButton('yue', '粤语', Icons.translate),
                          _buildLanguageButton('en', '英语', Icons.translate),
                          _buildLanguageButton('ja', '日语', Icons.translate),
                          _buildLanguageButton('fr', '法语', Icons.translate),
                          _buildLanguageButton('auto', '自动', Icons.auto_awesome),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _selectedLanguage == 'auto'
                              ? '自动识别适合不确定语种的录音。'
                              : '建议选择主要发言语种，转写和说话人分离会更稳定。',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Meeting Type Selection ─────────────────────────────────
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.category, color: Colors.green),
                          SizedBox(width: 8),
                          Text('会议类型',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedMeetingType,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: _meetingTypes.map((t) {
                          return DropdownMenuItem<String>(
                            value: t['value'] as String,
                            child: Row(
                              children: [
                                Icon(t['icon'] as IconData, size: 18, color: Colors.green[700]),
                                const SizedBox(width: 8),
                                Text(t['label'] as String),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setState(() => _selectedMeetingType = v ?? 'meeting'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Live Recording ─────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.mic, color: Colors.red),
                          SizedBox(width: 8),
                          Text('现场录音',
                              style:
                                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (!audio.isRecording) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '最长录音：${AppConstants.maxRecordingMinutes} 分钟',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Column(
                        children: [
                          Text(audio.duration,
                              style: const TextStyle(fontSize: 32)),
                          const SizedBox(height: 8),
                          if (audio.isRecording) ...[
                            Text(
                              '剩余：${audio.remainingTime}',
                              style: TextStyle(
                                fontSize: 14,
                                color: audio.isNearTimeLimit
                                    ? Colors.orange
                                    : Colors.grey[600],
                                fontWeight: audio.isNearTimeLimit
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: audio.seconds / AudioService.maxRecordingSeconds,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                audio.isNearTimeLimit ? Colors.orange : Colors.blue,
                              ),
                            ),
                          ],
                          if (audio.isNearTimeLimit && audio.isRecording) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning,
                                      color: Colors.orange[700], size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${audio.remainingTime} 后自动停止',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange[700],
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_isProcessing)
                        const Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在处理录音...'),
                          ],
                        )
                      else
                        FloatingActionButton(
                          backgroundColor:
                              audio.isRecording ? Colors.red : Colors.blue,
                          child:
                              Icon(audio.isRecording ? Icons.stop : Icons.mic),
                          onPressed: () async {
                            try {
                              if (audio.isRecording) {
                                final path = await audio.stopRecording();
                                if (path != null && mounted) {
                                  setState(() => _isProcessing = true);
                                  await _processRecording(path);
                                }
                              } else {
                                await audio.startRecording();
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              setState(() => _isProcessing = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('录音失败：$e')),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

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
      ),
    );
  }

  // ── Process live recording ───────────────────────────────────────────────

  Future<void> _processRecording(String path) async {
    final apiService      = context.read<ApiService>();
    final storageService  = context.read<StorageService>();
    final navigator       = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

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
        navigator.push(MaterialPageRoute(builder: (_) => ResultsScreen(result: res)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        context.read<AudioService>().resetRecording();
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('录音处理失败：$e')));
      }
    }
  }

  // ── Process uploaded file ────────────────────────────────────────────────

  Future<void> _processUploadedFile(Uint8List audioData, String fileName) async {
    final apiService      = context.read<ApiService>();
    final storageService  = context.read<StorageService>();
    final navigator       = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final res = await apiService.transcribeUploadedFile(
        audioData, fileName, _selectedMeetingType,
        language: _selectedLanguage,
      );
      await storageService.save(res);

      if (mounted) {
        context.read<AudioService>().resetRecording();
        setState(() => _isProcessing = false);
        navigator.push(MaterialPageRoute(builder: (_) => ResultsScreen(result: res)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        context.read<AudioService>().resetRecording();
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('上传处理失败：$e')));
      }
    }
  }

  // ── Language button builder ──────────────────────────────────────────────

  Widget _buildLanguageButton(String code, String label, IconData icon) {
    final selected = _selectedLanguage == code;
    return SizedBox(
      width: 104,
      child: ElevatedButton.icon(
          onPressed: () => setState(() => _selectedLanguage = code),
          icon: Icon(icon, size: 16, color: selected ? Colors.white : Colors.blue),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : Colors.blue,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: selected ? Colors.blue : Colors.white,
            foregroundColor: selected ? Colors.white : Colors.blue,
            side: BorderSide(color: Colors.blue, width: selected ? 2 : 1),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            minimumSize: const Size(0, 36),
          ),
        ),
    );
  }
}
