import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/transcription_models.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.result});
  final TranscriptionResult result;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, String> _speakerAliases = {};
  TranslationTtsResult? _translation;
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateTime = RecordWiseDateUtils.parseDateTime(widget.result.createdAt);
    final formattedDate = RecordWiseDateUtils.formatDateTime(dateTime);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.result.meetingTitle.isNotEmpty
            ? widget.result.meetingTitle
            : '会议记录'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_all),
            onPressed: () => _copyAllToClipboard(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '原录音文本'),
            Tab(text: '总结文本'),
            Tab(text: '待办事项'),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFF6F4EF),
          image: DecorationImage(
            image: AssetImage('assets/textures/app_bg_texture.png'),
            repeat: ImageRepeat.repeat,
            opacity: 0.05,
          ),
        ),
        child: Column(
          children: [
            _Header(result: widget.result, formattedDate: formattedDate),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _TranscriptTab(
                    segments: _segments,
                    speakerAliases: _speakerAliases,
                    onRenameSpeaker: _renameSpeaker,
                    onTranslate: _translateText,
                    translation: _translation,
                    isTranslating: _isTranslating,
                    onPlayTranslation: _playTranslation,
                  ),
                  _SummaryTab(summary: widget.result.summary),
                  _TasksTab(items: _actionItems),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TranscriptSegmentView> get _segments {
    if (widget.result.transcriptSegments.isNotEmpty) {
      return widget.result.transcriptSegments
          .map(TranscriptSegmentView.fromMap)
          .where((segment) => segment.text.trim().isNotEmpty)
          .toList();
    }
    return widget.result.transcription
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((entry) => TranscriptSegmentView(
              speakerId: 'speaker_${entry.key + 1}',
              startMs: entry.key * 30000,
              endMs: (entry.key + 1) * 30000,
              text: entry.value,
            ))
        .toList();
  }

  List<ActionItemView> get _actionItems {
    if (widget.result.structuredActionItems.isNotEmpty) {
      return widget.result.structuredActionItems
          .map(ActionItemView.fromMap)
          .where((item) => item.text.trim().isNotEmpty)
          .toList();
    }
    return widget.result.actionItems
        .map((item) => ActionItemView(
              text: item,
              owner: null,
              due: null,
              speakerCount: 0,
              isImportant: false,
              speakerIds: const [],
            ))
        .toList();
  }

  Future<void> _renameSpeaker(String speakerId) async {
    final apiService = context.read<ApiService>();
    final controller = TextEditingController(
      text: _speakerAliases[speakerId] ?? speakerId,
    );
    final alias = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改说话人名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '显示名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (alias == null || alias.isEmpty) return;
    setState(() => _speakerAliases[speakerId] = alias);
    try {
      await apiService.saveSpeakerAliases(
            meetingId: widget.result.sessionId,
            speakerAliases: _speakerAliases,
          );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('说话人名称已本地更新，后端同步失败')),
      );
    }
  }

  Future<void> _translateText(String text, String targetLanguage) async {
    setState(() {
      _isTranslating = true;
      _translation = null;
    });
    try {
      final result = await context.read<ApiService>().translateTts(
            meetingId: widget.result.sessionId,
            text: text,
            targetLanguage: targetLanguage,
          );
      setState(() => _translation = result);
      await _playTranslation();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  Future<void> _playTranslation() async {
    final audioUrl = _translation?.audioUrl;
    if (audioUrl == null || audioUrl.isEmpty) return;
    await _audioPlayer.stop();
    await _audioPlayer.play(UrlSource(audioUrl));
  }

  void _copyAllToClipboard(BuildContext context) {
    final buffer = StringBuffer()
      ..writeln(widget.result.meetingTitle)
      ..writeln()
      ..writeln('总结文本')
      ..writeln(widget.result.summary)
      ..writeln()
      ..writeln('待办事项');
    for (final item in _actionItems) {
      buffer.writeln('- ${item.isImportant ? "【重要】" : ""}${item.text}');
    }
    buffer
      ..writeln()
      ..writeln('原录音文本');
    for (final segment in _segments) {
      final speaker = _speakerAliases[segment.speakerId] ?? segment.speakerId;
      buffer.writeln('[${segment.timeRange}] $speaker: ${segment.text}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制完整会议记录')),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.result, required this.formattedDate});
  final TranscriptionResult result;
  final String formattedDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFCFBF8),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E0D7))),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Meta(icon: Icons.schedule, label: formattedDate),
          _Meta(
            icon: Icons.timer_outlined,
            label: '${result.durationMinutes.toStringAsFixed(1)} min',
          ),
          _Meta(icon: Icons.language, label: result.languageDisplay),
          if (result.participants.isNotEmpty)
            _Meta(icon: Icons.groups_2_outlined, label: '${result.participants.length} 人'),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6E675F)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF3C3935))),
      ],
    );
  }
}

