import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../utils/date_utils.dart';
import 'results_screen.dart';
import '../utils/constants.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _confirmClearAll(BuildContext context, StorageService storage) async {
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
          image: DecorationImage(
            image: AssetImage('assets/textures/app_bg_texture.png'),
            repeat: ImageRepeat.repeat,
            opacity: 0.05,
          ),
        ),
        child: items.isEmpty
        ? const Center(child: Text('暂无会议记录'))
        : ListView.builder(
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final r = items[i];
            final dateTime = RecordWiseDateUtils.parseDateTime(r.createdAt);
            final formattedDate = RecordWiseDateUtils.formatDateTime(dateTime);

            return Dismissible(
              key: ValueKey(r.sessionId),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                context: ctx,
                builder: (_) => AlertDialog(
                  title: const Text('删除会议记录？'),
                  content: Text(
                    '确认删除“${r.meetingTitle.isNotEmpty ? r.meetingTitle : "未命名会议"}”？',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
              onDismissed: (_) => storage.delete(r.sessionId),
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(
                    r.meetingTitle.isNotEmpty ? r.meetingTitle : '未命名会议',
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
                            '${r.durationMinutes.toStringAsFixed(1)} min',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      if (r.meetingType.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: RecordWiseDateUtils.meetingTypeColor(r.meetingType),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            r.meetingType.toUpperCase(),
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
                  onTap: () => Navigator.push(ctx, MaterialPageRoute(
                    builder: (_) => ResultsScreen(result: r),
                  )),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
