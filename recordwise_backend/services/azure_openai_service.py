"""
RecordWise Azure OpenAI Integration — chat / summarisation only.

Speech-to-text is handled by :class:`AzureSpeechSTTService` (Azure AI
Speech Fast Transcription).  This service is responsible solely for
transcript post-processing (Chinese script normalisation) and AI summary
generation via Azure OpenAI Chat Completions (default deployment
``gpt-5.1``).

``gpt-5.1`` (and newer 5.x reasoning models) is invoked via the standard
Chat Completions API.  This codebase uses ``max_completion_tokens`` (not
the legacy ``max_tokens``) so it works with the GPT-5 family without
code changes.  Tested with Azure OpenAI ``api-version`` ``2024-12-01-preview``
and ``2025-04-01-preview``.
"""

import asyncio
import logging
import os
import re
import sys
from typing import Dict, Optional

from openai import AzureOpenAI
try:
    # Available since openai>=1.0.  Used to surface Azure OpenAI HTTP error
    # details (status_code, response body) in backend logs.
    from openai import APIStatusError
except ImportError:  # pragma: no cover - older openai SDK
    APIStatusError = None  # type: ignore[assignment]

# Add parent directory to path for absolute imports
sys.path.append(os.path.dirname(os.path.dirname(__file__)))
from utils.config import get_settings
from services.language_detector import LanguageDetector

try:
    from opencc import OpenCC  # opencc-python-reimplemented (pure Python)
    _S2T = OpenCC("s2t")
    _T2S = OpenCC("t2s")
except Exception as _exc:  # pragma: no cover - opencc is optional but recommended
    _S2T = None
    _T2S = None
    logging.getLogger("RecordWise.AzureOpenAI").warning(
        "opencc not available; Chinese script conversion will be a no-op (%s)", _exc
    )

logger = logging.getLogger("RecordWise.AzureOpenAI")
settings = get_settings()


# Canonical meeting-type IDs accepted by the API plus localized display labels
# used inside the gpt-5.1 system / user prompts.  Without these, Chinese
# prompts would interpolate the raw English ID (e.g. "請分析這個interview"),
# which is awkward and slightly degrades summary quality.
_MEETING_TYPE_LABELS: Dict[str, Dict[str, str]] = {
    "meeting":    {"en": "meeting",                "hant": "會議",       "hans": "会议"},
    "interview":  {"en": "interview",              "hant": "訪談",       "hans": "访谈"},
    "lecture":    {"en": "lecture",                "hant": "講座",       "hans": "讲座"},
    "call":       {"en": "call",                   "hant": "通話",       "hans": "通话"},
    "chat":       {"en": "chat",                   "hant": "對話",       "hans": "对话"},
    "brainstorm": {"en": "brainstorming session",  "hant": "腦力激盪",   "hans": "头脑风暴"},
}


def _meeting_type_label(meeting_type: str, script: str) -> str:
    """Return the localized display label for a meeting type.

    `script` is one of "hant" (traditional Chinese), "hans" (simplified
    Chinese) or anything else (treated as English).  Unknown meeting types
    fall back to the raw input so the prompt still reads sensibly.
    """
    entry = _MEETING_TYPE_LABELS.get((meeting_type or "").lower())
    if not entry:
        return meeting_type
    if script == "hant":
        return entry["hant"]
    if script == "hans":
        return entry["hans"]
    return entry["en"]