class _TranscriptTab extends StatelessWidget {
  const _TranscriptTab({
    required this.segments,
    required this.speakerAliases,
    required this.onRenameSpeaker,
    required this.onTranslate,
    required this.translation,
    required this.isTranslating,
    required this.onPlayTranslation,
  });

  final List<TranscriptSegmentView> segments;
  final Map<String, String> speakerAliases;
  final ValueChanged<String> onRenameSpeaker;
  final void Function(String text, String targetLanguage) onTranslate;
  final TranslationTtsResult? translation;
  final bool isTranslating;
  final VoidCallback onPlayTranslation;

  static const _languages = [
    ('english', '英语'),
    ('japanese', '日语'),
    ('cantonese', '粤语'),
    ('mandarin', '普通话'),
    ('french', '法语'),
  ];

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return const _EmptyState(message: '暂无原录音文本');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final segment in segments)
          _TranscriptSegmentTile(
            segment: segment,
            speakerName: speakerAliases[segment.speakerId] ?? segment.speakerId,
            onRenameSpeaker: () => onRenameSpeaker(segment.speakerId),
            onTranslate: (target) => onTranslate(segment.text, target),
            languages: _languages,
          ),
        if (isTranslating)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (translation != null)
          _TranslationPanel(
            translation: translation!,
            onPlay: onPlayTranslation,
          ),
      ],
    );
  }
}

class _TranscriptSegmentTile extends StatelessWidget {
  const _TranscriptSegmentTile({
    required this.segment,
    required this.speakerName,
    required this.onRenameSpeaker,
    required this.onTranslate,
    required this.languages,
  });

  final TranscriptSegmentView segment;
  final String speakerName;
  final VoidCallback onRenameSpeaker;
  final ValueChanged<String> onTranslate;
  final List<(String, String)> languages;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4DED3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                segment.timeRange,
                style: const TextStyle(fontSize: 12, color: Color(0xFF7B746B)),
              ),
              const SizedBox(width: 8),
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(speakerName),
                avatar: const Icon(Icons.person_outline, size: 16),
                onPressed: onRenameSpeaker,
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: '翻译朗读',
                icon: const Icon(Icons.record_voice_over_outlined),
                onSelected: onTranslate,
                itemBuilder: (context) => [
                  for (final language in languages)
                    PopupMenuItem(value: language.$1, child: Text(language.$2)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            segment.text,
            style: const TextStyle(fontSize: 15, height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _TranslationPanel extends StatelessWidget {
  const _TranslationPanel({required this.translation, required this.onPlay});
  final TranslationTtsResult translation;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBCD7C6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.translate, size: 18, color: Color(0xFF2C6B4F)),
              const SizedBox(width: 8),
              Text('译文 · ${translation.language} · ${translation.voice}'),
              const Spacer(),
              IconButton(
                tooltip: '播放',
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(translation.translatedText),
        ],
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.summary});
  final String summary;

  @override
  Widget build(BuildContext context) {
    if (summary.trim().isEmpty) {
      return const _EmptyState(message: '暂无总结文本');
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE4DED3)),
          ),
          child: SelectableText(
            summary,
            style: const TextStyle(fontSize: 15, height: 1.65),
          ),
        ),
      ],
    );
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({required this.items});
  final List<ActionItemView> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState(message: '暂无待办事项');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        final important = item.isImportant;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: important ? const Color(0xFFFFF4D8) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: important ? const Color(0xFFE3B348) : const Color(0xFFE4DED3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    important ? Icons.priority_high : Icons.check_circle_outline,
                    color: important ? const Color(0xFF9A6A00) : AppColors.successGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: important ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (important)
                    const _Badge(text: '重点待办 · 3人以上提到', color: Color(0xFF9A6A00)),
                  _Badge(text: '提到人数 ${item.speakerCount}', color: Color(0xFF6E675F)),
                  if (item.owner != null && item.owner!.isNotEmpty)
                    _Badge(text: '负责人 ${item.owner}', color: Color(0xFF356B83)),
                  if (item.due != null && item.due!.isNotEmpty)
                    _Badge(text: '截止 ${item.due}', color: Color(0xFF825E35)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/textures/empty_state_texture.png'),
            opacity: 0.12,
            fit: BoxFit.cover,
          ),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF6E675F)),
        ),
      ),
    );
  }
}
