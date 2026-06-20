"""DashScope Fun-ASR recorded-file transcription with diarization."""

from __future__ import annotations

import asyncio
import logging
from typing import Any

import httpx

from services.meeting_analysis import TranscriptSegment


logger = logging.getLogger("RecordWise.AliyunASR")


class AliyunASRService:
    def __init__(
        self,
        *,
        api_key: str | None,
        base_url: str = "https://dashscope.aliyuncs.com/api/v1",
        model: str = "fun-asr",
    ) -> None:
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.model = model

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    async def transcribe(
        self,
        file_url: str,
        *,
        language_hints: list[str] | None = None,
        speaker_count: int | None = None,
        timeout_seconds: int = 1800,
    ) -> tuple[list[TranscriptSegment], dict[str, Any]]:
        if not self.configured:
            raise RuntimeError("DASHSCOPE_API_KEY is not configured.")
        task_id = await self._submit_task(
            file_url,
            language_hints=language_hints or ["zh", "en"],
            speaker_count=speaker_count,
        )
        task = await self._wait_for_task(task_id, timeout_seconds=timeout_seconds)
        result_url = self._extract_transcription_url(task)
        payload = await self._download_json(result_url)
        return self._parse_segments(payload), payload

    async def _submit_task(
        self,
        file_url: str,
        *,
        language_hints: list[str],
        speaker_count: int | None,
    ) -> str:
        parameters: dict[str, Any] = {
            "channel_id": [0],
            "language_hints": language_hints,
            "diarization_enabled": True,
            "enable_words": True,
        }
        if speaker_count is not None:
            parameters["speaker_count"] = speaker_count
        body = {
            "model": self.model,
            "input": {"file_urls": [file_url]},
            "parameters": parameters,
        }
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                f"{self.base_url}/services/audio/asr/transcription",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                    "X-DashScope-Async": "enable",
                },
                json=body,
            )
        response.raise_for_status()
        payload = response.json()
        task_id = (payload.get("output") or {}).get("task_id")
        if not task_id:
            raise RuntimeError(f"DashScope ASR did not return task_id: {payload}")
        return str(task_id)

    async def _wait_for_task(
        self, task_id: str, *, timeout_seconds: int
    ) -> dict[str, Any]:
        deadline = asyncio.get_event_loop().time() + timeout_seconds
        async with httpx.AsyncClient(timeout=60) as client:
            while True:
                response = await client.get(
                    f"{self.base_url}/tasks/{task_id}",
                    headers={
                        "Authorization": f"Bearer {self.api_key}",
                        "X-DashScope-Async": "enable",
                        "Content-Type": "application/json",
                    },
                )
                response.raise_for_status()
                payload = response.json()
                status = ((payload.get("output") or {}).get("task_status") or "").upper()
                if status == "SUCCEEDED":
                    return payload
                if status in {"FAILED", "UNKNOWN"}:
                    raise RuntimeError(f"DashScope ASR task {task_id} failed: {payload}")
                if asyncio.get_event_loop().time() > deadline:
                    raise TimeoutError(f"DashScope ASR task {task_id} timed out")
                await asyncio.sleep(3)

    @staticmethod
    def _extract_transcription_url(task_payload: dict[str, Any]) -> str:
        output = task_payload.get("output") or {}
        results = output.get("results") or []
        if results and isinstance(results, list):
            url = results[0].get("transcription_url")
            if url:
                return str(url)
        result = output.get("result") or {}
        url = result.get("transcription_url")
        if url:
            return str(url)
        raise RuntimeError(f"DashScope ASR result did not include transcription_url: {task_payload}")

    @staticmethod
    async def _download_json(url: str) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=120) as client:
            response = await client.get(url)
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict):
            raise RuntimeError("DashScope ASR transcription payload is not a JSON object.")
        return payload

    @staticmethod
    def _parse_segments(payload: dict[str, Any]) -> list[TranscriptSegment]:
        transcripts = payload.get("transcripts") or []
        segments: list[TranscriptSegment] = []
        for transcript in transcripts:
            for sentence in transcript.get("sentences") or []:
                text = str(sentence.get("text") or "").strip()
                if not text:
                    continue
                speaker = sentence.get("speaker_id", sentence.get("speaker"))
                speaker_id = f"speaker_{speaker}" if speaker is not None else "speaker_1"
                segments.append(
                    TranscriptSegment(
                        speaker_id=speaker_id,
                        start_ms=int(sentence.get("begin_time") or sentence.get("start_time") or 0),
                        end_ms=int(sentence.get("end_time") or 0),
                        text=text,
                    )
                )
        if segments:
            return segments

        # Fallback for compact result payloads.
        text = ""
        for transcript in transcripts:
            text = str(transcript.get("text") or "").strip()
            if text:
                break
        if text:
            return [TranscriptSegment("speaker_1", 0, 0, text)]
        return []
