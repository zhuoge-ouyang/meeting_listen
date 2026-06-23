import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/log_service.dart';
import '../utils/constants.dart';
import '../utils/toast_utils.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyAll(BuildContext context) {
    final logService = context.read<LogService>();
    final text = logService.copyAllText();
    if (text.isEmpty) {
      AppToast.show(context, '暂无日志可复制');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    AppToast.show(context, '已复制');
  }

  void _clearLogs(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定要清空所有日志吗？'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              context.read<LogService>().clear();
              Navigator.pop(context);
            },
            child: const Text('清空'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Color _colorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return AppColors.primaryBlue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return AppColors.errorRed;
    }
  }

  Color _colorForSource(LogSource source) {
    switch (source) {
      case LogSource.user:
        return AppColors.successGreen;
      case LogSource.api:
        return AppColors.primaryBlue;
      case LogSource.error:
        return AppColors.errorRed;
      case LogSource.system:
        return AppColors.textLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logService = context.watch<LogService>();
    final logs = logService.logs;

    // 当日志更新时自动滚动到底部
    if (logs.isNotEmpty) {
      _scrollToBottom();
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('运行日志'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(30, 30),
              onPressed: () => _copyAll(context),
              child: const Icon(CupertinoIcons.doc_on_clipboard, size: 20),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(30, 30),
              onPressed: () => _clearLogs(context),
              child: const Icon(CupertinoIcons.trash, size: 20),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: logs.isEmpty
            ? const Center(
                child: Text(
                  '暂无日志',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textLight,
                  ),
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final entry = logs[index];
                  return _buildLogItem(entry);
                },
              ),
      ),
    );
  }

  Widget _buildLogItem(LogEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间
          Text(
            entry.formattedTime,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textLight,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          // 来源标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _colorForSource(entry.source).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.sourceLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _colorForSource(entry.source),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 级别标签（仅 WARNING/ERROR 显示）
          if (entry.level != LogLevel.info)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: _colorForLevel(entry.level).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                entry.levelLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _colorForLevel(entry.level),
                ),
              ),
            ),
          // 消息内容
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontSize: 13,
                color: entry.level == LogLevel.error
                    ? AppColors.errorRed
                    : AppColors.textDark,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
