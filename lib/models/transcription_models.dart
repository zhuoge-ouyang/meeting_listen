import 'package:hive/hive.dart';

part 'transcription_models.g.dart';

@HiveType(typeId: 1)
class LanguageInfo extends HiveObject {
  @HiveField(0)
  String code;
  @HiveField(1)
  String name;
  @HiveField(2)
  String native;
  @HiveField(3)
  String script;
  @HiveField(4)
  double? confidence;

  LanguageInfo({
    required this.code,
    required this.name,
    required this.native,
    required this.script,
    this.confidence,
  });

  factory LanguageInfo.fromJson(Map<String, dynamic> json) {
    return LanguageInfo(
      code: json['code'] ?? 'en',
      name: json['name'] ?? 'English',
      native: json['native'] ?? 'English',
      script: json['script'] ?? 'latin',
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'native': native,
      'script': script,
      'confidence': confidence,
    };
  }

  // Helper methods for display
  String get displayName => '$native ($name)';

  bool get isTraditionalChinese => script == 'traditional';
  bool get isSimplifiedChinese => script == 'simplified';
  bool get isChinese => code.startsWith('zh') || script.contains('chinese');
  bool get isCantonese => code == 'zh-TW' || code == 'yue';
  bool get isMandarin => code == 'zh-CN';
}

@HiveType(typeId: 0)
class TranscriptionResult extends HiveObject {
  @HiveField(0)
  String sessionId;
  @HiveField(1)
  String transcriptionId;
  @HiveField(2)
  String transcription;
  @HiveField(3)
  String summary;
  @HiveField(4)
  List<String> actionItems;
  @HiveField(5)
  List<String> keyPoints;
  @HiveField(6)
  String meetingType;
  @HiveField(7)
  String meetingTitle;
  @HiveField(8)
  double durationMinutes;
  @HiveField(9)
  int wordCount;
  @HiveField(10)
  String createdAt;
  @HiveField(11)
  String? language; // Original language parameter for backwards compatibility
  @HiveField(12)
  LanguageInfo? detectedLanguage; // New enhanced language info
  @HiveField(13)
  List<Map<String, dynamic>> transcriptSegments;
  @HiveField(14)
  List<Map<String, dynamic>> structuredActionItems;
  @HiveField(15)
  List<String> participants;
  @HiveField(16)
  String? meetingTime;
  @HiveField(17)
  List<String> completedActionItemKeys;
  @HiveField(18)
  String summaryTemplateText;
  @HiveField(19)
  String summaryTemplateAnalysis;
  @HiveField(20)
  String summaryModule;

