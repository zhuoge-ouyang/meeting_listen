# RecordWise 配置文档

本文档面向自己部署和二开 RecordWise 的使用者。核心原则是：移动端不保存 DashScope、OSS 或模型 API Key，每个人部署自己的后端，并在 App 设置页填写自己的后端服务地址。

## 1. 架构配置边界

- Flutter App：只保存后端服务地址，例如 `http://192.168.1.33:8000` 或 `https://api.example.com`。
- FastAPI 后端：保存 DashScope、OSS、模型名称、TTS 缓存目录等服务端配置。
- 阿里云 DashScope：用于 Fun-ASR / Paraformer 转写、Qwen 总结、Qwen-MT 翻译、Qwen-TTS 朗读。
- 阿里云 OSS：用于上传录音文件，并向 DashScope ASR 提供可访问的音频 URL。

不要把以下内容写入 Flutter 源码、APK、截图、README 示例真实值或 GitHub：

- `DASHSCOPE_API_KEY`
- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `API_TOKEN`
- 任何真实 OSS 私有访问地址、签名 URL 或临时凭证

## 2. 后端环境变量

复制示例文件：

```powershell
Copy-Item recordwise_backend\.env_sample recordwise_backend\.env
```

必须配置：

| 变量 | 用途 |
| --- | --- |
| `DASHSCOPE_API_KEY` | DashScope API Key，用于 ASR、Qwen、翻译和 TTS |
| `DASHSCOPE_BASE_URL` | DashScope 原生 API 地址，默认 `https://dashscope.aliyuncs.com/api/v1` |
| `DASHSCOPE_COMPATIBLE_BASE_URL` | OpenAI 兼容模式地址，默认 `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| `ALIYUN_ASR_MODEL` | 转写模型，当前默认 `fun-asr` |
| `QWEN_SUMMARY_MODEL` | 总结模型，当前默认 `qwen3.7-max` |
| `QWEN_MT_MODEL` | 翻译模型，当前默认 `qwen-mt-flash` |
| `QWEN_TTS_MODEL` | 朗读模型，当前默认 `qwen3-tts-flash` |
| `ALIYUN_ACCESS_KEY_ID` | 阿里云 AccessKey ID，用于 OSS 上传 |
| `ALIYUN_ACCESS_KEY_SECRET` | 阿里云 AccessKey Secret，用于 OSS 上传 |
| `ALIYUN_OSS_ENDPOINT` | OSS Endpoint，例如 `https://oss-cn-beijing.aliyuncs.com` |
| `ALIYUN_OSS_BUCKET` | OSS Bucket 名称 |
| `TTS_AUDIO_CACHE_DIR` | TTS 音频缓存目录，默认 `storage/tts` |

可选配置：

| 变量 | 用途 |
| --- | --- |
| `ALIYUN_OSS_PUBLIC_BASE_URL` | Bucket 公网或 CDN 地址；为空时后端使用签名 URL |
| `ALIYUN_OSS_SIGNED_URL_EXPIRE_SECONDS` | OSS 签名 URL 有效期，默认 3600 秒 |
| `REQUIRE_AUTH` | 后端 Bearer Token 开关 |
| `API_TOKEN` | `REQUIRE_AUTH=true` 时的后端访问 Token |

当前 Flutter App 只配置后端 URL，暂未提供 `API_TOKEN` 输入和请求头发送。若把后端部署到公网，不建议直接裸露服务；先使用私有网络、反向代理鉴权、IP 白名单，或后续补移动端后端 Token 配置后再开启 `REQUIRE_AUTH=true`。

## 3. OSS Bucket 和 Endpoint

创建 OSS Bucket 时保持以下原则：

- 地域选择离自己近且与 DashScope 服务访问稳定的地域，例如华北 2（北京）。
- 读写权限建议保持私有。
- `ALIYUN_OSS_BUCKET` 填 Bucket 名称，例如 `meeting-listen-ouyang-0621`。
- `ALIYUN_OSS_ENDPOINT` 填访问端口里的外网 Endpoint，例如 `https://oss-cn-beijing.aliyuncs.com`。
- 如果 Bucket 私有，`ALIYUN_OSS_PUBLIC_BASE_URL` 可以留空，由后端生成签名 URL。

后端需要 OSS 的原因：DashScope 的文件转写接口需要一个它能访问的音频 URL。手机直接把录音传给后端，后端上传到 OSS，再把 OSS URL 交给 ASR。

## 4. 本地启动后端

首次安装依赖：

```powershell
cd recordwise_backend
python -m pip install -r requirements.txt
```

如果本机需要指定 FFmpeg：

```powershell
$env:IMAGEIO_FFMPEG_EXE="D:\tools\ffmpeg\ffmpeg-8.1.1-full_build\bin\ffmpeg.exe"
```

启动后端：

```powershell
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

检查健康状态：

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/health
```

状态里应看到：

- `dashscope: configured`
- `aliyun_oss: configured`
- `audio_processor: operational`

## 5. App 连接后端

打开 App：`设置` -> `后端服务地址`。

常见填写方式：

| 场景 | 地址示例 |
| --- | --- |
| 安卓模拟器访问电脑后端 | `http://10.0.2.2:8000` |
| 真机和电脑在同一局域网 | `http://电脑局域网IP:8000` |
| 部署到云服务器 | `https://your-domain.example.com` |

设置页支持：

- 输入地址后保存到手机本地。
- 自动补全 `http://`。
- 自动去掉尾部 `/`。
- 测试连接 `/api/test`。
- 清除本机配置，回到构建默认值或未配置状态。

开发打包时也可以预置默认地址：

```powershell
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.33:8000
```

用户仍可在设置页覆盖这个默认地址。

## 6. 常见问题

### 安装 APK 后是否还需要开发者电脑启动？

取决于 App 设置里的后端地址。

- 如果地址是开发者电脑的局域网 IP，电脑关机或后端停止后不可用。
- 如果地址是使用者自己部署的公网后端，手机只要能访问该后端就可以独立使用。
- 如果地址为空，录音转写、总结、翻译朗读都会失败。

### 可以把豆包、OpenAI 或其他模型 Key 填到前端吗？

不建议。当前实现也没有前端模型 Key 输入。模型供应商 Key 应放后端，由后端适配不同模型 API。这样 APK 不会泄漏密钥，也方便以后更换模型供应商。

### 可以不用 OSS 吗？

当前主链路需要 OSS，因为 DashScope ASR 需要可访问的音频 URL。若要去掉 OSS，需要改后端 ASR 上传方式或更换支持直传音频的转写服务，这是另一项后端能力改造。
