import 'package:flutter/material.dart';

import '../utils/constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/textures/app_bg_texture.png'),
            repeat: ImageRepeat.repeat,
            opacity: 0.05,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _InfoCard(
              icon: Icons.lock_outline,
              title: '密钥策略',
              lines: [
                '阿里云 DashScope 和 OSS 密钥只配置在后端环境变量。',
                '移动端不保存 API Key，避免安装包或本地存储泄漏。',
              ],
            ),
            const SizedBox(height: 12),
            const _InfoCard(
              icon: Icons.account_tree_outlined,
              title: '处理链路',
              lines: [
                '转写：Fun-ASR / Paraformer，开启说话人分离。',
                '总结：Qwen，输出会议纪要和待办事项。',
                '翻译朗读：Qwen-MT + Qwen-TTS 系统音色。',
              ],
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.dns_outlined,
              title: '后端',
              lines: [
                'API URL: ${AppConstants.apiBaseUrl}',
                '部署后可通过 --dart-define=API_BASE_URL=... 覆盖。',
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line,
                  style: const TextStyle(height: 1.45, color: AppColors.textDark),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
