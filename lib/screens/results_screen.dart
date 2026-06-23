import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
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
import '../utils/toast_utils.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.result});
  final TranscriptionResult result;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int _selectedTab = 0;
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
    _summaryController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateTime = RecordWiseDateUtils.parseDateTime(widget.result.createdAt);
    final formattedDate = RecordWiseDateUtils.formatDateTime(dateTime);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(
            _meetingTitle.isNotEmpty ? _meetingTitle : '会议记录',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          leading: CupertinoNavigationBarBackButton(
            onPressed: () => Navigator.of(context).pop(),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _editMeetingTitle,
                child: const Icon(CupertinoIcons.pencil, size: 22),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _copyAllToClipboard(context),
                child: const Icon(CupertinoIcons.doc_on_doc, size: 20),
              ),
            ],
          ),
        ),
        backgroundColor: AppColors.paper,
        child: SafeArea(
          child: Column(
            children: [
              _Header(result: widget.result, formattedDate: formattedDate),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<int>(
                    groupValue: _selectedTab,
                    onValueChanged: (value) {
                      if (value != null) setState(() => _selectedTab = value);
                    },
                    children: const {
                      0: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('原文'),
                      ),
                      1: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('总结'),
                      ),
                      2: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('待办'),
                      ),
                    },
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _selectedTab,
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
                      originalDocument: _originalDocumentText,
                      controller: _summaryController,
                      isEditing: _isEditingSummary,
                      summaryModule: _summaryModule,
                      hasImportedTemplate: _summaryTemplateText.trim().isNotEmpty,
                      templateAnalysis: _summaryTemplateAnalysis,
                      isRegenerating: _isRegeneratingSummary,
                      onEdit: _startEditingSummary,
                      onSave: () => _saveSummary(),
                      onCancel: _cancelEditingSummary,
                      onCopySummary: _copySummaryToClipboard,
                      onCopyOriginal: _copyOriginalDocumentToClipboard,
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

  String get _originalDocumentText {
    final buffer = StringBuffer();
    _OriginalDocumentBlock? currentBlock;
    for (final segment in _segments) {
      final speakerName =
          _speakerAliases[segment.speakerId] ?? segment.speakerId;
      if (currentBlock == null || currentBlock.speakerName != speakerName) {
        if (currentBlock != null) {
          _writeOriginalDocumentBlock(buffer, currentBlock);
        }
        currentBlock = _OriginalDocumentBlock(
          speakerName: speakerName,
          startMs: segment.startMs,
          endMs: segment.endMs,
          content: StringBuffer(segment.text),
        );
      } else {
        currentBlock.endMs = segment.endMs;
        currentBlock.content.write('\n${segment.text}');
      }
    }
    if (currentBlock != null) {
      _writeOriginalDocumentBlock(buffer, currentBlock);
    }
    return buffer.toString().trimRight();
  }

  void _writeOriginalDocumentBlock(
    StringBuffer buffer,
    _OriginalDocumentBlock block,
  ) {
    buffer
      ..writeln('发言人：${block.speakerName}')
      ..writeln('发言时间：${_formatTimeRange(block.startMs, block.endMs)}')
      ..writeln('发言内容：${block.content}')
      ..writeln();
  }

  String _formatTimeRange(int startMs, int endMs) {
    String format(int ms) {
      final total = (ms / 1000).floor();
      final minutes = (total ~/ 60).toString().padLeft(2, '0');
      final seconds = (total % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }

    return '${format(startMs)}-${format(endMs)}';
  }

  Future<void> _editMeetingTitle() async {
    final storage = context.read<StorageService>();
    final apiService = context.read<ApiService>();
    final controller = TextEditingController(text: _meetingTitle);
    final nextTitle = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('修改会议名称'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            placeholder: '会议名称',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
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
      _showToast('会议名称已本地保存，后端同步失败');
      return;
    }
    if (!mounted) return;
    _showToast('会议名称已保存');
  }

  Future<void> _renameSpeaker(String speakerId) async {
    final apiService = context.read<ApiService>();
    final controller = TextEditingController(
      text: _speakerAliases[speakerId] ?? speakerId,
    );
    final alias = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('修改说话人名称'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: '显示名称',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
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
      _showToast('说话人名称已本地更新，后端同步失败');
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
    _showToast('总结已保存');
  }

  void _copySummaryToClipboard() {
    Clipboard.setData(ClipboardData(text: _summaryText));
    _showToast('已复制总结文本');
  }

  void _copyOriginalDocumentToClipboard() {
    Clipboard.setData(ClipboardData(text: _originalDocumentText));
    _showToast('已复制原文汇总');
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
    final templateText = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('导入总结模板'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            height: 200,
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              placeholder: '粘贴会议纪要模板文字',
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('分析模板'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (templateText == null || templateText.trim().isEmpty) return;
    final analysis = SummaryTemplateAnalyzer.analyze(templateText);
    if (!mounted) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认导入模板'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _TemplateAnalysisView(analysis: analysis),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回修改'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
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
    _showToast('模板已导入，可切换模块后重新生成');
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
      _showToast('总结文本已重新生成');
    } catch (error) {
      if (!mounted) return;
      _showToast('$error');
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
      _showToast('$error');
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
    _showToast('已复制完整会议记录');
  }

  void _showToast(String message) {
    AppToast.show(context, message);
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.separator, width: 0.5)),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Meta(icon: CupertinoIcons.clock, label: formattedDate),
          _Meta(
            icon: CupertinoIcons.timer,
            label: '${result.durationMinutes.toStringAsFixed(1)} min',
          ),
          _Meta(icon: CupertinoIcons.globe, label: result.languageDisplay),
          if (result.participants.isNotEmpty)
            _Meta(
                icon: CupertinoIcons.person_2,
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
        Icon(icon, size: 15, color: AppColors.textLight),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
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
            child: Center(child: CupertinoActivityIndicator()),
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
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(
          bottom: BorderSide(color: AppColors.separator, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                segment.timeRange,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textLight),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRenameSpeaker,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: AssetImage(avatarAsset),
                      backgroundColor: AppColors.surface,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      speakerName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: () => _showLanguageMenu(context),
                child: const Icon(
                  CupertinoIcons.waveform,
                  size: 20,
                  color: AppColors.primaryBlue,
                ),
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

  void _showLanguageMenu(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择翻译语言'),
        actions: [
          for (final language in languages)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                onTranslate(language.$1);
              },
              child: Text(language.$2),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
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
        color: AppColors.successGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.successGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.textformat_alt, size: 18, color: AppColors.successGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '译文 · ${translation.language} · ${translation.voice}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textLight),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 32),
                onPressed: onPlay,
                child: const Icon(CupertinoIcons.play_fill, size: 20, color: AppColors.primaryBlue),
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

class _OriginalDocumentBlock {
  _OriginalDocumentBlock({
    required this.speakerName,
    required this.startMs,
    required this.endMs,
    required this.content,
  });

  final String speakerName;
  final int startMs;
  int endMs;
  final StringBuffer content;
}

class _SummaryTab extends StatefulWidget {
  const _SummaryTab({
    required this.summary,
    required this.originalDocument,
    required this.controller,
    required this.isEditing,
    required this.summaryModule,
    required this.hasImportedTemplate,
    required this.templateAnalysis,
    required this.isRegenerating,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
    required this.onCopySummary,
    required this.onCopyOriginal,
    required this.onImportTemplate,
    required this.onRegenerate,
    required this.onModuleChanged,
  });

  final String summary;
  final String originalDocument;
  final TextEditingController controller;
  final bool isEditing;
  final String summaryModule;
  final bool hasImportedTemplate;
  final String templateAnalysis;
  final bool isRegenerating;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onCopySummary;
  final VoidCallback onCopyOriginal;
  final VoidCallback onImportTemplate;
  final VoidCallback onRegenerate;
  final ValueChanged<String> onModuleChanged;

  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> {
  String _documentTab = 'summary';

  @override
  Widget build(BuildContext context) {
    final showingSummary = _documentTab == 'summary';
    if (widget.summary.trim().isEmpty &&
        widget.originalDocument.trim().isEmpty &&
        !widget.isEditing) {
      return _EmptyState(
        message: '暂无文档内容',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              onPressed: widget.onEdit,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(CupertinoIcons.pencil, size: 16), SizedBox(width: 4), Text('手动编辑')],
              ),
            ),
            CupertinoButton(
              onPressed: widget.onImportTemplate,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(CupertinoIcons.arrow_up_doc, size: 16), SizedBox(width: 4), Text('导入模板')],
              ),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.separator, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildToolbar(showingSummary),
              const SizedBox(height: 12),
              _buildDocumentSegment(),
              const SizedBox(height: 12),
              if (showingSummary) _buildModuleSegment(),
              const SizedBox(height: 10),
              _buildContent(showingSummary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(bool showingSummary) {
    return Row(
      children: [
        Icon(
          showingSummary ? CupertinoIcons.doc_text : CupertinoIcons.doc_plaintext,
          size: 18, color: AppColors.primaryBlue,
        ),
        const SizedBox(width: 8),
        Text(showingSummary ? '总结文档' : '原文汇总', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const Spacer(),
        if (showingSummary) ...[
          CupertinoButton(padding: EdgeInsets.zero, minimumSize: const Size(32, 32), onPressed: widget.onImportTemplate, child: const Icon(CupertinoIcons.arrow_up_doc, size: 20)),
          CupertinoButton(
            padding: EdgeInsets.zero, minimumSize: const Size(32, 32),
            onPressed: widget.isRegenerating ? null : widget.onRegenerate,
            child: widget.isRegenerating ? const CupertinoActivityIndicator(radius: 9) : const Icon(CupertinoIcons.arrow_2_circlepath, size: 20),
          ),
          if (widget.isEditing) ...[
            CupertinoButton(padding: EdgeInsets.zero, minimumSize: const Size(32, 32), onPressed: widget.onCancel, child: const Icon(CupertinoIcons.xmark, size: 18, color: AppColors.errorRed)),
            CupertinoButton(padding: EdgeInsets.zero, minimumSize: const Size(32, 32), onPressed: widget.onSave, child: const Icon(CupertinoIcons.checkmark_alt, size: 20, color: AppColors.successGreen)),
          ] else ...[
            CupertinoButton(padding: EdgeInsets.zero, minimumSize: const Size(32, 32), onPressed: widget.onCopySummary, child: const Icon(CupertinoIcons.doc_on_clipboard, size: 20)),
            CupertinoButton(padding: EdgeInsets.zero, minimumSize: const Size(32, 32), onPressed: widget.onEdit, child: const Icon(CupertinoIcons.pencil, size: 20)),
          ],
        ] else
          CupertinoButton(
            padding: EdgeInsets.zero, minimumSize: const Size(32, 32),
            onPressed: widget.originalDocument.trim().isEmpty ? null : widget.onCopyOriginal,
            child: const Icon(CupertinoIcons.doc_on_clipboard, size: 20),
          ),
      ],
    );
  }

  Widget _buildDocumentSegment() {
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<String>(
        groupValue: _documentTab,
        onValueChanged: (value) { if (value != null) setState(() => _documentTab = value); },
        children: const {
          'summary': Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('总结文档')),
          'original': Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('原文汇总')),
        },
      ),
    );
  }

  Widget _buildModuleSegment() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: widget.summaryModule,
            onValueChanged: (value) { if (value != null) widget.onModuleChanged(value); },
            children: const {
              'default': Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('默认格式')),
              'imported': Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('导入模板')),
            },
          ),
        ),
        if (!widget.hasImportedTemplate)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('导入模板后可切换', style: TextStyle(fontSize: 12, color: AppColors.textLight))),
        if (widget.templateAnalysis.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
            child: Text(widget.templateAnalysis, style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textLight)),
          ),
        ],
        if (widget.isRegenerating) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );
  }

  Widget _buildContent(bool showingSummary) {
    if (showingSummary && widget.isEditing) {
      return CupertinoTextField(
        controller: widget.controller, minLines: 12, maxLines: null,
        keyboardType: TextInputType.multiline, placeholder: '编辑会议总结',
        style: const TextStyle(fontSize: 15, height: 1.6),
      );
    } else if (showingSummary) {
      return SelectableText(
        widget.summary.trim().isEmpty ? '暂无总结文本' : widget.summary,
        style: const TextStyle(fontSize: 15, height: 1.65),
      );
    }
    return _OriginalDocumentView(document: widget.originalDocument);
  }
}

