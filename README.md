# RecordWise 二开版

简洁会议录音纪要 App。前端保留 Flutter，后端保留 FastAPI；当前二开主链路改为阿里云 DashScope / Qwen：

- 录音或上传音频，后端标准化音频后上传 OSS。
- DashScope Fun-ASR / Paraformer 转写，开启说话人分离。
- Qwen 生成会议纪要、总结文本和待办事项。
- Qwen-MT + Qwen-TTS 对指定话语翻译并朗读。
- Flutter 详情页按三个页签展示：原录音文本、总结文本、待办事项。

## 后端配置

复制示例配置并填入真实密钥：

```powershell
Copy-Item recordwise_backend\.env_sample recordwise_backend\.env
```

核心环境变量：

- `DASHSCOPE_API_KEY`
- `DASHSCOPE_BASE_URL`
- `DASHSCOPE_COMPATIBLE_BASE_URL`
- `ALIYUN_ASR_MODEL`
- `QWEN_SUMMARY_MODEL`
- `QWEN_MT_MODEL`
- `QWEN_TTS_MODEL`
- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `ALIYUN_OSS_ENDPOINT`
- `ALIYUN_OSS_BUCKET`
- `ALIYUN_OSS_PUBLIC_BASE_URL`
- `ALIYUN_OSS_SIGNED_URL_EXPIRE_SECONDS`
- `TTS_AUDIO_CACHE_DIR`

API Key 只放在后端环境变量中，Flutter App 不保存也不上传模型或语音服务密钥。

## 后端接口

- `POST /api/meetings`：上传录音，创建会议处理任务。
- `GET /api/meetings/{meetingId}`：返回会议状态、转写、总结和待办。
- `POST /api/meetings/{meetingId}/speakers`：保存说话人名称映射。
- `POST /api/meetings/{meetingId}/translate-tts`：翻译指定话语并生成朗读音频。
- `GET /api/tts-audio/{fileName}`：读取生成的 TTS 音频。

## 前端结构

- 首页：会议列表、记录入口。
- 录音页：录音、上传、会议类型和主要语种选择。
- 详情页：顶部会议信息 + `原录音文本`、`总结文本`、`待办事项` 三个页签。
- 原文页：支持说话人改名、段落翻译朗读。
- 待办页：同一事项被 3 个或以上不同说话人提到时标记为重点待办。

## 视觉资产

`visual_assets.json` 记录 image2 贴图规范。当前仓库内先放置低干扰 PNG 占位纹理：

- `assets/textures/app_bg_texture.png`
- `assets/textures/audio_wave_texture.png`
- `assets/textures/empty_state_texture.png`

正式设计期可按 `visual_assets.json` 生成 WebP 并替换。

## 本地验证

后端：

```powershell
cd recordwise_backend
python -m pip install -r requirements.txt
python -m unittest discover -s tests
python -m py_compile app\main.py services\meeting_analysis.py services\aliyun_asr_service.py services\aliyun_oss_service.py services\qwen_service.py models\transcription.py utils\config.py
```

前端：

```powershell
flutter pub get
flutter analyze
flutter test
```

当前机器如果没有安装 Flutter/Dart，需要先安装 SDK 并加入 PATH。
