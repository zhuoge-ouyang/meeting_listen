"""RecordWise fork backend.

Primary pipeline:
    upload audio -> normalize -> OSS URL -> DashScope ASR with diarization
    -> Qwen meeting minutes/action items -> optional Qwen-MT + Qwen-TTS.
"""

from __future__ import annotations

from datetime import datetime
import logging
import os
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Optional, Any

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

sys.path.append(os.path.dirname(os.path.dirname(__file__)))

from models.transcription import (  # noqa: E402
    LanguageInfo,
    MeetingTitleRequest,
    SpeakerAliasRequest,
    SummaryRegenerateRequest,
    TranscriptionResponse,
    TranslateTTSRequest,
    TranslateTTSResponse,
)
from services.aliyun_asr_service import AliyunASRService  # noqa: E402
from services.aliyun_oss_service import AliyunOSSService  # noqa: E402
from services.audio_processor import AudioProcessingError, AudioProcessor  # noqa: E402
from services.meeting_analysis import (  # noqa: E402
    TranscriptSegment,
    parse_speaker_lines,
    render_meeting_minutes,
    resolve_translation_source_text,
    transcript_text_from_segments,
)
from services.qwen_service import QwenService  # noqa: E402
from utils.config import get_settings  # noqa: E402


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("RecordWise")
settings = get_settings()

_VALID_MEETING_TYPES = frozenset(
    {"meeting", "interview", "lecture", "call", "chat", "brainstorm"}
)

app = FastAPI(
    title="RecordWise API",
    description="Meeting recording, diarized transcription, minutes, tasks and translation TTS.",
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

audio_processor = AudioProcessor()
oss_service = AliyunOSSService(
    access_key_id=settings.ALIYUN_ACCESS_KEY_ID,
    access_key_secret=settings.ALIYUN_ACCESS_KEY_SECRET,
    endpoint=settings.ALIYUN_OSS_ENDPOINT,
    bucket_name=settings.ALIYUN_OSS_BUCKET,
    public_base_url=settings.ALIYUN_OSS_PUBLIC_BASE_URL,
    expire_seconds=settings.ALIYUN_OSS_SIGNED_URL_EXPIRE_SECONDS,
)
asr_service = AliyunASRService(
    api_key=settings.DASHSCOPE_API_KEY,
    base_url=settings.DASHSCOPE_BASE_URL,
    model=settings.ALIYUN_ASR_MODEL,
)
qwen_service = QwenService(
    api_key=settings.DASHSCOPE_API_KEY,
    compatible_base_url=settings.DASHSCOPE_COMPATIBLE_BASE_URL,
    dashscope_base_url=settings.DASHSCOPE_BASE_URL,
    summary_model=settings.QWEN_SUMMARY_MODEL,
    mt_model=settings.QWEN_MT_MODEL,
    tts_model=settings.QWEN_TTS_MODEL,
    audio_cache_dir=settings.TTS_AUDIO_CACHE_DIR,
)

_MEETING_STORE: dict[str, dict[str, Any]] = {}
_TRANSLATION_CACHE: dict[str, dict[str, Any]] = {}


def optional_verify_token(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(
        HTTPBearer(auto_error=False)
    ),
):
    if not settings.REQUIRE_AUTH:
        return None
    if credentials is None or credentials.credentials != settings.API_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return credentials.credentials


@app.get("/")
async def root():
    return {
        "app": "RecordWise",
        "version": "2.0.0",
        "powered_by": "Aliyun DashScope Fun-ASR/Paraformer + Qwen",
        "docs": "/docs",
        "status": "operational",
    }


@app.get("/api/test")
async def test_endpoint():
    return {"status": "Backend is working!", "timestamp": datetime.now().isoformat()}


@app.get("/api/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "services": {
            "dashscope": "configured" if qwen_service.configured else "missing_key",
            "aliyun_oss": "configured" if oss_service.configured else "missing_config",
            "audio_processor": "operational",
        },
    }


