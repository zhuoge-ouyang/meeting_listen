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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空全部会议记录？'),
        content: const Text('这会删除本机保存的全部转写和纪要。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空全部',
              onPressed: () => _confirmClearAll(context, storage),
            ),
        ],
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
        child: items.isEmpty
            ? ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _HomeHero(
                    meetingCount: 0,
                    pendingTasks: 0,
                  ),
                  const SizedBox(height: 36),
                  const _HomeEmptyState(),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: items.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    return _HomeHero(
                      meetingCount: items.length,
                      pendingTasks: pendingTasks,
                    );
                  }
                  return _MeetingListItem(
                    result: items[i - 1],
                    storage: storage,
                  );
                },
              ),
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.meetingCount,
    required this.pendingTasks,
  });

  final int meetingCount;
  final int pendingTasks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final height = wide ? 260.0 : 218.0;
        return Container(
          height: height,
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                blurRadius: 22,
                offset: Offset(0, 10),
                color: Color(0x22000000),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/home/home_hero.jpg', fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xAA14221C),
                      Color(0x3314221C),
                      Color(0x0014221C),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: wide ? 34 : 22,
                bottom: wide ? 28 : 22,
                right: 22,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroMetric(
                      icon: Icons.library_books_outlined,
                      label: '会议',
                      value: '$meetingCount',
                    ),
                    _HeroMetric(
                      icon: Icons.task_alt,
                      label: '待办',
                      value: '$pendingTasks',
                    ),
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

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E1D8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primaryBlue),
          const SizedBox(width: 6),
          Text(
            '$label $value',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF22342E),
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
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red[400],
          borderRadius: BorderRadius.circular(8),
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
          content: Text('确认删除“$title”？'),
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
      onDismissed: (_) => storage.delete(result.sessionId),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    formattedDate,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.timer, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${result.durationMinutes.toStringAsFixed(1)} min',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              if (result.meetingType.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: RecordWiseDateUtils.meetingTypeColor(
                        result.meetingType),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.meetingType.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ResultsScreen(result: result)),
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
          Icon(Icons.library_books_outlined,
              size: 52, color: Color(0xFF8B867C)),
          SizedBox(height: 12),
          Text(
            '暂无会议记录',
            style: TextStyle(
              fontSize: 17,
              color: Color(0xFF5D5A54),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