  TranscriptionResult({
    required this.sessionId,
    required this.transcriptionId,
    required this.transcription,
    required this.summary,
    required this.actionItems,
    required this.keyPoints,
    required this.meetingType,
    required this.meetingTitle,
    required this.durationMinutes,
    required this.wordCount,
    required this.createdAt,
    this.language,
    this.detectedLanguage,
    List<Map<String, dynamic>>? transcriptSegments,
    List<Map<String, dynamic>>? structuredActionItems,
    List<String>? participants,
    this.meetingTime,
    List<String>? completedActionItemKeys,
    this.summaryTemplateText = '',
    this.summaryTemplateAnalysis = '',
    this.summaryModule = 'default',
  })  : transcriptSegments = transcriptSegments ?? const [],
        structuredActionItems = structuredActionItems ?? const [],
        participants = participants ?? const [],
        completedActionItemKeys = completedActionItemKeys ?? const [];

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    return TranscriptionResult(
      sessionId: json['session_id'] ?? '',
      transcriptionId: json['transcription_id'] ?? '',
      transcription: json['transcription'] ?? '',
      summary: json['summary'] ?? '',
      actionItems: json['action_items'] != null
          ? (json['action_items'] as List)
              .map((item) {
                if (item is Map) return '${item['text'] ?? item['task'] ?? ''}';
                return '$item';
              })
              .where((item) => item.trim().isNotEmpty)
              .toList()
          : <String>[],
      keyPoints: json['key_points'] != null
          ? List<String>.from(json['key_points'])
          : <String>[],
      meetingType: json['meeting_type'] ?? '',
      meetingTitle: json['meeting_title'] ?? '',
      durationMinutes: (json['duration_minutes'] as num?)?.toDouble() ?? 0.0,
      wordCount: json['word_count'] ?? 0,
      createdAt: json['created_at'] ?? DateTime.now().toIso8601String(),
      language: json['language'],
      detectedLanguage: json['detected_language'] != null
          ? LanguageInfo.fromJson(json['detected_language'])
          : null,
      transcriptSegments: _mapList(json['transcript_segments']),
      structuredActionItems: _mapList(json['structured_action_items']),
      participants: json['participants'] != null
          ? List<String>.from(json['participants'].map((item) => '$item'))
          : <String>[],
      meetingTime: json['meeting_time'],
      completedActionItemKeys: json['completed_action_item_keys'] != null
          ? List<String>.from(
              (json['completed_action_item_keys'] as List)
                  .map((item) => '$item'),
            )
          : <String>[],
      summaryTemplateText: '${json['summary_template_text'] ?? ''}',
      summaryTemplateAnalysis: '${json['summary_template_analysis'] ?? ''}',
      summaryModule: '${json['summary_module'] ?? 'default'}',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'transcription_id': transcriptionId,
      'transcription': transcription,
      'summary': summary,
      'action_items': actionItems,
      'key_points': keyPoints,
      'meeting_type': meetingType,
      'meeting_title': meetingTitle,
      'duration_minutes': durationMinutes,
      'word_count': wordCount,
      'created_at': createdAt,
      'language': language,
      'detected_language': detectedLanguage?.toJson(),
      'transcript_segments': transcriptSegments,
      'structured_action_items': structuredActionItems,
      'participants': participants,
      'meeting_time': meetingTime,
      'completed_action_item_keys': completedActionItemKeys,
      'summary_template_text': summaryTemplateText,
      'summary_template_analysis': summaryTemplateAnalysis,
      'summary_module': summaryModule,
    };
  }

  // Helper getters
  LanguageInfo get effectiveLanguage =>
      detectedLanguage ??
      LanguageInfo(
        code: language ?? 'en',
        name: 'English',
        native: 'English',
        script: 'latin',
      );

  String get languageDisplay => effectiveLanguage.displayName;
  bool get isMultiLanguage => detectedLanguage != null;

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class TranscriptSegmentView {
  final String speakerId;
  final int startMs;
  final int endMs;
  final String text;

  const TranscriptSegmentView({
    required this.speakerId,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  factory TranscriptSegmentView.fromMap(Map<String, dynamic> map) {
    return TranscriptSegmentView(
      speakerId: '${map['speaker_id'] ?? 'speaker_1'}',
      startMs: (map['start_ms'] as num?)?.toInt() ?? 0,
      endMs: (map['end_ms'] as num?)?.toInt() ?? 0,
      text: '${map['text'] ?? ''}',
    );
  }

  String get timeRange {
    String format(int ms) {
      final total = (ms / 1000).floor();
      final minutes = (total ~/ 60).toString().padLeft(2, '0');
      final seconds = (total % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }

    return '${format(startMs)}-${format(endMs)}';
  }
}

class ActionItemView {
  final String text;
  final String? owner;
  final String? due;
  final int speakerCount;
  final bool isImportant;
  final List<String> speakerIds;

  const ActionItemView({
    required this.text,
    required this.owner,
    required this.due,
    required this.speakerCount,
    required this.isImportant,
    required this.speakerIds,
  });

  factory ActionItemView.fromMap(Map<String, dynamic> map) {
    return ActionItemView(
      text: '${map['text'] ?? ''}',
      owner: map['owner']?.toString(),
      due: map['due']?.toString(),
      speakerCount: (map['speaker_count'] as num?)?.toInt() ??
          ((map['speaker_ids'] is List)
              ? (map['speaker_ids'] as List).length
              : 0),
      isImportant: map['is_important'] == true,
      speakerIds: map['speaker_ids'] is List
          ? List<String>.from(
              (map['speaker_ids'] as List).map((item) => '$item'))
          : const <String>[],
    );
  }
}

class TranslationTtsResult {
  final String translatedText;
  final String audioUrl;
  final String voice;
  final String language;
  final String status;

  const TranslationTtsResult({
    required this.translatedText,
    required this.audioUrl,
    required this.voice,
    required this.language,
    required this.status,
  });

  factory TranslationTtsResult.fromJson(Map<String, dynamic> json) {
    return TranslationTtsResult(
      translatedText: '${json['translated_text'] ?? ''}',
      audioUrl: '${json['audio_url'] ?? ''}',
      voice: '${json['voice'] ?? ''}',
      language: '${json['language'] ?? ''}',
      status: '${json['status'] ?? ''}',
    );
  }
}

class SummaryRegenerationResult {
  final String summary;
  final List<String> actionItems;
  final List<String> keyPoints;
  final String fullAnalysis;
  final List<Map<String, dynamic>> structuredActionItems;
  final List<String> participants;
  final String? meetingTime;

  const SummaryRegenerationResult({
    required this.summary,
    required this.actionItems,
    required this.keyPoints,
    required this.fullAnalysis,
    required this.structuredActionItems,
    required this.participants,
    required this.meetingTime,
  });

  factory SummaryRegenerationResult.fromJson(Map<String, dynamic> json) {
    return SummaryRegenerationResult(
      summary: '${json['summary'] ?? ''}',
      actionItems: json['action_items'] is List
          ? List<String>.from(
              (json['action_items'] as List).map((item) => '$item'))
          : const <String>[],
      keyPoints: json['key_points'] is List
          ? List<String>.from(
              (json['key_points'] as List).map((item) => '$item'))
          : const <String>[],
      fullAnalysis: '${json['full_analysis'] ?? ''}',
      structuredActionItems: TranscriptionResult._mapList(
        json['structured_action_items'],
      ),
      participants: json['participants'] is List
          ? List<String>.from(
              (json['participants'] as List).map((item) => '$item'))
          : const <String>[],
      meetingTime: json['meeting_time']?.toString(),
    );
  }
}