@app.post("/api/meetings", response_model=TranscriptionResponse)
async def create_meeting(
    audio_file: UploadFile = File(...),
    meeting_type: str = Form(default="meeting"),
    language: str = Form(default="zh"),
    meeting_title: Optional[str] = Form(default=None),
    participant_names: Optional[str] = Form(default=None),
    generate_summary: bool = Form(default=True),
    _token: Optional[str] = Depends(optional_verify_token),
):
    return await _process_audio_upload(
        audio_file=audio_file,
        meeting_type=meeting_type,
        language=language,
        meeting_title=meeting_title,
        participant_names=participant_names,
        generate_summary=generate_summary,
    )


@app.post("/api/transcribe-recording", response_model=TranscriptionResponse)
async def transcribe_recording(
    audio_file: UploadFile = File(...),
    meeting_type: str = Form(default="meeting"),
    language: str = Form(default="zh"),
    meeting_title: Optional[str] = Form(default=None),
    participant_names: Optional[str] = Form(default=None),
    generate_summary: bool = Form(default=True),
    _token: Optional[str] = Depends(optional_verify_token),
):
    """Backward-compatible endpoint used by the imported Flutter app."""
    return await _process_audio_upload(
        audio_file=audio_file,
        meeting_type=meeting_type,
        language=language,
        meeting_title=meeting_title,
        participant_names=participant_names,
        generate_summary=generate_summary,
    )


@app.get("/api/meetings/{meeting_id}")
async def get_meeting(
    meeting_id: str,
    _token: Optional[str] = Depends(optional_verify_token),
):
    meeting = _MEETING_STORE.get(meeting_id)
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
    return meeting


@app.post("/api/meetings/{meeting_id}/speakers")
async def update_speaker_aliases(
    meeting_id: str,
    payload: SpeakerAliasRequest,
    _token: Optional[str] = Depends(optional_verify_token),
):
    meeting = _MEETING_STORE.get(meeting_id)
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
    meeting["speaker_aliases"] = payload.speaker_aliases
    return {"status": "saved", "speaker_aliases": payload.speaker_aliases}


@app.post("/api/meetings/{meeting_id}/title")
async def update_meeting_title(
    meeting_id: str,
    payload: MeetingTitleRequest,
    _token: Optional[str] = Depends(optional_verify_token),
):
    meeting = _MEETING_STORE.get(meeting_id)
    if not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
    title = payload.meeting_title.strip() or "未命名会议"
    meeting["meeting_title"] = title
    return {"status": "saved", "meeting_title": title}


@app.post("/api/meetings/{meeting_id}/summary")
async def regenerate_summary(
    meeting_id: str,
    payload: SummaryRegenerateRequest,
    _token: Optional[str] = Depends(optional_verify_token),
):
    if not qwen_service.configured:
        raise HTTPException(status_code=503, detail="DASHSCOPE_API_KEY is not configured")
    segments = _segments_from_regenerate_payload(payload)
    if not segments:
        raise HTTPException(status_code=400, detail="No transcript content available")

    module = "imported" if payload.module == "imported" else "default"
    if module == "imported" and not (payload.template_text or "").strip():
        raise HTTPException(status_code=400, detail="Imported template text is required")
    participant_names = ", ".join(payload.participants) if payload.participants else None
    try:
        summary = await qwen_service.generate_minutes(
            meeting_title=payload.meeting_title,
            participant_names=participant_names,
            segments=segments,
            template_text=payload.template_text,
            module=module,
        )
    except Exception as exc:
        logger.exception("Qwen summary regeneration failed")
        raise HTTPException(
            status_code=502,
            detail=f"Qwen meeting summary regeneration failed: {exc}",
        ) from exc

    response = {
        "status": "completed",
        "summary": summary.get("summary", ""),
        "action_items": [
            item.get("text", str(item)) if isinstance(item, dict) else str(item)
            for item in (summary.get("action_items") or [])
        ],
        "key_points": summary.get("minutes") or [],
        "full_analysis": summary.get("raw") or summary.get("summary", ""),
        "structured_action_items": summary.get("action_items") or [],
        "participants": summary.get("participants") or payload.participants,
        "meeting_time": summary.get("meeting_time") or payload.meeting_time,
    }
    meeting = _MEETING_STORE.get(meeting_id)
    if meeting is not None:
        meeting.update(response)
        if payload.meeting_title:
            meeting["meeting_title"] = payload.meeting_title
    return response


