import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transcription_models.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';
import 'results_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _confirmClearAll(
    BuildContext context,
    StorageService storage,
  ) async {
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

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final items = storage.getAll();
    final pendingTasks = items.fold<int>(
      0,
      (count, item) => count + item.actionItems.length,
    );

    return CupertinoPageScaffold(
      backgroundColor: AppColors.paper,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('RecordWise'),
            backgroundColor: AppColors.paper,
            border: Border(
              bottom: BorderSide(
                color: AppColors.separator.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            trailing: items.isNotEmpty
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _confirmClearAll(context, storage),
                    child: const Icon(
                      CupertinoIcons.delete,
                      color: AppColors.errorRed,
                      size: 22,
                    ),
                  )
                : null,
          ),
          // Stats section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: CupertinoIcons.doc_text,
                      value: '${items.length}',
                      label: '会议数',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: CupertinoIcons.checkmark_circle,
                      value: '$pendingTasks',
                      label: '待办项',
                    ),
                  ),
                ],
              ),
            ),
          ),
          // List or empty state
          if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _HomeEmptyState(),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.separator.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < items.length; i++) ...[
                        _MeetingListItem(
                          result: items[i],
                          storage: storage,
                        ),
                        if (i < items.length - 1)
                          const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 0,
                            color: AppColors.separator,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.primaryBlue),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textLight,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingListItem extends StatelessWidget {
  const _MeetingListItem({required this.result, required this.storage});

  final TranscriptionResult result;
  final StorageService storage;

  @override
  Widget build(BuildContext context) {
    final dateTime = RecordWiseDateUtils.parseDateTime(result.createdAt);
    final formattedDate = RecordWiseDateUtils.formatDateTime(dateTime);
    final title =
        result.meetingTitle.isNotEmpty ? result.meetingTitle : '未命名会议';

    return Dismissible(
      key: ValueKey(result.sessionId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.errorRed,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.delete, color: CupertinoColors.white),
            SizedBox(height: 4),
            Text(
              '删除',
              style: TextStyle(
                color: CupertinoColors.white,
                fontSize: 12,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) => showCupertinoDialog<bool>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('删除会议记录？'),
          content: Text('确认删除"$title"？'),
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
      ),
      onDismissed: (_) => storage.delete(result.sessionId),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => Navigator.push(
          context,
          CupertinoPageRoute(builder: (_) => ResultsScreen(result: result)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.time,
                          size: 13,
                          color: AppColors.textLight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textLight,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          CupertinoIcons.timer,
                          size: 13,
                          color: AppColors.textLight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${result.durationMinutes.toStringAsFixed(1)} min',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textLight,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                    if (result.meetingType.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          result.meetingType.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: AppColors.textLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.doc_text, size: 52, color: AppColors.textLight),
          SizedBox(height: 12),
          Text(
            '暂无会议记录',
            style: TextStyle(
              fontSize: 17,
              color: AppColors.textLight,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
