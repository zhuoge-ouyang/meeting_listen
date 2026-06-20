"""
RecordWise Language Detection Service

Detects language from transcribed text using Unicode character analysis.
Audio-level / per-phrase locale identification is handled natively by
Azure AI Speech Fast Transcription (see `AzureSpeechSTTService`); this
detector is only used as a metadata lookup (name, native name, script)
for the response payload.
"""

import re
from typing import Dict, Tuple
import logging

logger = logging.getLogger("RecordWise.LanguageDetector")


class LanguageDetector:
    def __init__(self):
        self.language_mappings = {
            "en": {"code": "en", "name": "English",   "native": "English",          "script": "latin"},
            "zh": {"code": "zh", "name": "Mandarin",  "native": "中文",             "script": "simplified"},
            "zh-CN": {
                "code": "zh-CN", "name": "Mandarin (Simplified Chinese)",
                "native": "普通话 (简体中文)", "script": "simplified",
            },
            "zh-TW": {
                "code": "zh-TW", "name": "Cantonese (Traditional Chinese)",
                "native": "粵語 (繁體中文)", "script": "traditional",
            },
            "yue": {
                "code": "yue", "name": "Cantonese (Traditional Chinese)",
                "native": "粵語 (繁體中文)", "script": "traditional",
            },
        }

    def detect_from_text(self, text: str) -> Tuple[str, Dict]:
        """
        Detect language from transcribed text using Unicode character analysis.
        Used as a fallback when Azure AI Speech does not return a dominant
        locale for the request (e.g. very short audio, all phrases below
        the confidence threshold).

        Returns: (language_code, language_info)
        """
        if not text or not text.strip():
            return "en", self._get_language_info("en")

        try:
            cjk_chars = re.findall(r"[\u4e00-\u9fff\u3400-\u4dbf]", text)
            traditional_markers = re.findall(
                # Only characters whose Unicode codepoint differs between
                # Traditional and Simplified Chinese (i.e. genuinely Traditional-only).
                # Removed: 目品展者面 — same codepoint in both scripts.
                r"[會議錄音內容總結討論決定時間問題項計劃執行報告建議團隊客戶產服務發組織"
                r"這體傳來說與對話頭長間歲裡邊後從給還顯愛讓連達號終電關話邊長]",
                text,
            )
            cantonese_markers = re.findall(r"[係唔喺咁嘅囉啫咪喎㗎]", text)

            total_chars = max(len(text.replace(" ", "")), 1)
            cjk_ratio = len(cjk_chars) / total_chars

            if cjk_ratio < 0.1:
                logger.info("📊 Text analysis: English (Latin dominant)")
                return "en", self._get_language_info("en")

            if cantonese_markers or len(traditional_markers) > len(cjk_chars) * 0.15:
                logger.info("📊 Text analysis: Cantonese / Traditional Chinese")
                return "yue", self._get_language_info("yue")

            logger.info("📊 Text analysis: Mandarin / Simplified Chinese")
            return "zh", self._get_language_info("zh")

        except Exception as e:
            logger.warning(f"Text-based language detection failed: {e}")
            return "en", self._get_language_info("en")

    def _get_language_info(self, language_code: str) -> Dict:
        """Get language information for a given language code"""
        return self.language_mappings.get(
            self._normalize_language_code(language_code),
            self.language_mappings["en"],
        )

    def _normalize_language_code(self, language_code: str) -> str:
        code = language_code.lower().strip()
        if code in ("english", "eng"):
            return "en"
        return code

    def should_use_traditional_chinese(self, language_code: str) -> bool:
        return self._get_language_info(language_code).get("script") == "traditional"

    def get_supported_languages(self) -> Dict:
        return {
            "languages": [
                {"code": "en",   "name": "English",   "native": "English",     "script": "latin"},
                {"code": "zh",   "name": "Mandarin",  "native": "中文 (简体)",  "script": "simplified"},
                {"code": "yue",  "name": "Cantonese", "native": "廣東話 (繁體)", "script": "traditional"},
                {"code": "auto", "name": "Auto",      "native": "Auto-detect", "script": "auto"},
            ]
        }
