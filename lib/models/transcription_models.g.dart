// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcription_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LanguageInfoAdapter extends TypeAdapter<LanguageInfo> {
  @override
  final int typeId = 1;

  @override
  LanguageInfo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LanguageInfo(
      code: fields[0] as String,
      name: fields[1] as String,
      native: fields[2] as String,
      script: fields[3] as String,
      confidence: fields[4] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, LanguageInfo obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.code)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.native)
      ..writeByte(3)
      ..write(obj.script)
      ..writeByte(4)
      ..write(obj.confidence);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanguageInfoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TranscriptionResultAdapter extends TypeAdapter<TranscriptionResult> {
  @override
  final int typeId = 0;

  @override
  TranscriptionResult read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TranscriptionResult(
      sessionId: fields[0] as String,
      transcriptionId: fields[1] as String,
      transcription: fields[2] as String,
      summary: fields[3] as String,
      actionItems: (fields[4] as List).cast<String>(),
      keyPoints: (fields[5] as List).cast<String>(),
      meetingType: fields[6] as String,
      meetingTitle: fields[7] as String,
      durationMinutes: fields[8] as double,
      wordCount: fields[9] as int,
      createdAt: fields[10] as String,
      language: fields[11] as String?,
      detectedLanguage: fields[12] as LanguageInfo?,
      transcriptSegments: ((fields[13] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      structuredActionItems: ((fields[14] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      participants: ((fields[15] as List?) ?? const []).cast<String>(),
      meetingTime: fields[16] as String?,
      completedActionItemKeys:
          ((fields[17] as List?) ?? const []).cast<String>(),
      summaryTemplateText: fields[18] as String? ?? '',
      summaryTemplateAnalysis: fields[19] as String? ?? '',
      summaryModule: fields[20] as String? ?? 'default',
    );
  }

  @override
  void write(BinaryWriter writer, TranscriptionResult obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.sessionId)
      ..writeByte(1)
      ..write(obj.transcriptionId)
      ..writeByte(2)
      ..write(obj.transcription)
      ..writeByte(3)
      ..write(obj.summary)
      ..writeByte(4)
      ..write(obj.actionItems)
      ..writeByte(5)
      ..write(obj.keyPoints)
      ..writeByte(6)
      ..write(obj.meetingType)
      ..writeByte(7)
      ..write(obj.meetingTitle)
      ..writeByte(8)
      ..write(obj.durationMinutes)
      ..writeByte(9)
      ..write(obj.wordCount)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.language)
      ..writeByte(12)
      ..write(obj.detectedLanguage)
      ..writeByte(13)
      ..write(obj.transcriptSegments)
      ..writeByte(14)
      ..write(obj.structuredActionItems)
      ..writeByte(15)
      ..write(obj.participants)
      ..writeByte(16)
      ..write(obj.meetingTime)
      ..writeByte(17)
      ..write(obj.completedActionItemKeys)
      ..writeByte(18)
      ..write(obj.summaryTemplateText)
      ..writeByte(19)
      ..write(obj.summaryTemplateAnalysis)
      ..writeByte(20)
      ..write(obj.summaryModule);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranscriptionResultAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