class AzureOpenAIService:
    """Azure OpenAI chat client used to generate meeting summaries."""

    def __init__(
        self,
        override_endpoint: Optional[str] = None,
        override_api_key: Optional[str] = None,
        override_chat_deployment: Optional[str] = None,
    ):
        endpoint = override_endpoint or settings.AZURE_OPENAI_ENDPOINT
        api_key  = override_api_key  or settings.AZURE_OPENAI_API_KEY

        self.client = AzureOpenAI(
            azure_endpoint=endpoint,
            api_key=api_key,
            api_version=settings.AZURE_OPENAI_API_VERSION,
        )
        self.chat_model = override_chat_deployment or settings.AZURE_OPENAI_CHAT_DEPLOYMENT
        self.language_detector = LanguageDetector()

    # ------------------------------------------------------------------
    # Health
    # ------------------------------------------------------------------

    async def health_check(self) -> str:
        """Check Azure OpenAI chat service health."""
        try:
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(
                None,
                lambda: self.client.chat.completions.create(
                    model=self.chat_model,
                    messages=[{"role": "user", "content": "ping"}],
                    max_completion_tokens=1,
                ),
            )
            return "operational"
        except Exception as e:
            self._log_openai_exception("Azure OpenAI health check failed", e)
            return "unavailable"

    # ------------------------------------------------------------------
    # Transcript post-processing (Chinese script normalisation)
    # ------------------------------------------------------------------

    def post_process_transcription(
        self, transcription: str, detected_language_code: str
    ) -> str:
        """Normalise Chinese script (Simplified ↔ Traditional) where needed."""
        try:
            language_info = self.language_detector._get_language_info(detected_language_code)
            if language_info.get("script") == "traditional":
                logger.info("🔄 Applied Traditional Chinese character conversion")
                return self._convert_to_traditional_chinese(transcription)
            if language_info.get("script") == "simplified":
                logger.info("🔄 Applied Simplified Chinese character conversion")
                return self._convert_to_simplified_chinese(transcription)
            return transcription
        except Exception as e:
            logger.warning(f"Post-processing failed: {e}")
            return transcription

    def _convert_to_traditional_chinese(self, text: str) -> str:
        if _S2T is None:
            return text
        return _S2T.convert(text)

    def _convert_to_simplified_chinese(self, text: str) -> str:
        if _T2S is None:
            return text
        return _T2S.convert(text)

    # ------------------------------------------------------------------
    # Summary generation
    # ------------------------------------------------------------------

    async def generate_comprehensive_summary(
        self,
        transcript: str,
        meeting_type: str,
        meeting_title: Optional[str] = None,
        participants: Optional[str] = None,
        language_info: Optional[Dict] = None,
    ) -> Dict:
        """Generate a comprehensive meeting summary in the appropriate language."""
        try:
            if language_info:
                summary_language = language_info.get("code", "en")
                language_name    = language_info.get("name", "English")
                script_type      = language_info.get("script", "latin")
            else:
                summary_language = "en"
                language_name    = "English"
                script_type      = "latin"

            logger.info(f"🌐 Generating summary in {language_name} ({summary_language})")

            system_prompt = self._get_language_aware_summary_prompt(
                meeting_type, summary_language, script_type
            )
            user_content = self._format_user_content_for_language(
                transcript, meeting_type, meeting_title, participants, summary_language
            )

            loop = asyncio.get_event_loop()
            completion = await loop.run_in_executor(
                None,
                lambda: self.client.chat.completions.create(
                    model=self.chat_model,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user",   "content": user_content},
                    ],
                    max_completion_tokens=2000,
                    temperature=0.2,
                ),
            )

            response_text  = completion.choices[0].message.content
            parsed_summary = self._parse_summary_response(response_text)

            logger.info(f"✅ Summary generated in {language_name}")
            return parsed_summary

        except Exception as e:
            self._log_openai_exception(
                f"Summary generation failed (model={self.chat_model!r}, "
                f"language={language_name!r}, transcript_chars={len(transcript)})",
                e,
            )
            return {
                "summary": f"Summary generation failed: {str(e)}",
                "action_items": [],
                "key_points": [],
                "full_analysis": "",
                "_error": {
                    "type": type(e).__name__,
                    "message": str(e),
                    "status_code": getattr(e, "status_code", None),
                },
            }

    # ------------------------------------------------------------------
    # Error logging helper
    # ------------------------------------------------------------------

    def _log_openai_exception(self, context: str, exc: Exception) -> None:
        """Log an Azure OpenAI exception with full HTTP details + traceback.

        The OpenAI SDK raises subclasses of ``APIStatusError`` for HTTP
        4xx/5xx responses; those carry ``.status_code``, ``.response`` and
        ``.body`` attributes with the JSON error envelope returned by Azure
        (e.g. the ``unsupported_parameter`` / ``max_tokens`` payload).  We
        surface those fields here so backend logs contain enough info to
        diagnose without round-tripping through the frontend.
        """
        if APIStatusError is not None and isinstance(exc, APIStatusError):
            status = getattr(exc, "status_code", None)
            body = getattr(exc, "body", None)
            request_id = None
            response = getattr(exc, "response", None)
            if response is not None:
                try:
                    request_id = response.headers.get("x-request-id") or \
                        response.headers.get("apim-request-id")
                except Exception:
                    request_id = None
            logger.error(
                "%s: HTTP %s | request_id=%s | body=%r",
                context, status, request_id, body,
            )
        else:
            # Non-HTTP exception (network, timeout, programming error).
            logger.exception("%s: %s", context, exc)

    # ------------------------------------------------------------------
    # Prompt builders
    # ------------------------------------------------------------------

    def _get_language_aware_summary_prompt(
        self, meeting_type: str, language_code: str, script_type: str
    ) -> str:
        """Get language-specific system prompt for summary generation."""
        if language_code.startswith("zh") or script_type in ("traditional", "simplified"):
            if script_type == "traditional":
                mt_label = _meeting_type_label(meeting_type, "hant")
                return f"""你是 RecordWise AI，專業的會議分析專家。請用繁體中文分析這個{mt_label}。

請提供結構化的分析：

## 執行摘要
簡述2-3句會議目的和結果。

## 主要討論要點
- 討論的主要議題
- 作出的重要決定
- 提及的技術細節

## 行動項目
- 具體任務及負責人員
- 如有提及截止日期
- 優先級別

## 後續步驟
- 需要的跟進行動
- 計劃的未來會議
- 已識別的依賴關係

請用這些確切的標題格式回應。"""
            else:
                mt_label = _meeting_type_label(meeting_type, "hans")
                return f"""你是 RecordWise AI，专业的会议分析专家。请用简体中文分析这个{mt_label}。

请提供结构化的分析：

## 执行摘要
简述2-3句会议目的和结果。

## 主要讨论要点
- 讨论的主要议题
- 作出的重要决定
- 提及的技术细节

## 行动项目
- 具体任务及负责人员
- 如有提及截止日期
- 优先级别

## 后续步骤
- 需要的跟进行动
- 计划的未来会议
- 已识别的依赖关系

请用这些确切的标题格式回应。"""
        else:
            mt_label = _meeting_type_label(meeting_type, "en")
            return f"""You are RecordWise AI, an expert meeting analyst. Provide structured analysis in English.

Analyze this {mt_label} and provide:

## EXECUTIVE SUMMARY
Brief 2-3 sentence overview of the meeting's purpose and outcomes.

## KEY DISCUSSION POINTS
- Main topics discussed
- Important decisions made
- Technical details mentioned

## ACTION ITEMS
- Specific tasks with responsible parties
- Deadlines if mentioned
- Priority levels

## NEXT STEPS
- Follow-up actions required
- Future meetings planned
- Dependencies identified

Format your response with these exact headings."""

    def _format_user_content_for_language(
        self,
        transcript: str,
        meeting_type: str,
        meeting_title: Optional[str],
        participants: Optional[str],
        language_code: str,
    ) -> str:
        """Format user content based on language."""
        if language_code.startswith("zh") or language_code == "yue":
            trad = (language_code == "yue" or language_code == "zh-TW")
            mt_label = _meeting_type_label(meeting_type, "hant" if trad else "hans")
            return f"""{"會議標題" if trad else "会议标题"}: {meeting_title or "未命名"}
{"會議類型" if trad else "会议类型"}: {mt_label}
{"參與者" if trad else "参与者"}: {participants or "未指定"}

{"會議記錄" if trad else "会议记录"}:
{transcript}

{"請分析這個" if trad else "请分析这个"}{mt_label}{"並提供結構化摘要" if trad else "并提供结构化摘要"}。"""
        else:
            mt_label = _meeting_type_label(meeting_type, "en")
            return f"""Meeting Title: {meeting_title or "Untitled"}
Meeting Type: {mt_label}
Participants: {participants or "Not specified"}

Transcript:
{transcript}

Please analyze this {mt_label} and provide a structured summary."""

    # ------------------------------------------------------------------
    # Response parser
    # ------------------------------------------------------------------

    def _parse_summary_response(self, response_text: str) -> Dict:
        """Parse the structured summary response into a dict."""
        lines = response_text.split("\n")

        summary_lines: list[str] = []
        action_items = []
        key_points   = []
        current_section = None

        # Map Chinese section headings to their English canonical names
        _CN_HEADING = {
            "執行摘要":    "EXECUTIVE SUMMARY",
            "执行摘要":    "EXECUTIVE SUMMARY",
            "主要討論要點": "KEY DISCUSSION POINTS",
            "主要讨论要点": "KEY DISCUSSION POINTS",
            "行動項目":    "ACTION ITEMS",
            "行动项目":    "ACTION ITEMS",
            "後續步驟":    "NEXT STEPS",
            "后续步骤":    "NEXT STEPS",
        }

        # Match common bullet styles: "- ", "* ", "• ", "· ", and numbered
        # ("1.", "1)", "(1)").  gpt-5.1 sometimes prefers "*" or numbered
        # bullets even when the prompt asks for "-", so we accept all three.
        _BULLET_RE = re.compile(r"^\s*(?:[-*\u2022\u00b7]|\(?\d+[\.\)])\s+(.*)$")

        for line in lines:
            line = line.strip()
            if not line:
                continue
            if line.startswith("## "):
                raw_heading = line[3:].strip()
                # Strip optional numbered prefixes like "1. EXECUTIVE SUMMARY"
                raw_heading = re.sub(r"^\(?\d+[\.\)]\s*", "", raw_heading).strip()
                current_section = _CN_HEADING.get(raw_heading, raw_heading.upper())
                continue
            bullet_match = _BULLET_RE.match(line)
            if current_section == "EXECUTIVE SUMMARY":
                summary_lines.append(line)
            elif current_section == "ACTION ITEMS" and bullet_match:
                action_items.append(bullet_match.group(1).strip())
            elif current_section in ("KEY DISCUSSION POINTS", "KEY POINTS") and bullet_match:
                key_points.append(bullet_match.group(1).strip())

        summary = "\n".join(summary_lines).strip()

        return {
            "summary":      summary or response_text[:300] + "...",
            "action_items": action_items[:10],
            "key_points":   key_points[:10],
            "full_analysis": response_text,
        }
