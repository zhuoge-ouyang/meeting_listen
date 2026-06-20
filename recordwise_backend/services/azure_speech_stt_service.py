"""
RecordWise - Azure AI Speech Fast Transcription Service

Transcribes audio files using the Azure AI Speech Fast Transcription REST API.
The Fast Transcription API is a synchronous REST endpoint optimised for files
up to 2 hours long, with built-in speaker diarization and multi-locale
language identification.

Endpoint::

    POST https://{region}.api.cognitive.microsoft.com
        /speechtotext/transcriptions:transcribe?api-version=2024-11-15

Authentication
--------------
``Ocp-Apim-Subscription-Key: {AZURE_SPEECH_KEY}`` header.

Request body (multipart/form-data)
---------------------------------
* ``audio``      — the audio file (wav, mp3, m4a, opus, flac, ogg, ...)
* ``definition`` — JSON string with ``locales``, ``diarization``, etc.

Response (application/json)
---------------------------
* ``durationMilliseconds``  — total audio duration
* ``combinedPhrases[].text`` — full transcript joined per channel
* ``phrases[]`` — per-phrase items with ``speaker`` (int), ``offsetMilliseconds``,
  ``durationMilliseconds``, ``text``, ``locale``, ``confidence``, ``words[]``

This service consumes ``phrases`` to build a speaker-attributed transcript:

    Speaker 1: Hello there, thanks for joining today.
    Speaker 2: Glad to be here. Where shall we start?
    Speaker 1: Let's begin with the milestones for Q1.
"""

import asyncio
import json
import logging
import os
import subprocess
from typing import Any, Optional

import httpx
import imageio_ffmpeg

logger = logging.getLogger("RecordWise.AzureSpeechSTT")

_FFMPEG_BIN = imageio_ffmpeg.get_ffmpeg_exe()

# Status codes worth retrying. 429 = throttled; 5xx = transient server errors.
_RETRYABLE_STATUSES = {408, 429, 500, 502, 503, 504}
# How many times to attempt the call (initial attempt + retries).
# Fast Transcription "Resource Exhausted" 429s come from regional backend
# capacity, not from your account quota, and typically clear within 60-120s.
# We give 6 attempts so transient hot-region pressure has time to ease.
_MAX_ATTEMPTS = 6
# Cap individual back-off so we never sleep absurdly long.
_MAX_BACKOFF_SECONDS = 60.0
# Base seconds for exponential back-off when the service did NOT return a
# Retry-After header. Azure Speech hangs ~15s per attempt before returning a
# capacity-related 429, so a small base (e.g. 1.5s) just wastes attempts.
_BACKOFF_BASE_SECONDS = 5.0


class SpeechSTTError(RuntimeError):
    """Base error raised by :class:`AzureSpeechSTTService`."""

    def __init__(self, message: str, *, status_code: Optional[int] = None):
        super().__init__(message)
        self.status_code = status_code


class SpeechSTTThrottledError(SpeechSTTError):
    """Raised when Azure Speech returns 429 after all retries are exhausted."""

    def __init__(self, message: str, *, retry_after: Optional[float] = None):
        super().__init__(message, status_code=429)
        self.retry_after = retry_after

# ---------------------------------------------------------------------------
# Locale helpers
# ---------------------------------------------------------------------------

# App-level language code → Azure Speech BCP-47 locale (single-locale path).
#
# IMPORTANT: Cantonese is mapped to "zh-HK" (NOT "yue-CN").  The
# `yue-CN` locale is only supported by Batch Transcription (the `Submit`
# locale list); the Fast Transcription endpoint (`transcriptions:transcribe`)
# uses the `Transcribe` locale list, which exposes Cantonese as `zh-HK`.
# Sending `yue-CN` to Fast Transcription returns a misleading
# `HTTP 429 "Resource Exhausted"` after ~7 s instead of a proper
# `400 InvalidLocale` error.
_APP_TO_LOCALE = {
    "en":  "en-US",
    "zh":  "zh-CN",
    "yue": "zh-HK",
}

