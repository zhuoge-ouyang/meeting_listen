import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../utils/constants.dart';
import 'log_service.dart';
import 'web_audio_handler.dart';

class AudioService extends ChangeNotifier {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _filePath;
  Uint8List? _audioData; // For web audio data
  Timer? _timer;
  int _seconds = 0;

  // Derived hard limit, kept in sync with [AppConstants.maxRecordingMinutes].
  // The backend processes long recordings through DashScope ASR with diarization.
  static const int maxRecordingSeconds =
      AppConstants.maxRecordingMinutes * 60;

  /// Fired after the time limit is reached AND `stopRecording()` has finished.
  /// [recordedPath] is the file path / blob URL returned by the recorder, or
  /// null if the recorder produced nothing usable. The audio bytes (web) are
  /// available via [audioData] at the time this fires.
  void Function(String? recordedPath)? onTimeLimitReached;

  bool get isRecording => _isRecording;
  String get duration => '${(_seconds~/60).toString().padLeft(2,'0')}:${(_seconds%60).toString().padLeft(2,'0')}';
  String? get filePath => _filePath;
  Uint8List? get audioData => _audioData; // Getter for web audio data
  int get seconds => _seconds; // Public getter for seconds
  bool get isNearTimeLimit => _seconds >= (maxRecordingSeconds - 300); // 5 minutes warning
  bool get hasReachedTimeLimit => _seconds >= maxRecordingSeconds;
  int get remainingSeconds => maxRecordingSeconds - _seconds;
  String get remainingTime {
    final remaining = remainingSeconds;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '${minutes.toString().padLeft(2,'0')}:${seconds.toString().padLeft(2,'0')}';
  }

  Future<bool> _hasPermission() async {
    if (await _audioRecorder.hasPermission()) {
      return true;
    }
    return false;
  }

  Future startRecording() async {
    try {
      if (!await _hasPermission()) {
        throw Exception('Microphone permission denied');
      }

      // Handle different platforms
      if (kIsWeb) {
        // For web, we still need to provide a path even though it records to memory
        _filePath = 'web_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
        debugPrint('🌐 Starting web recording to: $_filePath');
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            bitRate: 128000,
          ),
          path: _filePath!,
        );
        debugPrint('✅ Web recording started successfully');
      } else {
        // For mobile platforms, record to file
        final dir = await getApplicationDocumentsDirectory();
        _filePath = '${dir.path}/recordwise_${DateTime.now().millisecondsSinceEpoch}.wav';
        debugPrint('📱 Starting mobile recording to: $_filePath');
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            bitRate: 128000,
          ),
          path: _filePath!,
        );
        debugPrint('✅ Mobile recording started successfully');
      }
      
      _isRecording = true;
      _seconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _seconds++;
        notifyListeners();

        // Auto-stop when the time limit is reached
        if (_seconds >= maxRecordingSeconds) {
          _timer?.cancel();
          _autoStop();
        }
      });
      notifyListeners();
      debugPrint('🎤 Recording is now active');
      LogService().info(LogSource.user, '开始录音');
    } catch (e) {
      debugPrint('❌ Error starting recording: $e');
      LogService().error(LogSource.error, '录音启动失败: $e');
      rethrow;
    }
  }

  Future<String?> stopRecording() async {
    try {
      debugPrint('=== Stopping Audio Recording ===');
      if (!_isRecording) {
        debugPrint('⚠️ Recording is not active, cannot stop');
        return null;
      }

      final path = await _audioRecorder.stop();
      debugPrint('📁 Recorded audio path: $path');
      
      _isRecording = false;
      _timer?.cancel();
      // Note: Don't reset _seconds here, keep showing duration until reset is called
      notifyListeners();

      if (path != null) {
        if (kIsWeb) {
          // On web, the 'path' is actually a blob URL
          debugPrint('🌐 Web recording completed with blob URL: $path');
          LogService().info(LogSource.user, '停止录音，文件: $path');
          
          // Immediately fetch the audio data while blob URL is still valid
          debugPrint('🎯 Fetching audio data from blob URL immediately...');
          try {
            final audioBytes = await WebAudioHandler.fetchBlobData(path);
            if (audioBytes != null && audioBytes.isNotEmpty) {
              _audioData = audioBytes;
              debugPrint('✅ Successfully captured ${audioBytes.length} bytes of real audio data');
            } else {
              debugPrint('⚠️ Failed to fetch audio data from blob URL');
              _audioData = null;
            }
          } catch (e) {
            debugPrint('❌ Error fetching blob audio data: $e');
            _audioData = null;
          }
          
          // Store the path for compatibility but audio data is more important
          _filePath = path;
          debugPrint('✅ Web recording processing complete');
          return path;
        } else {
          // On mobile platforms, check the file
          final file = File(path);
          if (await file.exists()) {
            final size = await file.length();
            debugPrint('📱 Mobile recording: File size: $size bytes');
            if (size > 0) {
              debugPrint('✅ Mobile recording successful');
              LogService().info(LogSource.user, '停止录音，文件: $path');
              return path;
            } else {
              debugPrint('❌ Mobile recording: File is empty');
              return null;
            }
          } else {
            debugPrint('❌ Mobile recording: File does not exist');
            return null;
          }
        }
      } else {
        debugPrint('❌ No audio path returned from recording');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error stopping recording: $e');
      LogService().error(LogSource.error, '停止录音失败: $e');
      _isRecording = false;
      _timer?.cancel();
      notifyListeners();
      return null;
    }
  }

  /// Called by the timer when the recording limit is reached.
  Future<void> _autoStop() async {
    final path = await stopRecording();
    onTimeLimitReached?.call(path);
  }

  /// Reset the recording state and timer for next recording
  void resetRecording() {
    debugPrint('🔄 Resetting recording state for next recording');
    _seconds = 0;
    _filePath = null;
    _audioData = null;
    _isRecording = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _timer?.cancel();
    super.dispose();
  }
}
