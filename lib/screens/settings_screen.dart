import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/user_settings_service.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backendUrlController = TextEditingController();
  String? _loadedUrl;
  bool _isSaving = false;
  bool _isTesting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentUrl = Provider.of<UserSettingsService>(context).apiBaseUrl;
    if (_loadedUrl != currentUrl) {
      _backendUrlController.text = currentUrl;
      _loadedUrl = currentUrl;
    }
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveBackendUrl() async {
    setState(() => _isSaving = true);
    try {
      await context
          .read<UserSettingsService>()
          .saveApiBaseUrl(_backendUrlController.text);
      if (!mounted) return;
      _showMessage('已保存后端服务地址。');
    } catch (e) {
      if (!mounted) return;
      _showMessage('保存失败：${_formatError(e)}');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _testBackendUrl() async {
    final url = _backendUrlController.text.trim();
    if (url.isEmpty) {
      _showMessage('请先填写后端服务地址。');
      return;
    }

    setState(() => _isTesting = true);
    try {
      await context.read<ApiService>().testConnection(baseUrlOverride: url);
      if (!mounted) return;
      _showMessage('连接成功。');
    } catch (e) {
      if (!mounted) return;
      _showMessage('连接失败：${_formatError(e)}');
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _clearBackendUrl() async {
    await context.read<UserSettingsService>().clearApiBaseUrl();
    if (!mounted) return;
    _showMessage('已清除本机后端地址配置。');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<UserSettingsService>();

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
            _BackendConfigCard(
              controller: _backendUrlController,
              source: settings.apiBaseUrlSource,
              currentUrl: settings.apiBaseUrl,
              isSaving: _isSaving,
              isTesting: _isTesting,
              onSave: _saveBackendUrl,
              onTest: _testBackendUrl,
              onClear: _clearBackendUrl,
            ),
            const SizedBox(height: 12),
            const _InfoCard(
              icon: Icons.lock_outline,
              title: '密钥策略',
              lines: [
                'DashScope、OSS 和模型密钥只配置在用户自己的后端环境变量中。',
                '移动端只保存后端服务地址，不保存 API Key。',
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
          ],
        ),
      ),
    );
  }
}

class _BackendConfigCard extends StatelessWidget {
  const _BackendConfigCard({
    required this.controller,
    required this.source,
    required this.currentUrl,
    required this.isSaving,
    required this.isTesting,
    required this.onSave,
    required this.onTest,
    required this.onClear,
  });

  final TextEditingController controller;
  final String source;
  final String currentUrl;
  final bool isSaving;
  final bool isTesting;
  final VoidCallback onSave;
  final VoidCallback onTest;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final canSubmit = !isSaving && !isTesting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns_outlined, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '后端服务',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Text(
                      source,
                      style: const TextStyle(
                        color: AppColors.primaryBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '后端服务地址',
                hintText: '例如：http://192.168.1.33:8000',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => onSave(),
            ),
            const SizedBox(height: 10),
            Text(
              currentUrl.isEmpty
                  ? '未配置时，录音转写、总结和翻译朗读无法连接后端。'
                  : '当前请求地址：$currentUrl',
              style: const TextStyle(
                color: AppColors.textLight,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: canSubmit ? onSave : null,
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
                OutlinedButton.icon(
                  onPressed: canSubmit ? onTest : null,
                  icon: isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('测试连接'),
                ),
                TextButton.icon(
                  onPressed: canSubmit ? onClear : null,
                  icon: const Icon(Icons.restart_alt_outlined),
                  label: const Text('清除本机配置'),
                ),
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
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line,
                  style: const TextStyle(
                    height: 1.45,
                    color: AppColors.textDark,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