# When the app sends "auto" we use Azure's MULTI-LINGUAL model (empty
# `locales` list).  This is true code-switching transcription that handles
# mixed-language content within a single audio file.
#
# Why not "language identification" (passing multiple candidate locales)?
# Per the Fast Transcription docs, language ID is *designed to identify ONE
# main language locale per audio file* — segments in other languages get
# dropped.  That broke real users speaking Cantonese + English mid-sentence.
#
# CAVEAT: Azure's multi-lingual model supports de-DE, en-AU, en-CA, en-GB,
# en-IN, en-US, es-ES, es-MX, fr-CA, fr-FR, it-IT, ja-JP, ko-KR, pt-BR, and
# zh-CN.  **Cantonese (zh-HK) is NOT in this list.**  For Cantonese audio
# (mixed or otherwise), users must explicitly pick the "Cantonese" button
# in the UI, which sends `language=yue` and routes through the single-locale
# `zh-HK` path.
_AUTO_LOCALES: list[str] = []


def app_lang_to_locales(app_lang: Optional[str]) -> list[str]:
    """Translate an app-level language hint into Azure Speech locale list.

    Returns ``[]`` for "auto" — Azure interprets an empty/omitted ``locales``
    list as a request for the multi-lingual code-switching model.
    """
    if not app_lang or app_lang.lower() in ("auto", "detect", ""):
        return list(_AUTO_LOCALES)
    locale = _APP_TO_LOCALE.get(app_lang.lower())
    return [locale] if locale else list(_AUTO_LOCALES)


def locale_to_app_lang(locale: Optional[str]) -> str:
    """Map an Azure Speech locale back to the app language code."""
    if not locale:
        return "en"
    lower = locale.lower()
    if lower.startswith("yue"):
        return "yue"
    if lower.startswith("zh"):
        # zh-HK / zh-TW → Cantonese-style traditional; default to "zh".
        if lower in ("zh-hk", "zh-tw"):
            return "yue"
        return "zh"
    return "en"


# ---------------------------------------------------------------------------
# Audio helpers
# ---------------------------------------------------------------------------

def _probe_duration_seconds(audio_path: str) -> Optional[float]:
    """Return audio duration in seconds via ffprobe-style ffmpeg invocation."""
    cmd = [
        _FFMPEG_BIN,
        "-i", audio_path,
        "-hide_banner",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, check=False, timeout=15)
    except Exception:
        return None
    stderr = (proc.stderr or b"").decode("utf-8", "replace")
    for line in stderr.splitlines():
        # ffmpeg writes "  Duration: HH:MM:SS.xx, ..." on stderr.
        marker = "Duration:"
        if marker in line:
            tail = line.split(marker, 1)[1].split(",", 1)[0].strip()
            try:
                h, m, s = tail.split(":")
                return int(h) * 3600 + int(m) * 60 + float(s)
            except Exception:
                return None
    return None


# ---------------------------------------------------------------------------
# Speaker formatting
# ---------------------------------------------------------------------------

def _format_speaker_phrases(phrases: list, fallback_combined: str) -> str:
    """Convert ``phrases[]`` into a ``Speaker N: ...`` transcript."""
    if not phrases:
        return fallback_combined.strip()

    # Sort defensively by offset so out-of-order phrases serialise correctly.
    try:
        phrases = sorted(
            phrases,
            key=lambda p: p.get("offsetMilliseconds", 0) if isinstance(p, dict) else 0,
        )
    except Exception:
        pass

    lines: list = []
    last_speaker: Optional[int] = None
    buf: list = []

    for ph in phrases:
        if not isinstance(ph, dict):
            continue
        text = (ph.get("text") or "").strip()
        if not text:
            continue
        speaker = ph.get("speaker")
        # Azure Speech omits ``speaker`` when diarization is off / single
        # speaker detected.  Fall back to a single label.
        speaker_id = int(speaker) if isinstance(speaker, (int, float)) else 0
        if speaker_id == last_speaker:
            buf.append(text)
        else:
            if last_speaker is not None and buf:
                lines.append(f"Speaker {last_speaker + 1}: {' '.join(buf).strip()}")
            last_speaker = speaker_id
            buf = [text]

    if last_speaker is not None and buf:
        lines.append(f"Speaker {last_speaker + 1}: {' '.join(buf).strip()}")

    result = "\n".join(lines).strip()
    return result or fallback_combined.strip()