class _OriginalDocumentView extends StatelessWidget {
  const _OriginalDocumentView({required this.document});
  final String document;

  @override
  Widget build(BuildContext context) {
    if (document.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('暂无原文汇总', style: TextStyle(color: AppColors.textLight))),
      );
    }
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
      child: SelectableText(document, style: const TextStyle(fontSize: 14, height: 1.65, color: AppColors.textDark)),
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
            _TemplateRow(label: '栏目', value: analysis.sections.isEmpty ? '未识别' : analysis.sections.join(' / ')),
            const SizedBox(height: 12),
            const Text('模板预览', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
              child: Text(analysis.preview, style: const TextStyle(fontSize: 13, height: 1.45)),
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
          SizedBox(width: 48, child: Text(label, style: const TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({required this.items, required this.completedKeys, required this.itemKeyFor, required this.onToggle});
  final List<ActionItemView> items;
  final Set<String> completedKeys;
  final String Function(ActionItemView item, int index) itemKeyFor;
  final void Function(ActionItemView item, int index, bool done) onToggle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState(message: '暂无待办事项');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.separator),
      itemBuilder: (context, index) {
        final item = items[index];
        final important = item.isImportant;
        final completed = completedKeys.contains(itemKeyFor(item, index));
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          color: AppColors.paper,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => onToggle(item, index, !completed),
                    child: Container(
                      width: 22, height: 22,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: completed ? AppColors.primaryBlue : Colors.transparent,
                        border: Border.all(color: completed ? AppColors.primaryBlue : AppColors.separator, width: 1.5),
                      ),
                      child: completed ? const Icon(CupertinoIcons.checkmark, size: 14, color: AppColors.paper) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.text,
                      style: TextStyle(
                        fontSize: 15, height: 1.45,
                        fontWeight: important ? FontWeight.w600 : FontWeight.w400,
                        color: completed ? AppColors.textLight : AppColors.textDark,
                        decoration: completed ? TextDecoration.lineThrough : TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Wrap(
                  spacing: 8, runSpacing: 6,
                  children: [
                    if (important) const _Badge(text: '重点待办 · 3人以上提到', color: AppColors.errorRed),
                    if (completed) const _Badge(text: '已完成', color: AppColors.successGreen),
                    _Badge(text: '提到人数 ${item.speakerCount}', color: AppColors.textLight),
                    if (item.owner != null && item.owner!.isNotEmpty)
                      _Badge(text: '负责人${item.owner}', color: AppColors.primaryBlue),
                    if (item.due != null && item.due!.isNotEmpty)
                      _Badge(text: '截止 ${item.due}', color: AppColors.textLight),
                  ],
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.doc_text, size: 48, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textLight, fontSize: 15)),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
