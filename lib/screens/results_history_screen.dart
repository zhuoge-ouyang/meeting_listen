import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../models/transcription_models.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';
import 'results_screen.dart';

class ResultsHistoryScreen extends StatefulWidget {
  const ResultsHistoryScreen({super.key});

  @override
  State<ResultsHistoryScreen> createState() => _ResultsHistoryScreenState();
}

class _ResultsHistoryScreenState extends State<ResultsHistoryScreen> {
  String _searchQuery = '';
  String _sortBy = 'date';
  bool _sortAscending = false;

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final allItems = storage.getAll();
    final filteredItems = _filterAndSortItems(allItems);

    return CupertinoPageScaffold(
      backgroundColor: AppColors.surface,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('会议记录'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _showSortSheet(context),
              child: const Icon(CupertinoIcons.sort_down, size: 22),
            ),
            if (allItems.isNotEmpty)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _confirmClearAll(context, storage),
                child: const Icon(CupertinoIcons.trash, size: 20),
              ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: CupertinoSearchTextField(
                placeholder: '搜索会议标题、原文或总结',
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
              ),
            ),
            if (filteredItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '找到 ${filteredItems.length} 条会议记录',
                    style: const TextStyle(
                      color: AppColors.textLight,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredItems.isEmpty
                  ? _buildEmptyState(allItems)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _buildResultItem(context, filteredItems[index], storage),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(List<TranscriptionResult> allItems) {
    if (allItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.clock, size: 56, color: AppColors.textLight),
            SizedBox(height: 16),
            Text('暂无会议记录',
                style: TextStyle(
                    fontSize: 17,
                    color: AppColors.textLight,
                    fontWeight: FontWeight.w500)),
            SizedBox(height: 8),
            Text('录音或上传音频后会显示在这里',
                style: TextStyle(fontSize: 14, color: AppColors.textLight)),
          ],
        ),
      );
    }
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.search, size: 56, color: AppColors.textLight),
          SizedBox(height: 16),
          Text('没有匹配结果',
              style: TextStyle(
                  fontSize: 17,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: 8),
          Text('可以换一个关键词再试',
              style: TextStyle(fontSize: 14, color: AppColors.textLight)),
        ],
      ),
    );
  }

  Widget _buildResultItem(
      BuildContext context, TranscriptionResult item, StorageService storage) {
    final dateTime = RecordWiseDateUtils.parseDateTime(item.createdAt);
    final formattedDate = RecordWiseDateUtils.formatDate(dateTime);
    final formattedTime = RecordWiseDateUtils.formatTime(dateTime);

    return Dismissible(
      key: ValueKey(item.sessionId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.errorRed,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.delete, color: CupertinoColors.white),
            SizedBox(height: 4),
            Text('删除',
                style: TextStyle(color: CupertinoColors.white, fontSize: 12)),
          ],
        ),
      ),
      confirmDismiss: (_) => _confirmDeleteItem(context, item),
      onDismissed: (_) => storage.delete(item.sessionId),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(builder: (_) => ResultsScreen(result: item)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.meetingTitle.isNotEmpty
                                ? item.meetingTitle
                                : '未命名会议',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (item.meetingType.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: RecordWiseDateUtils.meetingTypeColor(
                                  item.meetingType),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              item.meetingType.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: CupertinoColors.white),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(CupertinoIcons.calendar,
                            size: 13, color: AppColors.textLight),
                        const SizedBox(width: 4),
                        Text(formattedDate,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textLight)),
                        const SizedBox(width: 14),
                        const Icon(CupertinoIcons.time,
                            size: 13, color: AppColors.textLight),
                        const SizedBox(width: 4),
                        Text(formattedTime,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textLight)),
                        const SizedBox(width: 14),
                        const Icon(CupertinoIcons.timer,
                            size: 13, color: AppColors.textLight),
                        const SizedBox(width: 4),
                        Text('${item.durationMinutes.toStringAsFixed(1)} 分钟',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textLight)),
                      ],
                    ),
                    if (item.transcription.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.transcription.length > 100
                            ? '${item.transcription.substring(0, 100)}...'
                            : item.transcription,
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textLight,
                            height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (item.wordCount > 0) ...[
                          const Icon(CupertinoIcons.textformat_size,
                              size: 13, color: AppColors.textLight),
                          const SizedBox(width: 4),
                          Text('${item.wordCount} 字',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textLight)),
                        ],
                        if (item.actionItems.isNotEmpty) ...[
                          if (item.wordCount > 0) const SizedBox(width: 14),
                          const Icon(CupertinoIcons.checkmark_circle,
                              size: 13, color: AppColors.textLight),
                          const SizedBox(width: 4),
                          Text('${item.actionItems.length} 项待办',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textLight)),
                        ],
                        if (item.keyPoints.isNotEmpty) ...[
                          if (item.wordCount > 0 || item.actionItems.isNotEmpty)
                            const SizedBox(width: 14),
                          const Icon(CupertinoIcons.star,
                              size: 13, color: AppColors.textLight),
                          const SizedBox(width: 4),
                          Text('${item.keyPoints.length} 条纪要',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textLight)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(CupertinoIcons.chevron_right,
                  size: 16, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDeleteItem(
      BuildContext context, TranscriptionResult item) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('删除会议记录？'),
        content: Text(
          '确认删除"${item.meetingTitle.isNotEmpty ? item.meetingTitle : "未命名会议"}"？',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll(
      BuildContext context, StorageService storage) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('清空全部会议记录？'),
        content: const Text('这会删除本机保存的全部转写和纪要。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm == true) await storage.clearAll();
  }

  void _showSortSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('排序方式'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                if (_sortBy == 'date') {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = 'date';
                  _sortAscending = false;
                }
              });
            },
            child: Text(
              '按日期${_sortBy == "date" ? (_sortAscending ? " ↑" : " ↓") : ""}',
              style: TextStyle(
                color: _sortBy == 'date'
                    ? AppColors.primaryBlue
                    : AppColors.textDark,
              ),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                if (_sortBy == 'title') {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = 'title';
                  _sortAscending = false;
                }
              });
            },
            child: Text(
              '按标题${_sortBy == "title" ? (_sortAscending ? " ↑" : " ↓") : ""}',
              style: TextStyle(
                color: _sortBy == 'title'
                    ? AppColors.primaryBlue
                    : AppColors.textDark,
              ),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                if (_sortBy == 'duration') {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = 'duration';
                  _sortAscending = false;
                }
              });
            },
            child: Text(
              '按时长${_sortBy == "duration" ? (_sortAscending ? " ↑" : " ↓") : ""}',
              style: TextStyle(
                color: _sortBy == 'duration'
                    ? AppColors.primaryBlue
                    : AppColors.textDark,
              ),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  List<TranscriptionResult> _filterAndSortItems(List<TranscriptionResult> items) {
    var filtered = items.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item.meetingTitle.toLowerCase().contains(_searchQuery) ||
          item.transcription.toLowerCase().contains(_searchQuery) ||
          item.summary.toLowerCase().contains(_searchQuery) ||
          item.meetingType.toLowerCase().contains(_searchQuery);
    }).toList();

    filtered.sort((a, b) {
      int comparison;
      switch (_sortBy) {
        case 'title':
          comparison = a.meetingTitle.compareTo(b.meetingTitle);
          break;
        case 'duration':
          comparison = a.durationMinutes.compareTo(b.durationMinutes);
          break;
        default:
          comparison = RecordWiseDateUtils.parseDateTime(a.createdAt)
              .compareTo(RecordWiseDateUtils.parseDateTime(b.createdAt));
      }
      return _sortAscending ? comparison : -comparison;
    });
    return filtered;
  }
}
