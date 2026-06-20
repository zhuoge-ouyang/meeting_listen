import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../models/transcription_models.dart';
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
    final storage       = context.watch<StorageService>();
    final allItems      = storage.getAll();
    final filteredItems = _filterAndSortItems(allItems);

    return Scaffold(
      appBar: AppBar(
        title: const Text('会议记录'),
        actions: [
          if (allItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空全部',
              onPressed: () => _confirmClearAll(context, storage),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                if (value == _sortBy) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = value;
                  _sortAscending = false;
                }
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'date',
                child: Row(children: [
                  Icon(_sortBy == 'date' ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.calendar_today, size: 20),
                  const SizedBox(width: 8),
                  const Text('按日期排序'),
                ]),
              ),
              PopupMenuItem(
                value: 'title',
                child: Row(children: [
                  Icon(_sortBy == 'title' ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.title, size: 20),
                  const SizedBox(width: 8),
                  const Text('按标题排序'),
                ]),
              ),
              PopupMenuItem(
                value: 'duration',
                child: Row(children: [
                  Icon(_sortBy == 'duration' ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.timer, size: 20),
                  const SizedBox(width: 8),
                  const Text('按时长排序'),
                ]),
              ),
            ],
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索会议标题、原文或总结',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),
          if (filteredItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '找到 ${filteredItems.length} 条会议记录',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredItems.isEmpty
                ? _buildEmptyState(allItems)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) =>
                        _buildResultCard(context, filteredItems[index], storage),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(List<TranscriptionResult> allItems) {
    if (allItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无会议记录',
                style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500)),
            SizedBox(height: 8),
            Text('录音或上传音频后会显示在这里',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      );
    }
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('没有匹配结果',
              style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500)),
          SizedBox(height: 8),
          Text('可以换一个关键词再试',
              style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, TranscriptionResult item, StorageService storage) {
    final dateTime      = RecordWiseDateUtils.parseDateTime(item.createdAt);
    final formattedDate = RecordWiseDateUtils.formatDate(dateTime);
    final formattedTime = RecordWiseDateUtils.formatTime(dateTime);

    return Dismissible(
      key: ValueKey(item.sessionId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red[400],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete, color: Colors.white),
            SizedBox(height: 4),
            Text('删除', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('删除会议记录？'),
          content: Text(
            '确认删除“${item.meetingTitle.isNotEmpty ? item.meetingTitle : "未命名会议"}”？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
      onDismissed: (_) => storage.delete(item.sessionId),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ResultsScreen(result: item)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.meetingTitle.isNotEmpty ? item.meetingTitle : '未命名会议',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (item.meetingType.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: RecordWiseDateUtils.meetingTypeColor(item.meetingType),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          item.meetingType.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(formattedDate, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(width: 16),
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(formattedTime, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(width: 16),
                    Icon(Icons.timer, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text('${item.durationMinutes.toStringAsFixed(1)} 分钟',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
                const SizedBox(height: 8),
                if (item.transcription.isNotEmpty)
                  Text(
                    item.transcription.length > 100
                        ? '${item.transcription.substring(0, 100)}...'
                        : item.transcription,
                    style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (item.wordCount > 0) ...[
                      Icon(Icons.text_fields, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text('${item.wordCount} 字',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                    if (item.actionItems.isNotEmpty) ...[
                      if (item.wordCount > 0) const SizedBox(width: 16),
                      Icon(Icons.task_alt, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        '${item.actionItems.length} 项待办',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                    if (item.keyPoints.isNotEmpty) ...[
                      if (item.wordCount > 0 || item.actionItems.isNotEmpty) const SizedBox(width: 16),
                      Icon(Icons.star, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        '${item.keyPoints.length} 条纪要',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context, StorageService storage) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空全部会议记录？'),
        content: const Text('这会删除本机保存的全部转写和纪要。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) await storage.clearAll();
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
