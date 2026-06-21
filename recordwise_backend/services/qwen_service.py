"""Qwen summary, translation and TTS service wrappers."""

from __future__ import annotations

import asyncio
import hashlib
import logging
import os
from pathlib import Path
from typing import Any

import httpx
from openai import OpenAI

from services.meeting_analysis import (
    ActionItem,
    TranscriptSegment,
    build_summary_prompt,
    normalize_action_items,
    parse_summary_payload,
    render_meeting_minutes,
)


logger = logging.getLogger("RecordWise.Qwen")


LANGUAGE_MAP = {
    "english": ("English", "English", "Neil"),
    "japanese": ("Japanese", "Japanese", "Neil"),
    "cantonese": ("Cantonese", "Chinese", "Kiki"),
    "mandarin": ("Chinese", "Chinese", "Neil"),
    "french": ("French", "French", "Neil"),
}


class QwenService:
    def __init__(
        self,
        *,
        api_key: str | None,
        compatible_base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1",
        dashscope_base_url: str = "https://dashscope.aliyuncs.com/api/v1",
        summary_model: str = "qwen3.7-max",
        mt_model: str = "qwen-mt-flash",
        tts_model: str = "qwen3-tts-flash",
        audio_cache_dir: str = "storage/tts",
    ) -> None:
        self.api_key = api_key
        self.compatible_base_url = compatible_base_url.rstrip("/")
        self.dashscope_base_url = dashscope_base_url.rstrip("/")
        self.summary_model = summary_model
        self.mt_model = mt_model
        self.tts_model = tts_model
        self.audio_cache_dir = Path(audio_cache_dir)
        self._client = OpenAI(
            api_key=api_key or "missing",
            base_url=self.compatible_base_url,
        )

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    async def generate_minutes(
        self,
        *,
        meeting_title: str | None,
        participant_names: str | None,
        segments: list[TranscriptSegment],
        template_text: str | None = None,
        module: str = "default",
    ) -> dict[str, Any]:
        if not self.configured:
            raise RuntimeError("DASHSCOPE_API_KEY is not configured.")
        prompt = build_summary_prompt(
            meeting_title=meeting_title,
            participant_names=participant_names,
            segments=segments,
            template_text=template_text,
            module=module,
        )
        loop = asyncio.get_event_loop()
        completion = await loop.run_in_executor(
            None,
            lambda: self._client.chat.completions.create(
                model=self.summary_model,
                messages=[
                    {
                        "role": "system",
                        "content": "你是严谨的会议纪要整理助手，只输出用户要求的 JSON。",
                    },
                    {"role": "user", "content": prompt},
                ],
                temperature=0.1,
            ),
        )
        raw = completion.choices[0].message.content or ""
        payload = parse_summary_payload(raw)
        action_items = normalize_action_items(payload.get("action_items") or [])
        summary_text = str(payload.get("summary_text") or "").strip()
        if not summary_text:
            summary_text = render_meeting_minutes(
                meeting_time=str(payload.get("meeting_time") or ""),
                participants=[str(v) for v in (payload.get("participants") or [])],
                minutes=[str(v) for v in (payload.get("minutes") or [])],
                action_items=action_items,
            )
        return {
            "summary": summary_text,
            "minutes": [str(v) for v in (payload.get("minutes") or [])],
            "participants": [str(v) for v in (payload.get("participants") or [])],
            "meeting_time": str(payload.get("meeting_time") or ""),
            "action_items": [item.as_dict() for item in action_items],
            "raw": raw,
        }

    async def translate_and_tts(
        self,
        *,
        text: str,
        target_language: str,
        meeting_id: str,
    ) -> dict[str, Any]:
        if not self.configured:
            raise RuntimeError("DASHSCOPE_API_KEY is not configured.")
        target_key = target_language.lower().strip()
        if target_key not in LANGUAGE_MAP:
            raise ValueError(f"Unsupported target language: {target_language}")
        mt_target, tts_language, voice = LANGUAGE_MAP[target_key]
        translated = await self.translate(text=text, target_language=mt_target)
        audio_path = await self.synthesize(
            text=translated,
            language_type=tts_language,
            voice=voice,
            meeting_id=meeting_id,
            target_language=target_key,
        )
        return {
            "translated_text": translated,
            "audio_url": f"/api/tts-audio/{audio_path.name}",
            "voice": voice,
            "language": target_key,
            "status": "completed",
        }

    async def translate(self, *, text: str, target_language: str) -> str:
        loop = asyncio.get_event_loop()
        completion = await loop.run_in_executor(
            None,
            lambda: self._client.chat.completions.create(
                model=self.mt_model,
                messages=[{"role": "user", "content": text}],
                extra_body={
                    "translation_options": {
                        "source_lang": "auto",
                        "target_lang": target_language,
                    }
                },
            ),
        )
        return (completion.choices[0].message.content or "").strip()

    async def synthesize(
        self,
        *,
        text: str,
        language_type: str,
        voice: str,
        meeting_id: str,
        target_language: str,
    ) -> Path:
        self.audio_cache_dir.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256(f"{meeting_id}|{target_language}|{voice}|{text}".encode()).hexdigest()
        target_path = self.audio_cache_dir / f"{digest}.wav"
        if target_path.exists() and target_path.stat().st_size > 0:
            return target_path

        body = {
            "model": self.tts_model,
            "input": {
                "text": text,
                "voice": voice,
                "language_type": language_type,
            },
        }
        async with httpx.AsyncClient(timeout=120) as client:
            response = await client.post(
                f"{self.dashscope_base_url}/services/aigc/multimodal-generation/generation",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                json=body,
            )
            response.raise_for_status()
            payload = response.json()
            audio_url = (((payload.get("output") or {}).get("audio") or {}).get("url"))
            if not audio_url:
                raise RuntimeError(f"Qwen-TTS did not return audio URL: {payload}")
            audio_response = await client.get(audio_url)
            audio_response.raise_for_status()
        target_path.write_bytes(audio_response.content)
        return target_path