# ---------------------------------------------------------------------------
# Main service class
# ---------------------------------------------------------------------------

class AzureSpeechSTTService:
    """
    Thin async wrapper around the Azure AI Speech Fast Transcription REST API.

    Usage
    -----
        svc = AzureSpeechSTTService(speech_key, "eastus2")
        text, locale, duration = await svc.transcribe(
            audio_path, app_language="auto", max_speakers=4,
        )
    """

    DEFAULT_API_VERSION = "2024-11-15"

    def __init__(
        self,
        speech_key: str,
        region: str,
        api_version: str = DEFAULT_API_VERSION,
        endpoint_override: Optional[str] = None,
    ):
        if not speech_key:
            raise ValueError("AzureSpeechSTTService requires a Speech key")
        if not region and not endpoint_override:
            raise ValueError(
                "AzureSpeechSTTService requires either a region or an endpoint_override"
            )
        self.speech_key = speech_key
        self.region = region
        self.api_version = api_version
        self.endpoint_override = endpoint_override

    # ------------------------------------------------------------------
    # URL builder
    # ------------------------------------------------------------------

    @property
    def endpoint(self) -> str:
        if self.endpoint_override:
            base = self.endpoint_override.rstrip("/")
        else:
            base = f"https://{self.region}.api.cognitive.microsoft.com"
        return (
            f"{base}/speechtotext/transcriptions:transcribe"
            f"?api-version={self.api_version}"
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def transcribe(
        self,
        audio_path: str,
        app_language: Optional[str] = "auto",
        max_speakers: int = 4,
        profanity_filter_mode: str = "None",
        timeout_sec: int = 300,
    ) -> tuple[Optional[str], Optional[str], Optional[float]]:
        """
        Transcribe ``audio_path``.

        Returns ``(transcript_text, dominant_locale, duration_seconds)``.

        ``transcript_text`` contains inline speaker labels
        (``Speaker 1: ...\\nSpeaker 2: ...``) when diarization detects multiple
        speakers; otherwise it's a continuous transcript.

        On failure all three returned values are ``None``.
        """
        try:
            with open(audio_path, "rb") as fh:
                audio_bytes = fh.read()
        except Exception as exc:
            logger.error(f"Failed to read audio file {audio_path!r}: {exc}")
            return None, None, None

        if not audio_bytes:
            logger.error("Audio file is empty; aborting transcription request")
            return None, None, None

        locales = app_lang_to_locales(app_language)
        definition = {
            "locales": locales,
            "diarization": {
                "enabled": True,
                "maxSpeakers": int(max_speakers),
            },
            "profanityFilterMode": profanity_filter_mode,
        }
        logger.info(
            f"Calling Azure Speech Fast Transcription — locales={locales}, "
            f"diarize maxSpeakers={max_speakers}, audio bytes={len(audio_bytes):,}"
        )

        try:
            data = await asyncio.wait_for(
                self._post_multipart(audio_path, audio_bytes, definition),
                timeout=timeout_sec,
            )
        except asyncio.TimeoutError:
            logger.error(f"Azure Speech transcription timed out after {timeout_sec}s")
            return None, None, None
        except SpeechSTTError:
            # Typed errors (e.g. throttling) are surfaced to the caller so the
            # HTTP layer can return a meaningful status code.
            raise
        except Exception as exc:
            logger.error(f"Azure Speech transcription error: {exc}", exc_info=True)
            return None, None, None

        if data is None:
            return None, None, None

        return self._parse_response(data, audio_path)

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    async def _post_multipart(
        self, audio_path: str, audio_bytes: bytes, definition: dict
    ) -> Optional[dict]:
        """Issue the multipart POST and return parsed JSON, or None on error.

        Retries on 408 / 429 / 5xx with exponential back-off, honouring the
        ``Retry-After`` header when Azure provides one.  Raises
        :class:`SpeechSTTThrottledError` when all retries are exhausted on a
        429 response so the API layer can surface a 429 to the client.
        """
        filename = os.path.basename(audio_path) or "audio.wav"
        ext = os.path.splitext(filename)[1].lstrip(".").lower()
        mime = {
            "wav":  "audio/wav",
            "mp3":  "audio/mpeg",
            "m4a":  "audio/mp4",
            "mp4":  "audio/mp4",
            "webm": "audio/webm",
            "ogg":  "audio/ogg",
            "opus": "audio/ogg",
            "flac": "audio/flac",
        }.get(ext, "application/octet-stream")

        headers = {
            "Ocp-Apim-Subscription-Key": self.speech_key,
            "Accept":                     "application/json",
        }

        last_status: Optional[int] = None
        last_body: str = ""
        last_retry_after: Optional[float] = None

        async with httpx.AsyncClient(timeout=httpx.Timeout(300.0, connect=30.0)) as client:
            for attempt in range(1, _MAX_ATTEMPTS + 1):
                # ``files`` must be rebuilt every attempt because httpx consumes
                # the multipart streams on send.
                #
                # IMPORTANT: the multipart parts must be sent in this exact
                # order — ``audio`` FIRST, ``definition`` SECOND — and the
                # ``definition`` part MUST have NO ``Content-Type`` header
                # (pass ``None`` as the third tuple element). The Azure Speech
                # Fast Transcription gateway returns a misleading HTTP 429
                # ``Resource Exhausted`` after an ~8s hang if either rule is
                # violated. This matches the official curl example exactly.
                # We use a list of tuples (not a dict) so order is preserved.
                files_list = [
                    ("audio",      (filename, audio_bytes, mime)),
                    ("definition", (None, json.dumps(definition), None)),
                ]
                try:
                    resp = await client.post(
                        self.endpoint, headers=headers, files=files_list
                    )
                except httpx.RequestError as exc:
                    # Network-level failure (DNS, conn reset, ...) — retry.
                    last_status, last_body = None, str(exc)
                    if attempt >= _MAX_ATTEMPTS:
                        logger.error(
                            f"Azure Speech network error after {attempt} attempt(s): {exc}"
                        )
                        raise SpeechSTTError(f"Network error: {exc}") from exc
                    backoff = self._compute_backoff(attempt, None)
                    logger.warning(
                        f"Azure Speech network error on attempt {attempt}: {exc}; "
                        f"retrying in {backoff:.1f}s"
                    )
                    await asyncio.sleep(backoff)
                    continue

                status = resp.status_code
                if status < 400:
                    try:
                        return resp.json()
                    except Exception as exc:
                        logger.error(f"Failed to parse Azure Speech JSON response: {exc}")
                        return None

                last_status = status
                last_body = (resp.text or "")[:500]
                last_retry_after = self._parse_retry_after(resp.headers.get("Retry-After"))

                if status in _RETRYABLE_STATUSES and attempt < _MAX_ATTEMPTS:
                    backoff = self._compute_backoff(attempt, last_retry_after)
                    logger.warning(
                        f"Azure Speech HTTP {status} on attempt {attempt}/{_MAX_ATTEMPTS} "
                        f"(retry-after={last_retry_after}); body={last_body!r}; "
                        f"retrying in {backoff:.1f}s"
                    )
                    await asyncio.sleep(backoff)
                    continue

                # Non-retryable error or out of retries.
                logger.error(f"Azure Speech HTTP {status}: {last_body}")
                if status == 429:
                    raise SpeechSTTThrottledError(
                        "Azure AI Speech rate limit exceeded after "
                        f"{attempt} attempt(s). Body: {last_body}",
                        retry_after=last_retry_after,
                    )
                resp.raise_for_status()
                return None  # unreachable; raise_for_status already raised

        # Loop exited without returning — only happens when all retries failed
        # on a retryable status code (e.g. persistent 429).
        if last_status == 429:
            raise SpeechSTTThrottledError(
                f"Azure AI Speech rate limit exceeded after {_MAX_ATTEMPTS} attempts. "
                f"Body: {last_body}",
                retry_after=last_retry_after,
            )
        raise SpeechSTTError(
            f"Azure AI Speech request failed after {_MAX_ATTEMPTS} attempts "
            f"(last status={last_status}, body={last_body!r})",
            status_code=last_status,
        )

    @staticmethod
    def _parse_retry_after(value: Optional[str]) -> Optional[float]:
        """Parse a ``Retry-After`` header value (seconds-only is supported)."""
        if not value:
            return None
        try:
            seconds = float(value.strip())
            if seconds < 0:
                return None
            return seconds
        except ValueError:
            # HTTP-date form is permitted by RFC 9110 but Azure Speech sends
            # delta-seconds; we ignore the date form to avoid pulling in extra
            # parsing dependencies.
            return None

    @staticmethod
    def _compute_backoff(attempt: int, retry_after: Optional[float]) -> float:
        """Exponential back-off with light jitter, honouring ``Retry-After``."""
        # Azure's hint always wins when present.
        if retry_after is not None and retry_after > 0:
            return min(retry_after, _MAX_BACKOFF_SECONDS)
        # 5s, 10s, 20s, 40s, 60s, 60s ... capped at _MAX_BACKOFF_SECONDS.
        base = min(
            _BACKOFF_BASE_SECONDS * (2 ** (attempt - 1)),
            _MAX_BACKOFF_SECONDS,
        )
        # Small deterministic jitter so concurrent callers don't sync-up.
        jitter = 0.25 * (attempt % 3)
        return base + jitter

    def _parse_response(
        self, data: dict, audio_path: str
    ) -> tuple[Optional[str], Optional[str], Optional[float]]:
        """Extract transcript text, dominant locale, and duration from JSON."""
        phrases = data.get("phrases") or []
        combined = data.get("combinedPhrases") or []
        combined_text = ""
        if combined and isinstance(combined, list):
            first = combined[0]
            if isinstance(first, dict):
                combined_text = (first.get("text") or "").strip()

        transcript = _format_speaker_phrases(phrases, combined_text)

        # Pick the most common locale across phrases as the "dominant" locale
        # so the chat/summary step can render the right script.
        dominant_locale: Optional[str] = None
        locale_counts: dict = {}
        for ph in phrases:
            if isinstance(ph, dict):
                loc = ph.get("locale")
                if loc:
                    locale_counts[loc] = locale_counts.get(loc, 0) + 1
        if locale_counts:
            dominant_locale = max(locale_counts.items(), key=lambda kv: kv[1])[0]

        duration_ms = data.get("durationMilliseconds")
        duration_seconds: Optional[float] = None
        if isinstance(duration_ms, (int, float)) and duration_ms > 0:
            duration_seconds = float(duration_ms) / 1000.0
        else:
            duration_seconds = _probe_duration_seconds(audio_path)

        speaker_count = len({
            ph.get("speaker") for ph in phrases
            if isinstance(ph, dict) and ph.get("speaker") is not None
        })
        logger.info(
            f"Azure Speech transcription: {len(phrases)} phrase(s), "
            f"{speaker_count} speaker(s), dominant locale={dominant_locale!r}, "
            f"duration={duration_seconds!r}s, {len(transcript)} chars"
        )
        if transcript:
            logger.info(f"Transcript preview: {transcript[:160]!r}")

        return transcript or None, dominant_locale, duration_seconds
