# RecordWise / meeting_listen Agent Guide

本文件是这个仓库的项目级执行约束。优先遵守用户本轮明确要求；没有冲突时按本文执行。

## 项目概况

- 前端是 Flutter App，入口在 `lib/main.dart`，主要页面在 `lib/screens/`，服务封装在 `lib/services/`。
- 后端是 FastAPI，入口在 `recordwise_backend/app/main.py`，配置在 `recordwise_backend/utils/config.py`，业务服务在 `recordwise_backend/services/`。
- 主链路：App 录音或上传音频 -> 后端标准化音频 -> OSS URL -> DashScope ASR 说话人分离 -> Qwen 会议纪要 / 待办 -> 可选 Qwen-MT + Qwen-TTS。
- Flutter App 只保存后端服务地址；DashScope、OSS、模型和语音密钥只允许放在后端环境变量或后端 `.env`。

## 工作方式

- 先读代码和相邻实现，再改代码；先定位根因，再修表象。
- 做最小改动，保持现有项目风格，不顺手重构、不批量格式化、不引入无关抽象。
- 工作区可能已有用户改动；不要覆盖、回滚或格式化与当前任务无关的文件。
- 不自动 commit、push、删除文件、升级核心依赖、改数据库 / 认证 / CI/CD / 发布流程；这些都需要用户明确确认。
- 不允许随意增加 fallback 策略。只有在定位清楚 bug 或业务缺陷后，且得到用户明确确认，才可以新增 fallback。

## 路径与打包规则

项目开发应尽量避免绝对路径，尤其禁止在运行时代码、配置默认值和打包资源里写死开发机路径。原因是 APK、桌面包、容器或其他机器上不会存在开发者本机的 `D:\...`、`C:\Users\...`、`/Users/...`、`/home/...` 路径，打包后会直接失效。

- Flutter 资源使用 `pubspec.yaml` 声明的相对 asset 路径，例如 `assets/home/launch_planet.jpg`。
- Flutter 本地数据目录使用 `path_provider`、Hive 或平台 API 获取，不要拼接开发机绝对目录。
- 后端缓存和生成文件默认使用相对路径或环境变量，例如 `TTS_AUDIO_CACHE_DIR=storage/tts`。
- Python 路径处理优先使用 `pathlib.Path`，Dart 路径处理优先使用 `package:path/path.dart`。
- 后端地址不要写死在源码里；开发或打包默认值通过 `--dart-define=API_BASE_URL=...` 注入，用户运行时仍应可在设置页覆盖。
- 外部工具路径如果只用于本机调试，可以出现在文档或临时命令中，但必须标明是 local-only 示例，不得作为代码默认值进入打包产物。
- 新增或修改路径相关逻辑后，用搜索确认没有引入开发机绝对路径。

建议检查命令：

```powershell
rg -n --hidden --glob '!build/**' --glob '!.dart_tool/**' --glob '!*.lock' 'D:\\|C:\\|(^|[^A-Za-z0-9_.-])/(Users|home)/' .
```

## 配置与密钥

- 不要把真实 `DASHSCOPE_API_KEY`、`ALIYUN_ACCESS_KEY_ID`、`ALIYUN_ACCESS_KEY_SECRET`、`API_TOKEN`、签名 URL 或临时凭证写入源码、测试、README、截图或提交记录。
- `.env` 是本地文件，不应提交；新增配置要同步更新 `recordwise_backend/.env_sample` 和 `docs/configuration.md` 的占位说明。
- 如果要让公网 App 访问后端，优先通过部署环境变量、反向代理鉴权、IP 白名单或后续明确设计的 Token 配置处理，不要把模型供应商密钥下发到 App。

## 前端改动规则

- 优先沿用当前 `Cupertino` 风格、`Provider` 注入方式、Hive 本地存储和现有 `services/` 封装。
- API 调用集中在 `lib/services/api_service.dart`，后端 URL 由 `UserSettingsService` 统一归一化和持久化。
- 不要恢复前端模型 Key / 语音 Key 输入；当前边界是 App 只配置后端 URL。
- 修改模型字段时同步检查 `lib/models/transcription_models.dart`、生成文件、存储兼容性和相关页面。
- UI 改动要注意移动端尺寸、空状态、错误状态和加载状态。

## 后端改动规则

- FastAPI 入口和接口兼容性集中看 `recordwise_backend/app/main.py`。
- 配置读取通过 `get_settings()`，新增服务配置写入 `Settings`，并保持 `.env_sample` 同步。
- 音频、OSS、ASR、Qwen、会议分析逻辑分别放在现有 service 模块里，不要把业务细节堆到路由函数里。
- 错误处理不要吞异常；日志遵循现有 `logging` 风格，避免输出密钥、签名 URL 或完整敏感请求体。

## 验证

按改动范围选择最小有效验证，不要在未验证时声称已修好。

前端常用验证：

```powershell
flutter pub get
flutter analyze
flutter test
```

后端常用验证：

```powershell
cd recordwise_backend
python -m pip install -r requirements.txt
python -m unittest discover -s tests
python -m py_compile app\main.py services\meeting_analysis.py services\aliyun_asr_service.py services\aliyun_oss_service.py services\qwen_service.py models\transcription.py utils\config.py
```

完成前必须检查 diff，确认没有无关改动、临时代码、调试输出、密钥或开发机绝对路径。