@app.post(
    "/api/meetings/{meeting_id}/translate-tts",
    response_model=TranslateTTSResponse,
)
async def translate_tts(
    meeting_id: str,
    payload: TranslateTTSRequest,
    _token: Optional[str] = Depends(optional_verify_token),
):
    meeting = _MEETING_STORE.get(meeting_id)
    source_text = resolve_translation_source_text(
        text=payload.text,
        segment_ids=payload.segment_ids,
        meeting=meeting,
    )
    if not source_text and payload.segment_ids and not meeting:
        raise HTTPException(status_code=404, detail="Meeting not found")
    if not source_text:
        raise HTTPException(status_code=400, detail="No source text selected")

    cache_key = f"{meeting_id}:{payload.target_language}:{source_text}"
    if cache_key in _TRANSLATION_CACHE:
        return _TRANSLATION_CACHE[cache_key]
    try:
        result = await qwen_service.translate_and_tts(
            text=source_text,
            target_language=payload.target_language,
            meeting_id=meeting_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("translate_tts failed")
        raise HTTPException(status_code=502, detail=f"Translation/TTS failed: {exc}") from exc
    _TRANSLATION_CACHE[cache_key] = result
    return result


@app.get("/api/tts-audio/{file_name}")
async def get_tts_audio(file_name: str):
    safe_name = os.path.basename(file_name)
    audio_path = Path(settings.TTS_AUDIO_CACHE_DIR) / safe_name
    if not audio_path.exists():
        raise HTTPException(status_code=404, detail="Audio not found")
    return FileResponse(audio_path, media_type="audio/wav", filename=safe_name)


@app.get("/api/supported-languages")
async def get_supported_languages():
    return {
        "languages": [
            {"code": "zh", "name": "Mandarin", "native": "普通话"},
            {"code": "yue", "name": "Cantonese", "native": "粤语"},
            {"code": "en", "name": "English", "native": "English"},
            {"code": "ja", "name": "Japanese", "native": "日本語"},
            {"code": "fr", "name": "French", "native": "Français"},
            {"code": "auto", "name": "Auto", "native": "自动识别"},
        ],
        "translation_languages": ["english", "japanese", "cantonese", "mandarin", "french"],
        "features": {
            "speaker_diarization": True,
            "meeting_minutes": True,
            "translation_tts": True,
        },
    }


@app.get("/api/meeting-types")
async def get_meeting_types():
    return {
        "types": [
            {"id": "meeting", "name": "Meeting", "description": "Business meetings"},
            {"id": "interview", "name": "Interview", "description": "Interviews"},
            {"id": "lecture", "name": "Lecture", "description": "Educational content"},
            {"id": "call", "name": "Call", "description": "Phone/video calls"},
            {"id": "chat", "name": "Chat", "description": "Casual conversations"},
            {"id": "brainstorm", "name": "Brainstorm", "description": "Creative sessions"},
        ],
        "default": "meeting",
    }


async def _process_audio_upload(
    *,
    audio_file: UploadFile,
    meeting_type: str,
    language: str,
    meeting_title: Optional[str],
    participant_names: Optional[str],
    generate_summary: bool,
) -> TranscriptionResponse:
    session_id = str(uuid.uuid4())
    normalized_type = (meeting_type or "").strip().lower()
    if normalized_type not in _VALID_MEETING_TYPES:
        normalized_type = "meeting"

    content = await audio_file.read()
    file_size_mb = len(content) / (1024 * 1024)
    if not content:
        return _generate_demo_response(session_id, normalized_type, meeting_title)
    if file_size_mb > 500:
        raise HTTPException(status_code=413, detail="Upload exceeds 500 MB limit")
    if not asr_service.configured or not oss_service.configured:
        raise HTTPException(
            status_code=503,
            detail=(
                "Aliyun ASR/OSS is not configured. Set DASHSCOPE_API_KEY and "
                "ALIYUN_OSS_* environment variables."
            ),
        )

    orig_ext = os.path.splitext(audio_file.filename or "")[1].lower() or ".bin"
    with tempfile.NamedTemporaryFile(delete=False, suffix=orig_ext) as tmp:
        tmp.write(content)
        tmp_path = tmp.name
    processed_path = ""
    try:
        try:
            processed_path = await audio_processor.process_for_transcription(tmp_path)
        except AudioProcessingError as exc:
            raise HTTPException(status_code=400, detail=f"Audio could not be decoded: {exc}") from exc
        duration = await audio_processor.get_audio_duration(processed_path)
        file_url = oss_service.upload_file(processed_path, suffix=".mp3")
        language_hints = _language_hints(language)
        segments, raw_asr = await asr_service.transcribe(
            file_url,
            language_hints=language_hints,
        )
        if not segments:
            raise HTTPException(status_code=502, detail="ASR returned no transcript segments")
        summary = _summary_from_segments(
            meeting_title=meeting_title,
            participant_names=participant_names,
            segments=segments,
        )
        if generate_summary:
            try:
                summary = await qwen_service.generate_minutes(
                    meeting_title=meeting_title,
                    participant_names=participant_names,
                    segments=segments,
                )
            except Exception as exc:
                logger.exception("Qwen summary failed")
                raise HTTPException(
                    status_code=502,
                    detail=f"Qwen meeting summary failed: {exc}",
                ) from exc
        response = _build_response(
            session_id=session_id,
            meeting_type=normalized_type,
            meeting_title=meeting_title,
            language=language,
            duration=duration,
            file_size_mb=file_size_mb,
            segments=segments,
            summary=summary,
        )
        _MEETING_STORE[session_id] = {
            **response.model_dump(),
            "status": "completed",
            "speaker_aliases": {},
            "raw_asr": raw_asr,
        }
        return response
    finally:
        for path in (tmp_path, processed_path):
            if path and os.path.exists(path):
                os.unlink(path)


def _build_response(
    *,
    session_id: str,
    meeting_type: str,
    meeting_title: Optional[str],
    language: str,
    duration: float,
    file_size_mb: float,
    segments: list[TranscriptSegment],
    summary: dict[str, Any],
) -> TranscriptionResponse:
    transcript = transcript_text_from_segments(segments)
    structured_actions = summary.get("action_items") or []
    return TranscriptionResponse(
        success=True,
        session_id=session_id,
        transcription_id=str(uuid.uuid4()),
        transcription=transcript,
        summary=summary.get("summary", ""),
        action_items=[
            item.get("text", str(item)) if isinstance(item, dict) else str(item)
            for item in structured_actions
        ],
        key_points=summary.get("minutes") or [],
        full_analysis=summary.get("raw") or summary.get("summary", ""),
        transcript_segments=[seg.as_dict() for seg in segments],
        structured_action_items=structured_actions,
        participants=summary.get("participants") or [],
        meeting_time=summary.get("meeting_time"),
        meeting_type=meeting_type,
        meeting_title=meeting_title or "未命名会议",
        language=language,
        detected_language=LanguageInfo(
            code=language or "zh",
            name=_language_name(language),
            native=_language_native(language),
            script="simplified" if language in {"zh", "mandarin"} else "latin",
            confidence=1.0,
        ),
        duration_minutes=round(duration / 60, 2),
        word_count=len(transcript),
        participant_count=len(summary.get("participants") or []),
        created_at=datetime.now().isoformat(),
        file_size_mb=round(file_size_mb, 2),
    )


def _summary_from_segments(
    *,
    meeting_title: Optional[str],
    participant_names: Optional[str],
    segments: list[TranscriptSegment],
) -> dict[str, Any]:
    participants = (
        [p.strip() for p in participant_names.split(",") if p.strip()]
        if participant_names
        else sorted({seg.speaker_id for seg in segments})
    )
    minutes = [seg.text for seg in segments[:8]]
    action_items: list[Any] = []
    return {
        "meeting_time": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "participants": participants,
        "minutes": minutes,
        "action_items": action_items,
        "summary": render_meeting_minutes(
            meeting_time=datetime.now().strftime("%Y-%m-%d %H:%M"),
            participants=participants,
            minutes=minutes,
            action_items=[],
        ),
        "raw": "",
    }


def _segments_from_regenerate_payload(
    payload: SummaryRegenerateRequest,
) -> list[TranscriptSegment]:
    segments: list[TranscriptSegment] = []
    for index, raw in enumerate(payload.transcript_segments):
        text = str(raw.get("text") or "").strip()
        if not text:
            continue
        start_ms = raw.get("start_ms")
        end_ms = raw.get("end_ms")
        segments.append(
            TranscriptSegment(
                speaker_id=str(raw.get("speaker_id") or f"speaker_{index + 1}"),
                start_ms=int(start_ms) if isinstance(start_ms, (int, float)) else index * 30_000,
                end_ms=int(end_ms) if isinstance(end_ms, (int, float)) else (index + 1) * 30_000,
                text=text,
            )
        )
    if segments:
        return segments
    return parse_speaker_lines(payload.transcription)


def _generate_demo_response(
    session_id: str,
    meeting_type: str,
    meeting_title: Optional[str],
) -> TranscriptionResponse:
    transcript = """Speaker 1: 仓库区域要加强防雨和防风，电灯错开开启，节约用电。
Speaker 2: ITSM 和自主改善提报要抓紧完成，月底前关闭。
Speaker 3: 仓库人员也提到了防雨遮盖问题，要马上处理。
Speaker 4: 我同意，防雨防风物料要及时配好，异常第一时间通知采购。"""
    segments = parse_speaker_lines(transcript)
    summary = {
        "meeting_time": "示例会议",
        "participants": sorted({seg.speaker_id for seg in segments}),
        "minutes": [
            "各组长汇报工作进度，仓库区域重点关注防雨、防风和照明节电。",
            "ITSM 与自主改善事项需要在月底前完成关闭。",
            "防雨防风物料被多名参会人反复提到，应作为重点待办跟进。",
        ],
        "action_items": [
            {
                "text": "补齐仓库防雨防风物料并完成现场遮盖检查",
                "owner": "仓库",
                "due": "尽快",
                "speaker_ids": ["speaker_1", "speaker_3", "speaker_4"],
                "speaker_count": 3,
                "is_important": True,
                "evidence": ["仓库区域要加强防雨和防风", "防雨遮盖问题", "防雨防风物料要及时配好"],
            }
        ],
        "raw": "",
    }
    summary["summary"] = render_meeting_minutes(
        meeting_time=summary["meeting_time"],
        participants=summary["participants"],
        minutes=summary["minutes"],
        action_items=[],
    )
    # Keep action text in the rendered summary with important marker.
    summary["summary"] += "\n待办事项:\n1. 【重要】补齐仓库防雨防风物料并完成现场遮盖检查（负责人：仓库）（截止：尽快）"
    response = _build_response(
        session_id=session_id,
        meeting_type=meeting_type,
        meeting_title=meeting_title or "示例会议纪要",
        language="zh",
        duration=180,
        file_size_mb=0,
        segments=segments,
        summary=summary,
    )
    _MEETING_STORE[session_id] = {**response.model_dump(), "status": "completed"}
    return response


def _language_hints(language: str) -> list[str]:
    value = (language or "").lower()
    if value in {"en", "english"}:
        return ["en"]
    if value in {"ja", "japanese"}:
        return ["ja"]
    if value in {"fr", "french"}:
        return ["fr"]
    return ["zh", "en"]


def _language_name(language: str) -> str:
    return {
        "en": "English",
        "ja": "Japanese",
        "fr": "French",
        "yue": "Cantonese",
        "zh": "Mandarin",
    }.get((language or "").lower(), "Auto")


def _language_native(language: str) -> str:
    return {
        "en": "English",
        "ja": "日本語",
        "fr": "Français",
        "yue": "粤语",
        "zh": "普通话",
    }.get((language or "").lower(), "自动识别")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level="info",
    )
