"""
RecordWise Configuration
"""

import os
from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # App settings
    APP_NAME: str = "RecordWise"
    APP_VERSION: str = "2.0.0"
    DEBUG: bool = True
    
    # API Security
    API_TOKEN: str = "recordwise-secure-token-2025"
    REQUIRE_AUTH: bool = False
    
    # Aliyun / DashScope — primary provider for the forked meeting assistant.
    DASHSCOPE_API_KEY: Optional[str] = None
    DASHSCOPE_BASE_URL: str = "https://dashscope.aliyuncs.com/api/v1"
    DASHSCOPE_COMPATIBLE_BASE_URL: str = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    ALIYUN_ASR_MODEL: str = "fun-asr"
    QWEN_SUMMARY_MODEL: str = "qwen-plus"
    QWEN_MT_MODEL: str = "qwen-mt-flash"
    QWEN_TTS_MODEL: str = "qwen3-tts-flash"

    # OSS is required because DashScope recorded-file transcription consumes
    # a public HTTP(S) file URL rather than raw multipart audio bytes.
    ALIYUN_ACCESS_KEY_ID: Optional[str] = None
    ALIYUN_ACCESS_KEY_SECRET: Optional[str] = None
    ALIYUN_OSS_ENDPOINT: Optional[str] = None
    ALIYUN_OSS_BUCKET: Optional[str] = None
    ALIYUN_OSS_PUBLIC_BASE_URL: Optional[str] = None
    ALIYUN_OSS_SIGNED_URL_EXPIRE_SECONDS: int = 3600

    # Local generated-audio cache. FastAPI serves these through /api/tts-audio.
    TTS_AUDIO_CACHE_DIR: str = "storage/tts"
    
    # Server
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    
    model_config = {"env_file": ".env", "extra": "ignore"}

_settings = None

def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings
