import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;
import '../models/transcription_models.dart';
import '../utils/constants.dart';
import 'web_audio_handler.dart';

class ApiService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConstants.apiBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
  ));

  // ── Connectivity test ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> testConnection() async {
    try {
      final response = await _dio.get('/api/test');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ApiService: connection test failed — $e');
      rethrow;
    }
  }

  Future<TranslationTtsResult> translateTts({
    required String meetingId,
    required String text,
    required String targetLanguage,
    List<int> segmentIds = const [],
  }) async {
    try {
      final response = await _dio.post(
        '/api/meetings/$meetingId/translate-tts',
        data: {
          'text': text,
          'segment_ids': segmentIds,
          'target_language': targetLanguage,
        },
      );
      final result = TranslationTtsResult.fromJson(
        response.data as Map<String, dynamic>,
      );
      final audioUrl = result.audioUrl.startsWith('http')
          ? result.audioUrl
          : '${AppConstants.apiBaseUrl}${result.audioUrl}';
      return TranslationTtsResult(
        translatedText: result.translatedText,
        audioUrl: audioUrl,
        voice: result.voice,
        language: result.language,
        status: result.status,
      );
    } on DioException catch (e) {
      debugPrint(
          'ApiService: translate/TTS DioException — ${e.response?.data ?? e.message}');
      throw Exception(
          'Translation/TTS error: ${e.response?.data ?? e.message}');
    }
  }

  Future<void> saveSpeakerAliases({
    required String meetingId,
    required Map<String, String> speakerAliases,
  }) async {
    await _dio.post(
      '/api/meetings/$meetingId/speakers',
      data: {'speaker_aliases': speakerAliases},
    );
  }

  Future<void> updateMeetingTitle({
    required String meetingId,
    required String meetingTitle,
  }) async {
    await _dio.post(
      '/api/meetings/$meetingId/title',
      data: {'meeting_title': meetingTitle},
    );
  }

  Future<SummaryRegenerationResult> regenerateSummary({
    required TranscriptionResult result,
    required String module,
    String? templateText,
  }) async {
    try {
      final response = await _dio.post(
        '/api/meetings/${result.sessionId}/summary',
        data: {
          'meeting_title': result.meetingTitle,
          'transcription': result.transcription,
          'transcript_segments': result.transcriptSegments,
          'participants': result.participants,
          'meeting_time': result.meetingTime,
          'module': module,
          'template_text': templateText,
        },
        options: Options(receiveTimeout: const Duration(minutes: 3)),
      );
      return SummaryRegenerationResult.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      debugPrint(
          'ApiService: regenerate summary DioException — ${e.response?.data ?? e.message}');
      throw Exception(
          'Summary regeneration error: ${e.response?.data ?? e.message}');
    }
  }

  // ── Public transcription entry-points ────────────────────────────────────

  /// Transcribe a live recording (blob URL on web, [File] path on mobile).
  Future<TranscriptionResult> transcribe(
    dynamic file,
    String meetingType, {
    String language = 'zh',
  }) async {
    Uint8List audioBytes;
    String fileName;

    if (kIsWeb) {
      if (file is String && file.startsWith('blob:')) {
        final blobData = await WebAudioHandler.fetchBlobData(file);
        if (blobData != null && blobData.isNotEmpty) {
          audioBytes = blobData;
          fileName = 'web_recording.wav';
        } else {
          throw Exception(
            'Could not retrieve audio data from the browser. Please try again.',
          );
        }
      } else {
        throw Exception('Unexpected audio source on web: $file');
      }
    } else {
      final ioFile = file as File;
      if (!await ioFile.exists()) {
        throw Exception('Audio file not found: ${ioFile.path}');
      }
      audioBytes = await ioFile.readAsBytes();
      fileName = path.basename(ioFile.path);
    }

    return _postToBackend(
      audioBytes: audioBytes,
      fileName: fileName,
      meetingType: meetingType,
      language: language,
    );
  }

  /// Transcribe using pre-fetched raw audio bytes (web primary path).
  Future<TranscriptionResult> transcribeWithAudioData(
    Uint8List audioData,
    String meetingType, {
    String language = 'zh',
  }) async {
    return _postToBackend(
      audioBytes: audioData,
      fileName: 'web_recording.wav',
      meetingType: meetingType,
      language: language,
    );
  }

  /// Transcribe a user-uploaded audio file.
  Future<TranscriptionResult> transcribeUploadedFile(
    Uint8List audioData,
    String fileName,
    String meetingType, {
    String language = 'zh',
  }) async {
    final ext = _getFileExtension(fileName) ?? _detectAudioFormat(audioData);
    return _postToBackend(
      audioBytes: audioData,
      fileName: 'uploaded_audio.$ext',
      meetingType: meetingType,
      language: language,
      audioSubtype: ext,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Single POST helper shared by all three public methods.
  Future<TranscriptionResult> _postToBackend({
    required Uint8List audioBytes,
    required String fileName,
    required String meetingType,
    required String language,
    String audioSubtype = 'wav',
  }) async {
    try {
      final formData = FormData.fromMap({
        'audio_file': MultipartFile.fromBytes(
          audioBytes,
          filename: fileName,
          contentType: MediaType('audio', audioSubtype),
        ),
        'meeting_type': meetingType,
        'language': language,
        'generate_summary': 'true',
      });

      final response = await _dio.post(
        '/api/meetings',
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 5),
        ),
      );

      if (response.data is Map && response.data['success'] == false) {
        throw Exception(
            'API error: ${response.data['error'] ?? 'Unknown error'}');
      }

      return TranscriptionResult.fromJson(
          response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint('ApiService: DioException [${e.type}] — ${e.message}');
      debugPrint(
          'ApiService: status=${e.response?.statusCode}, body=${e.response?.data}');
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('ApiService: transcription failed — $e');
      rethrow;
    }
  }

  /// Extract file extension from [fileName], or null if absent.
  String? _getFileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return (dot != -1 && dot < fileName.length - 1)
        ? fileName.substring(dot + 1).toLowerCase()
        : null;
  }

  /// Infer audio container format from magic bytes.
  String _detectAudioFormat(Uint8List data) {
    if (data.length >= 4) {
      if (data[0] == 0x52 &&
          data[1] == 0x49 &&
          data[2] == 0x46 &&
          data[3] == 0x46) {
        return 'wav';
      }
      if (data[0] == 0xFF && (data[1] & 0xE0) == 0xE0) {
        return 'mp3';
      }
      if (data[0] == 0x4F &&
          data[1] == 0x67 &&
          data[2] == 0x67 &&
          data[3] == 0x53) {
        return 'ogg';
      }
      if (data.length >= 8 &&
          data[4] == 0x66 &&
          data[5] == 0x74 &&
          data[6] == 0x79 &&
          data[7] == 0x70) {
        return 'm4a';
      }
    }
    return 'wav';
  }
}
