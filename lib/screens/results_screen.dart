import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/transcription_models.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';
import '../utils/speaker_avatar.dart';
import '../utils/summary_template_analyzer.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.result});
  final TranscriptionResult result;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _summaryController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, String> _speakerAliases = {};
  final Set<String> _completedActionItemKeys = {};
  TranslationTtsResult? _translation;
  bool _isTranslating = false;
  bool _isEditingSummary = false;
  bool _isRegeneratingSummary = false;
  late String _meetingTitle;
  late String _summaryText;
  late String _summaryModule;
  late String _summaryTemplateText;
  late String _summaryTemplateAnalysis;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _meetingTitle = widget.result.meetingTitle;
    _summaryText = widget.result.summary;
    _summaryTemplateText = widget.result.summaryTemplateText;
    _summaryTemplateAnalysis = widget.result.summaryTemplateAnalysis;
    _summaryModule = widget.result.summaryModule == 'imported' &&
            _summaryTemplateText.trim().isNotEmpty
        ? 'imported'
        : 'default';
    _summaryController = TextEditingController(text: _summaryText);
    _completedActionItemKeys.addAll(widget.result.completedActionItemKeys);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _summaryController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateTime = RecordWiseDateUtils.parseDateTime(widget.result.createdAt);
    final formattedDate = RecordWiseDateUtils.formatDateTime(dateTime);

    return Scaffold(
      appBar: AppBar(
        title: Text(_meetingTitle.isNotEmpty ? _meetingTitle : '会议记录'),
        actions: [
          IconButton(
            tooltip: '修改会议名称',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editMeetingTitle,
          ),
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
                  _SummaryTab(
                    summary: _summaryText,
                    controller: _summaryController,
                    isEditing: _isEditingSummary,
                    summaryModule: _summaryModule,
                    hasImportedTemplate: _summaryTemplateText.trim().isNotEmpty,
                    templateAnalysis: _summaryTemplateAnalysis,
                    isRegenerating: _isRegeneratingSummary,
                    onEdit: _startEditingSummary,
                    onSave: () => _saveSummary(),
                    onCancel: _cancelEditingSummary,
                    onCopy: _copySummaryToClipboard,
                    onImportTemplate: _importSummaryTemplate,
                    onRegenerate: _regenerateSummary,
                    onModuleChanged: _setSummaryModule,
                  ),
                  _TasksTab(
                    items: _actionItems,
                    completedKeys: _completedActionItemKeys,
                    itemKeyFor: _actionItemKey,
                    onToggle: (item, index, done) =>
                        _toggleActionItem(item, index, done),
                  ),
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

  Future<void> _editMeetingTitle() async {
    final storage = context.read<StorageService>();
    final apiService = context.read<ApiService>();
    final controller = TextEditingController(text: _meetingTitle);
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改会议名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: '会议名称',
            border: OutlineInputBorder(),
          ),
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
    controller.dispose();
    if (nextTitle == null) return;
    final normalized = nextTitle.isEmpty ? '未命名会议' : nextTitle;
    setState(() {
      _meetingTitle = normalized;
      widget.result.meetingTitle = normalized;
    });
    await storage.save(widget.result);
    try {
      await apiService.updateMeetingTitle(
        meetingId: widget.result.sessionId,
        meetingTitle: normalized,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('会议名称已本地保存，后端同步失败')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('会议名称已保存')),
    );
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

  void _startEditingSummary() {
    _summaryController.text = _summaryText;
    setState(() => _isEditingSummary = true);
  }

  void _cancelEditingSummary() {
    _summaryController.text = _summaryText;
    setState(() => _isEditingSummary = false);
  }

  Future<void> _saveSummary() async {
    final storage = context.read<StorageService>();
    final nextSummary = _summaryController.text.trimRight();
    setState(() {
      _summaryText = nextSummary;
      _isEditingSummary = false;
      widget.result.summary = nextSummary;
    });
    await storage.save(widget.result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('总结已保存')),
    );
  }

  void _copySummaryToClipboard() {
    Clipboard.setData(ClipboardData(text: _summaryText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制总结文本')),
    );
  }

  Future<void> _setSummaryModule(String module) async {
    if (module == 'imported' && _summaryTemplateText.trim().isEmpty) {
      await _importSummaryTemplate();
      return;
    }
    final storage = context.read<StorageService>();
    setState(() {
      _summaryModule = module;
      widget.result.summaryModule = module;
    });
    await storage.save(widget.result);
  }

  Future<void> _importSummaryTemplate() async {
    final storage = context.read<StorageService>();
    final controller = TextEditingController(text: _summaryTemplateText);
    final templateText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入总结模板'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 10,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '粘贴会议纪要模板文字',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('分析模板'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (templateText == null || templateText.trim().isEmpty) return;
    final analysis = SummaryTemplateAnalyzer.analyze(templateText);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认导入模板'),
        content: _TemplateAnalysisView(analysis: analysis),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _summaryTemplateText = templateText;
      _summaryTemplateAnalysis = analysis.toStorageText();
      _summaryModule = 'imported';
      widget.result.summaryTemplateText = _summaryTemplateText;
      widget.result.summaryTemplateAnalysis = _summaryTemplateAnalysis;
      widget.result.summaryModule = _summaryModule;
    });
    await storage.save(widget.result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('模板已导入，可切换模块后重新生成')),
    );
  }

  Future<void> _regenerateSummary() async {
    if (_summaryModule == 'imported' && _summaryTemplateText.trim().isEmpty) {
      await _importSummaryTemplate();
      if (_summaryTemplateText.trim().isEmpty) return;
      if (!mounted) return;
    }
    final apiService = context.read<ApiService>();
    final storage = context.read<StorageService>();
    setState(() => _isRegeneratingSummary = true);
    try {
      final generated = await apiService.regenerateSummary(
        result: widget.result,
        module: _summaryModule,
        templateText:
            _summaryModule == 'imported' ? _summaryTemplateText : null,
      );
      if (generated.summary.trim().isEmpty) {
        throw Exception('后端没有返回总结文本');
      }
      setState(() {
        _summaryText = generated.summary;
        _summaryController.text = generated.summary;
        widget.result.summary = generated.summary;
        widget.result.actionItems = generated.actionItems;
        widget.result.keyPoints = generated.keyPoints;
        widget.result.structuredActionItems = generated.structuredActionItems;
        widget.result.participants = generated.participants;
        widget.result.meetingTime = generated.meetingTime;
        _completedActionItemKeys.clear();
        widget.result.completedActionItemKeys = const [];
      });
      await storage.save(widget.result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('总结文本已重新生成')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _isRegeneratingSummary = false);
    }
  }

  Future<void> _toggleActionItem(
      ActionItemView item, int index, bool done) async {
    final storage = context.read<StorageService>();
    final key = _actionItemKey(item, index);
    setState(() {
      if (done) {
        _completedActionItemKeys.add(key);
      } else {
        _completedActionItemKeys.remove(key);
      }
      widget.result.completedActionItemKeys = _completedActionItemKeys.toList();
    });
    await storage.save(widget.result);
  }

  String _actionItemKey(ActionItemView item, int index) {
    return '$index|${item.text}|${item.owner ?? ""}|${item.due ?? ""}';
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
      ..writeln(_summaryText)
      ..writeln()
      ..writeln('待办事项');
    for (final entry in _actionItems.asMap().entries) {
      final item = entry.value;
      final done =
          _completedActionItemKeys.contains(_actionItemKey(item, entry.key));
      buffer.writeln(
        '- ${done ? "[已完成] " : ""}${item.isImportant ? "【重要】" : ""}${item.text}',
      );
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
            _Meta(
                icon: Icons.groups_2_outlined,
                label: '${result.participants.length} 人'),
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
        Text(label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF3C3935))),
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
            avatarAsset: SpeakerAvatar.assetFor(
              speakerId: segment.speakerId,
              displayName:
                  speakerAliases[segment.speakerId] ?? segment.speakerId,
            ),
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
    required this.avatarAsset,
    required this.onRenameSpeaker,
    required this.onTranslate,
    required this.languages,
  });

  final TranscriptSegmentView segment;
  final String speakerName;
  final String avatarAsset;
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
                avatar: CircleAvatar(
                  backgroundImage: AssetImage(avatarAsset),
                  backgroundColor: const Color(0xFFE8E0D4),
                ),
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
  const _SummaryTab({
    required this.summary,
    required this.controller,
    required this.isEditing,
    required this.summaryModule,
    required this.hasImportedTemplate,
    required this.templateAnalysis,
    required this.isRegenerating,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
    required this.onCopy,
    required this.onImportTemplate,
    required this.onRegenerate,
    required this.onModuleChanged,
  });

  final String summary;
  final TextEditingController controller;
  final bool isEditing;
  final String summaryModule;
  final bool hasImportedTemplate;
  final String templateAnalysis;
  final bool isRegenerating;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onCopy;
  final VoidCallback onImportTemplate;
  final VoidCallback onRegenerate;
  final ValueChanged<String> onModuleChanged;

  @override
  Widget build(BuildContext context) {
    if (summary.trim().isEmpty && !isEditing) {
      return _EmptyState(
        message: '暂无总结文本',
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_note),
              label: const Text('手动编辑'),
            ),
            TextButton.icon(
              onPressed: onImportTemplate,
              icon: const Icon(Icons.upload_file),
              label: const Text('导入模板'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE4DED3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.summarize_outlined,
                      size: 18, color: AppColors.primaryBlue),
                  const SizedBox(width: 8),
                  const Text(
                    '总结文本',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '导入模板',
                    onPressed: onImportTemplate,
                    icon: const Icon(Icons.upload_file),
                  ),
                  IconButton(
                    tooltip: '重新生成',
                    onPressed: isRegenerating ? null : onRegenerate,
                    icon: isRegenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                  if (isEditing) ...[
                    IconButton(
                      tooltip: '取消',
                      onPressed: onCancel,
                      icon: const Icon(Icons.close),
                    ),
                    IconButton(
                      tooltip: '保存',
                      onPressed: onSave,
                      icon: const Icon(Icons.check),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: '复制',
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy),
                    ),
                    IconButton(
                      tooltip: '编辑',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_note),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    selected: {summaryModule},
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(
                        value: 'default',
                        icon: Icon(Icons.article_outlined),
                        label: Text('默认格式'),
                      ),
                      ButtonSegment(
                        value: 'imported',
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('导入模板'),
                        enabled: hasImportedTemplate,
                      ),
                    ],
                    onSelectionChanged: (values) {
                      if (values.isEmpty) return;
                      onModuleChanged(values.first);
                    },
                  ),
                  if (!hasImportedTemplate)
                    const Text(
                      '导入模板后可切换',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7C746B)),
                    ),
                ],
              ),
              if (templateAnalysis.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F4EF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE4DED3)),
                  ),
                  child: Text(
                    templateAnalysis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFF5D5A54),
                    ),
                  ),
                ),
              ],
              if (isRegenerating) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 8),
              if (isEditing)
                TextField(
                  controller: controller,
                  minLines: 12,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '编辑会议总结',
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.6),
                )
              else
                SelectableText(
                  summary,
                  style: const TextStyle(fontSize: 15, height: 1.65),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TemplateAnalysisView extends StatelessWidget {
  const _TemplateAnalysisView({required this.analysis});

  final SummaryTemplateAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _TemplateRow(label: '样式', value: analysis.styleName),
            _TemplateRow(label: '编号', value: analysis.numberingStyle),
            _TemplateRow(label: '待办', value: analysis.actionSection),
            _TemplateRow(
              label: '栏目',
              value: analysis.sections.isEmpty
                  ? '未识别'
                  : analysis.sections.join(' / '),
            ),
            const SizedBox(height: 12),
            const Text(
              '模板预览',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F4EF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE4DED3)),
              ),
              child: Text(
                analysis.preview,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6E675F),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({
    required this.items,
    required this.completedKeys,
    required this.itemKeyFor,
    required this.onToggle,
  });

  final List<ActionItemView> items;
  final Set<String> completedKeys;
  final String Function(ActionItemView item, int index) itemKeyFor;
  final void Function(ActionItemView item, int index, bool done) onToggle;

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
        final completed = completedKeys.contains(itemKeyFor(item, index));
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: completed
                ? const Color(0xFFF2F2EE)
                : important
                    ? const Color(0xFFFFF4D8)
                    : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: completed
                  ? const Color(0xFFD8D4CC)
                  : important
                      ? const Color(0xFFE3B348)
                      : const Color(0xFFE4DED3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: completed,
                    onChanged: (value) => onToggle(item, index, value == true),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        fontWeight:
                            important ? FontWeight.w700 : FontWeight.w500,
                        color: completed ? const Color(0xFF878078) : null,
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
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
                    const _Badge(
                        text: '重点待办 · 3人以上提到', color: Color(0xFF9A6A00)),
                  if (completed)
                    const _Badge(text: '已完成', color: Color(0xFF6E675F)),
                  _Badge(
                      text: '提到人数 ${item.speakerCount}',
                      color: Color(0xFF6E675F)),
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
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, this.action});
  final String message;
  final Widget? action;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6E675F)),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
