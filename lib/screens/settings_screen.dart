import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/user_settings_service.dart';
import '../utils/constants.dart';
import '../utils/toast_utils.dart';
import 'log_screen.dart';

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
    AppToast.show(context, message);
  }

  String _formatError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<UserSettingsService>();

    return CupertinoPageScaffold(
      backgroundColor: AppColors.surface,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('设置'),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 20),
            _buildBackendConfigSection(settings),
            const SizedBox(height: 20),
            _buildSection(
              header: '密钥策略',
              icon: CupertinoIcons.lock,
              items: [
                '阿里云 DashScope 和 OSS 密钥只配置在后端环境变量。',
                '移动端不保存 API Key，避免安装包或本地存储泄漏。',
              ],
            ),
            const SizedBox(height: 20),
            _buildSection(
              header: '处理链路',
              icon: CupertinoIcons.flowchart,
              items: [
                '转写：Fun-ASR / Paraformer，开启说话人分离。',
                '总结：Qwen，输出会议纪要和待办事项。',
                '翻译朗读：Qwen-MT + Qwen-TTS 系统音色。',
              ],
            ),
            const SizedBox(height: 20),
            _buildLogEntry(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBackendConfigSection(UserSettingsService settings) {
    final canSubmit = !_isSaving && !_isTesting;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.desktopcomputer,
                    color: AppColors.primaryBlue, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '后端服务',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                  ),
                  child: Text(
                    settings.apiBaseUrlSource,
                    style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _backendUrlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              placeholder: '例如：http://192.168.1.33:8000',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(CupertinoIcons.link,
                    color: AppColors.textLight, size: 18),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.separator),
                borderRadius: BorderRadius.circular(8),
              ),
              onSubmitted: (_) => _saveBackendUrl(),
            ),
            const SizedBox(height: 10),
            Text(
              settings.apiBaseUrl.isEmpty
                  ? '未配置时，录音转写、总结和翻译朗读无法连接后端。'
                  : '当前请求地址：${settings.apiBaseUrl}',
              style: const TextStyle(
                color: AppColors.textLight,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                CupertinoButton.filled(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  onPressed: canSubmit ? _saveBackendUrl : null,
                  child: _isSaving
                      ? const CupertinoActivityIndicator(
                          color: Colors.white, radius: 8)
                      : const Text('保存', style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 10),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  onPressed: canSubmit ? _testBackendUrl : null,
                  child: _isTesting
                      ? const CupertinoActivityIndicator(radius: 8)
                      : const Text('测试连接', style: TextStyle(fontSize: 14)),
                ),
                const Spacer(),
                CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onPressed: canSubmit ? _clearBackendUrl : null,
                  child: const Text('清除',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.errorRed)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogEntry(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () {
          Navigator.of(context).push(
            CupertinoPageRoute(builder: (_) => const LogScreen()),
          );
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(CupertinoIcons.doc_text_search,
                  color: AppColors.primaryBlue, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '运行日志',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Icon(CupertinoIcons.chevron_right,
                  color: AppColors.textLight, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String header,
    required IconData icon,
    required List<String> items,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primaryBlue, size: 20),
                const SizedBox(width: 8),
                Text(
                  header,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 16, color: AppColors.separator),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                items[i],
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
